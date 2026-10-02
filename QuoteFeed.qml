import QtQuick
import Quickshell
import "SymbolID.js" as SymbolID
import "Market.js" as Market
import "YahooAdapter.js" as Yahoo
import "TWSEAdapter.js" as TWSE

// The quote engine.
//
// Yahoo answers one symbol per request and rate-limits hard per IP, so requests
// are serialised through a queue with a spacing delay rather than fired as a
// fan-out. A watchlist of twenty symbols therefore refreshes over twenty
// seconds, which is well inside a 60-second cadence and never trips the limit.
//
// Nothing polls a closed market. A Tokyo row at 3am Tokyo time cannot have
// moved, and spending a request on it only brings the rate limit closer for the
// rows that can. The first pass after the panel opens is exempt: an empty row
// has to be filled once before session logic can decide it is not worth
// refilling.
//
// Taiwanese rows ride two lanes. Yahoo's queue quotes them like any other
// market — that is their intraday line and their price whenever the exchange
// has none — and a second, batched lane asks TWSE for them in batches of up to
// fifty, at least three seconds apart. The panel's model merges the
// two, so the live price wins without the delayed one ever rolling it back.
QtObject {
  id: root

  property bool active: false
  property var symbols: []
  property int pollIntervalSeconds: 60

  // "idle" before anything is asked for, "loading" while the queue drains,
  // "live" once every reachable row has a price, "error" when none does.
  property string status: "idle"
  property int inFlight: 0
  property int completed: 0
  property int failed: 0
  property double lastCompletedMs: 0

  signal quoteReceived(var quote)
  signal quoteFailed(string symbol, string message)

  property var _queue: []
  property bool _draining: false
  property var _seeded: ({})
  property var _twseQueue: []
  property bool _twseDraining: false
  property var _twseSeeded: ({})

  function _key(symbol) { return SymbolID.toString(symbol) }

  // Whether this row is worth a request now. A symbol that has never been
  // fetched by this lane in this session always is.
  function _shouldFetch(parsed, nowMs, seeded) {
    if (!seeded[_key(parsed)]) return true
    return Market.isOpen(parsed.market, nowMs)
  }

  function _enqueue(force) {
    var nowMs = Date.now()
    var queue = []
    var twse = []
    for (var i = 0; i < root.symbols.length; i++) {
      var parsed = SymbolID.parse(root.symbols[i])
      if (!parsed) continue
      if (Yahoo.supports(parsed) && (force || root._shouldFetch(parsed, nowMs, root._seeded))) queue.push(parsed)
      if (TWSE.supports(parsed) && (force || root._shouldFetch(parsed, nowMs, root._twseSeeded))) twse.push(parsed)
    }
    root._queue = queue
    root._twseQueue = TWSE.batches(twse)
    if (queue.length > 0 && root.status !== "live") root.status = "loading"
    root._drain()
    root._drainTwse()
  }

  function _drain() {
    if (root._draining || !root.active) return
    if (root._queue.length === 0) {
      root.status = (root.completed > 0) ? "live" : (root.failed > 0 ? "error" : "idle")
      return
    }
    root._draining = true
    var next = root._queue.shift()
    root._request(next)
  }

  function _finish() {
    root._draining = false
    root.inFlight = Math.max(0, root.inFlight - 1)
    if (root._queue.length > 0) spacing.restart()
    else root._drain()
  }

  function _request(parsed) {
    var spec = Yahoo.requestFor(parsed)
    if (!spec) { root._finish(); return }

    root.inFlight = root.inFlight + 1
    var xhr = new XMLHttpRequest()
    xhr.open("GET", spec.url)
    // The queue is serial: one request that never completes freezes every row
    // behind it, with no error to show why. A network that has stopped
    // answering must become a failed row, not a stuck panel.
    xhr.timeout = 10000
    // Yahoo serves an empty body to clients it does not recognise as browsers.
    xhr.setRequestHeader("User-Agent", "Mozilla/5.0 (X11; Linux x86_64) Pulse/0.1 (+https://www.pulseticker.app)")
    xhr.setRequestHeader("Accept", "application/json")
    xhr.onreadystatechange = function () {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      var key = root._key(parsed)
      if (xhr.status === 429) {
        root.failed = root.failed + 1
        root.quoteFailed(key, "rate limited")
      } else if (xhr.status < 200 || xhr.status >= 300) {
        root.failed = root.failed + 1
        root.quoteFailed(key, xhr.status === 0 ? "offline" : ("HTTP " + xhr.status))
      } else {
        var quote = null
        try {
          quote = Yahoo.parseQuote(parsed, JSON.parse(xhr.responseText), spec.extended)
        } catch (e) {
          quote = null
        }
        if (quote) {
          root._seeded[key] = true
          root.completed = root.completed + 1
          root.lastCompletedMs = Date.now()
          root.quoteReceived(quote)
        } else {
          root.failed = root.failed + 1
          root.quoteFailed(key, "no quote")
        }
      }
      root._finish()
    }
    xhr.send()
  }

  function _drainTwse() {
    if (root._twseDraining || !root.active || root._twseQueue.length === 0) return
    if (twseSpacing.running) return
    root._twseDraining = true
    root._requestTwse(root._twseQueue.shift())
  }

  function _finishTwse() {
    root._twseDraining = false
    twseSpacing.restart()
  }

  // A miss on this lane is not a failure. Yahoo quotes every Taiwanese row
  // too, and whether a row shows an error is that lane's call; this one only
  // ever improves a price. A miss is seeded all the same, so a row the exchange
  // never prices is not asked again every poll after the close.
  function _requestTwse(batch) {
    var spec = TWSE.requestFor(batch)
    if (!spec) { root._finishTwse(); return }

    var xhr = new XMLHttpRequest()
    xhr.open("GET", spec.url)
    xhr.timeout = 10000
    xhr.setRequestHeader("User-Agent", "Mozilla/5.0 (X11; Linux x86_64) Pulse/0.1 (+https://www.pulseticker.app)")
    xhr.setRequestHeader("Accept", "application/json")
    xhr.onreadystatechange = function () {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      if (xhr.status >= 200 && xhr.status < 300) {
        var quotes = []
        try {
          quotes = TWSE.parseQuotes(batch, JSON.parse(xhr.responseText), Date.now())
        } catch (e) {
          quotes = []
        }
        for (var j = 0; j < batch.length; j++) root._twseSeeded[root._key(batch[j])] = true
        for (var i = 0; i < quotes.length; i++) {
          root.completed = root.completed + 1
          root.lastCompletedMs = Date.now()
          root.quoteReceived(quotes[i])
        }
      }
      root._finishTwse()
    }
    xhr.send()
  }

  function refresh() {
    root.completed = 0
    root.failed = 0
    root._enqueue(true)
  }

  // Between two requests, not between two rounds: this is the rate limit, and
  // it is the reason the queue exists at all.
  property Timer spacing: Timer {
    id: spacing
    interval: Yahoo.DESCRIPTOR.rateLimit.minIntervalMs
    repeat: false
    onTriggered: root._drain()
  }

  // TWSE's own pacing, independent of Yahoo's: the two hosts have separate
  // limits, and one lane waiting must not hold up the other.
  property Timer twseSpacing: Timer {
    id: twseSpacing
    interval: TWSE.DESCRIPTOR.rateLimit.minIntervalMs
    repeat: false
    onTriggered: root._drainTwse()
  }

  property Timer poll: Timer {
    interval: Math.max(15, root.pollIntervalSeconds) * 1000
    repeat: true
    running: root.active
    onTriggered: root._enqueue(false)
  }

  onActiveChanged: {
    if (root.active) root._enqueue(false)
    else {
      root._queue = []
      root._twseQueue = []
    }
  }

  onSymbolsChanged: {
    if (root.active) root._enqueue(false)
  }
}
