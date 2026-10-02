import QtQuick
import "YahooAdapter.js" as Yahoo
import "TWSEAdapter.js" as TWSE
import "Search.js" as Search

// Symbol lookup for the settings view.
//
// Typing is throttled rather than sent per keystroke: Yahoo rate-limits per IP
// and the same budget pays for the quotes on screen. A request already in
// flight is superseded rather than cancelled, and a late response for an older
// query is dropped — otherwise a fast typist sees results for a prefix they
// have already finished typing.
//
// A code or Chinese text is also matched against the Taiwanese exchanges'
// listings, which answer exactly what Yahoo cannot: Yahoo answers 400 to
// Chinese text, and does not know which Taiwanese board a bare code is on. The
// exchanges' results lead the merged list. Their lists are fetched once, on
// the first search that needs them, and matched locally from then on — two
// requests a day rather than one per query. Each lane is tagged with the query it
// answered, and only lanes that answered the query now pending are shown, so
// two queries' answers never mix; the previous list stays until a lane has
// something to show for the new one. Yahoo's faults always speak; its hints
// speak only when neither lane found anything.
QtObject {
  id: root

  property string query: ""
  property var results: []
  property bool searching: false
  property string message: ""

  property string _pendingQuery: ""
  property string _servedQuery: ""
  property var _yahooResults: []
  property var _twseResults: []
  property string _yahooQuery: ""
  property string _twseQuery: ""
  property string _yahooFault: ""
  property string _yahooHint: ""
  property bool _yahooPending: false
  property bool _twsePending: false

  // The exchanges' listings change once a trading day. Twelve hours keeps a
  // panel left open across days current without refetching within one, and a
  // failed fetch is not retried for a minute however fast the user types.
  readonly property int _twseIndexTtlMs: 12 * 60 * 60 * 1000
  readonly property int _twseRetryMs: 60 * 1000
  property var _twseIndex: []
  property double _twseIndexMs: 0
  property double _twseFailedMs: 0
  property bool _twseLoading: false

  function clear() {
    root.query = ""
    root._reset()
    debounce.stop()
  }

  function _reset() {
    root._yahooResults = []
    root._twseResults = []
    root._yahooFault = ""
    root._yahooHint = ""
    root._yahooQuery = ""
    root._twseQuery = ""
    root._pendingQuery = ""
    root._yahooPending = false
    root._twsePending = false
    root._publish()
  }

  // Both lanes publish through here, so the list and its message always
  // describe the same answers. The previous complete list stays until the
  // exchange has rows for the pending query, or Yahoo has rows or the exchange
  // is no longer pending. Yahoo's empty answer to Chinese text, usually first,
  // must not blank the list while the exchange is still on its way.
  function _publish() {
    var q = root._pendingQuery
    var yahooIn = root._yahooQuery === q
    var twseIn = root._twseQuery === q
    root.searching = root._yahooPending || root._twsePending
    var yahooShows = yahooIn && (root._yahooResults.length > 0 || !root._twsePending)
    var twseShows = twseIn && root._twseResults.length > 0
    if (!yahooShows && !twseShows) return
    root.results = Search.merge([
      twseIn ? root._twseResults : [],
      yahooIn ? root._yahooResults : []
    ])
    if (yahooIn && root._yahooFault !== "") root.message = root._yahooFault
    else if (yahooIn && !root.searching && root.results.length === 0) root.message = root._yahooHint
    else root.message = ""
  }

  function _run(text) {
    var spec = Yahoo.searchRequest(text)
    if (!spec) {
      root._reset()
      return
    }
    root._pendingQuery = spec.query

    var twseWanted = TWSE.searchable(spec.query) !== null
    // A stale index still answers at once while a fresh one is fetched.
    var twseReady = twseWanted && root._twseIndex.length > 0
    if (!twseWanted || twseReady) root._matchTwse(spec.query)
    root._twsePending = twseWanted && !twseReady
    root._yahooPending = true
    root._publish()

    root._runYahoo(spec)
    if (twseWanted && Date.now() - root._twseIndexMs >= root._twseIndexTtlMs) root._loadTwseIndex()
  }

  function _runYahoo(spec) {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", spec.url)
    xhr.timeout = 8000
    xhr.setRequestHeader("User-Agent", "Mozilla/5.0 (X11; Linux x86_64) Pulse/0.1 (+https://www.pulseticker.app)")
    xhr.setRequestHeader("Accept", "application/json")
    xhr.onreadystatechange = function () {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      // A response for a query the user has moved past is not an answer.
      if (spec.query !== root._pendingQuery) return
      root._yahooPending = false
      root._servedQuery = spec.query
      root._yahooQuery = spec.query
      root._yahooFault = ""
      root._yahooHint = ""

      if (xhr.status === 400) {
        // Yahoo answers 400 to queries its index cannot parse, which includes
        // Chinese, Japanese and Korean text. That is an empty result, not a
        // fault: a code the user typed still resolves locally, and Taiwanese
        // names come from the exchange's own lane.
        root._yahooResults = Yahoo.parseSearch(null, spec.query)
        root._yahooHint = "Yahoo indexes English names and tickers. Try a code, like 600519.SH."
      } else if (xhr.status === 429) {
        root._yahooResults = Yahoo.parseSearch(null, spec.query)
        root._yahooFault = "Rate limited. Try again in a moment."
      } else if (xhr.status < 200 || xhr.status >= 300) {
        root._yahooResults = Yahoo.parseSearch(null, spec.query)
        root._yahooFault = xhr.status === 0 ? "Offline." : ("Search failed (HTTP " + xhr.status + ").")
      } else {
        var parsed = []
        try {
          parsed = Yahoo.parseSearch(JSON.parse(xhr.responseText), spec.query)
        } catch (e) {
          parsed = Yahoo.parseSearch(null, spec.query)
        }
        root._yahooResults = parsed
        root._yahooHint = "Nothing found for “" + spec.query + "”."
      }
      root._publish()
    }
    xhr.send()
  }

  function _matchTwse(query) {
    root._twseResults = TWSE.searchable(query) !== null ? TWSE.searchNames(root._twseIndex, query) : []
    root._twseQuery = query
  }

  // Silent on failure: Yahoo's lane carries the messaging, and a listing that
  // did not arrive is simply no extra results. One board's list is better than
  // none, but it is not kept as fresh, so the next search past the retry
  // window asks again.
  function _loadTwseIndex() {
    if (root._twseLoading) return
    if (Date.now() - root._twseFailedMs < root._twseRetryMs) {
      root._twseIndexSettled()
      return
    }
    root._twseLoading = true
    var lists = TWSE.NAME_LISTS
    var loaded = []
    var remaining = lists.length
    var failed = false
    for (var i = 0; i < lists.length; i++) {
      (function (list, slot) {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", list.url)
        // TPEx's file is several megabytes.
        xhr.timeout = 30000
        xhr.setRequestHeader("User-Agent", "Mozilla/5.0 (X11; Linux x86_64) Pulse/0.1 (+https://www.pulseticker.app)")
        xhr.setRequestHeader("Accept", "application/json")
        xhr.onreadystatechange = function () {
          if (xhr.readyState !== XMLHttpRequest.DONE) return
          var entries = []
          if (xhr.status >= 200 && xhr.status < 300) {
            try {
              entries = TWSE.parseNameList(list.market, JSON.parse(xhr.responseText))
            } catch (e) {
              entries = []
            }
          }
          if (entries.length === 0) failed = true
          loaded[slot] = entries
          remaining = remaining - 1
          if (remaining > 0) return
          var index = []
          for (var j = 0; j < loaded.length; j++) index = index.concat(loaded[j] || [])
          root._twseLoading = false
          if (failed) root._twseFailedMs = Date.now()
          else root._twseIndexMs = Date.now()
          if (!failed || root._twseIndex.length === 0) root._twseIndex = index
          root._twseIndexSettled()
        }
        xhr.send()
      })(lists[i], i)
    }
  }

  // Whatever the index now holds answers the query pending now, which may not
  // be the one that asked for it.
  function _twseIndexSettled() {
    if (!root._twsePending) return
    root._twsePending = false
    root._matchTwse(root._pendingQuery)
    root._publish()
  }

  onQueryChanged: {
    var text = String(root.query || "").replace(/^\s+|\s+$/g, "")
    if (!text) {
      root._reset()
      debounce.stop()
      return
    }
    if (text === root._servedQuery) return
    debounce.restart()
  }

  property Timer debounce: Timer {
    id: debounce
    interval: 350
    repeat: false
    onTriggered: root._run(root.query)
  }
}
