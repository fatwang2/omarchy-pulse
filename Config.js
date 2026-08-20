// The config file's shape, and every operation that changes it.
//
// Kept out of QML so the migration and the list arithmetic can be tested under
// `node --test`, where a wrong answer is a failed assertion rather than a
// watchlist someone has to rebuild by hand.

.import "SymbolID.js" as SymbolID

var VERSION = 2
var DEFAULT_LIST_NAME = "Watching"
var BAR_MODES = ["icon", "pinned", "carousel"]

function trimmed(value) {
  return String(value === null || value === undefined ? "" : value).replace(/^\s+|\s+$/g, "")
}

function clampInt(value, fallback, minimum, maximum) {
  var n = Number(value)
  if (!isFinite(n)) return fallback
  return Math.max(minimum, Math.min(maximum, Math.round(n)))
}

// The canonical spelling of a symbol, or "" if it cannot become a row. Writing
// canonical means `00700.HK` becomes `700.HK` on the first edit and is stable
// from then on.
function canonical(raw) {
  var parsed = SymbolID.parse(raw)
  return parsed ? SymbolID.toString(parsed) : ""
}

function canonicalList(values) {
  var source = (values && typeof values.length === "number") ? values : []
  var out = []
  var seen = {}
  for (var i = 0; i < source.length; i++) {
    var key = canonical(source[i])
    if (!key || seen[key]) continue
    seen[key] = true
    out.push(key)
  }
  return out
}

// --- Parsing --------------------------------------------------------------

function emptyConfig() {
  return {
    version: VERSION,
    lists: [{ name: DEFAULT_LIST_NAME, symbols: [] }],
    activeList: DEFAULT_LIST_NAME,
    pollIntervalSeconds: 60,
    barDisplay: "icon",
    pinnedSymbol: "",
    carouselIntervalSeconds: 6,
    passthrough: {}
  }
}

var KNOWN_KEYS = ["version", "lists", "activeList", "symbols", "pollIntervalSeconds",
                  "barDisplay", "pinnedSymbol", "carouselIntervalSeconds"]

// A list name has to survive being a tab label and a lookup key. Empty names
// and duplicates are the two that break one or the other.
function uniqueName(name, taken, fallback) {
  var base = trimmed(name) || fallback
  if (taken.indexOf(base) < 0) return base
  for (var n = 2; n < 1000; n++) {
    var candidate = base + " " + n
    if (taken.indexOf(candidate) < 0) return candidate
  }
  return base + " " + Date
}

function parseLists(raw) {
  var source = (raw && typeof raw.length === "number") ? raw : []
  var lists = []
  var names = []
  for (var i = 0; i < source.length; i++) {
    var entry = source[i] || {}
    var name = uniqueName(entry.name, names, "List " + (i + 1))
    names.push(name)
    lists.push({ name: name, symbols: canonicalList(entry.symbols) })
  }
  return lists
}

// Reads any version of the file. A v1 file has a bare `symbols` array and no
// lists; it becomes one list rather than being rejected, because the user's
// watchlist predates the feature that split it into several.
function parse(raw) {
  var text = trimmed(raw)
  if (!text) return emptyConfig()

  var parsed = JSON.parse(text)
  var config = emptyConfig()

  var lists = parseLists(parsed.lists)
  if (lists.length === 0) {
    lists = [{ name: DEFAULT_LIST_NAME, symbols: canonicalList(parsed.symbols) }]
  }
  config.lists = lists

  var active = trimmed(parsed.activeList)
  config.activeList = listIndex(config, active) >= 0 ? active : lists[0].name

  // Yahoo rate-limits per IP, so the floor is not a preference.
  config.pollIntervalSeconds = clampInt(parsed.pollIntervalSeconds, 60, 15, 3600)
  var display = trimmed(parsed.barDisplay)
  config.barDisplay = BAR_MODES.indexOf(display) >= 0 ? display : "icon"
  config.pinnedSymbol = canonical(parsed.pinnedSymbol)
  config.carouselIntervalSeconds = clampInt(parsed.carouselIntervalSeconds, 6, 2, 120)

  // Keys this version does not understand are carried through a write
  // untouched. A newer Pulse's settings must survive being edited by an older
  // one, and silently dropping them is the one failure a user cannot see.
  var extra = {}
  for (var key in parsed) {
    if (KNOWN_KEYS.indexOf(key) < 0) extra[key] = parsed[key]
  }
  config.passthrough = extra
  return config
}

function serialize(config) {
  var payload = {}
  for (var key in config.passthrough) payload[key] = config.passthrough[key]
  payload.version = VERSION
  payload.lists = config.lists.map(function (list) {
    return { name: list.name, symbols: list.symbols.slice() }
  })
  payload.activeList = config.activeList
  payload.pollIntervalSeconds = config.pollIntervalSeconds
  payload.barDisplay = config.barDisplay
  payload.pinnedSymbol = config.pinnedSymbol
  payload.carouselIntervalSeconds = config.carouselIntervalSeconds
  return JSON.stringify(payload, null, 2) + "\n"
}

// --- Reading --------------------------------------------------------------

function listIndex(config, name) {
  for (var i = 0; i < config.lists.length; i++) {
    if (config.lists[i].name === name) return i
  }
  return -1
}

function activeIndex(config) {
  var index = listIndex(config, config.activeList)
  return index >= 0 ? index : 0
}

function activeSymbols(config) {
  var list = config.lists[activeIndex(config)]
  return list ? list.symbols.slice() : []
}

function listNames(config) {
  return config.lists.map(function (list) { return list.name })
}

// Every symbol on every list, deduplicated. The feed subscribes to this rather
// than to the active list: switching tabs then shows prices instead of an
// empty list that has to refetch, and the bar's pinned quote keeps working
// while another tab is open.
function allSymbols(config) {
  var out = []
  var seen = {}
  for (var i = 0; i < config.lists.length; i++) {
    var symbols = config.lists[i].symbols
    for (var j = 0; j < symbols.length; j++) {
      if (seen[symbols[j]]) continue
      seen[symbols[j]] = true
      out.push(symbols[j])
    }
  }
  return out
}

function contains(config, raw) {
  return activeSymbols(config).indexOf(canonical(raw)) >= 0
}

// --- Writing --------------------------------------------------------------
//
// Every function returns a new config rather than mutating, so a rejected edit
// is the same object back and the caller can skip the write.

function withLists(config, lists) {
  var next = {}
  for (var key in config) next[key] = config[key]
  next.lists = lists
  return next
}

function replaceActive(config, symbols) {
  var lists = config.lists.slice()
  var index = activeIndex(config)
  lists[index] = { name: lists[index].name, symbols: symbols }
  return withLists(config, lists)
}

function addSymbol(config, raw) {
  var key = canonical(raw)
  if (!key || contains(config, key)) return config
  return replaceActive(config, activeSymbols(config).concat([key]))
}

function removeSymbol(config, raw) {
  var symbols = activeSymbols(config)
  var index = symbols.indexOf(canonical(raw))
  if (index < 0) return config
  symbols.splice(index, 1)
  var next = replaceActive(config, symbols)
  // A pinned symbol that is no longer on any list would keep naming a bar
  // quote that can never arrive.
  if (allSymbols(next).indexOf(next.pinnedSymbol) < 0) {
    next.pinnedSymbol = allSymbols(next)[0] || ""
  }
  return next
}

function moveSymbol(config, raw, delta) {
  var symbols = activeSymbols(config)
  var index = symbols.indexOf(canonical(raw))
  if (index < 0) return config
  var target = index + delta
  if (target < 0 || target >= symbols.length) return config
  symbols.splice(target, 0, symbols.splice(index, 1)[0])
  return replaceActive(config, symbols)
}

function selectList(config, name) {
  if (listIndex(config, name) < 0) return config
  var next = {}
  for (var key in config) next[key] = config[key]
  next.activeList = name
  return next
}

function addList(config, name) {
  var created = uniqueName(name, listNames(config), "List " + (config.lists.length + 1))
  var next = withLists(config, config.lists.concat([{ name: created, symbols: [] }]))
  next.activeList = created
  return next
}

function renameList(config, from, to) {
  var index = listIndex(config, from)
  if (index < 0) return config
  var taken = listNames(config)
  taken.splice(index, 1)
  var created = uniqueName(to, taken, from)
  var lists = config.lists.slice()
  lists[index] = { name: created, symbols: lists[index].symbols }
  var next = withLists(config, lists)
  if (next.activeList === from) next.activeList = created
  return next
}

function removeList(config, name) {
  var index = listIndex(config, name)
  // The last list is not removable. A file with no lists has nowhere to put
  // the next symbol, and an empty tab strip reads as a broken panel.
  if (index < 0 || config.lists.length <= 1) return config
  var lists = config.lists.slice()
  lists.splice(index, 1)
  var next = withLists(config, lists)
  if (next.activeList === name) next.activeList = lists[Math.min(index, lists.length - 1)].name
  if (allSymbols(next).indexOf(next.pinnedSymbol) < 0) {
    next.pinnedSymbol = allSymbols(next)[0] || ""
  }
  return next
}

function setValue(config, key, value) {
  var next = {}
  for (var name in config) next[name] = config[name]
  switch (key) {
    case "barDisplay":
      next.barDisplay = BAR_MODES.indexOf(trimmed(value)) >= 0 ? trimmed(value) : "icon"
      break
    case "pinnedSymbol":
      next.pinnedSymbol = canonical(value)
      break
    case "pollIntervalSeconds":
      next.pollIntervalSeconds = clampInt(value, 60, 15, 3600)
      break
    case "carouselIntervalSeconds":
      next.carouselIntervalSeconds = clampInt(value, 6, 2, 120)
      break
    default:
      return config
  }
  return next
}

if (typeof module !== "undefined") module.exports = {
  VERSION: VERSION,
  DEFAULT_LIST_NAME: DEFAULT_LIST_NAME,
  BAR_MODES: BAR_MODES,
  canonical: canonical,
  canonicalList: canonicalList,
  emptyConfig: emptyConfig,
  parse: parse,
  serialize: serialize,
  listIndex: listIndex,
  activeIndex: activeIndex,
  activeSymbols: activeSymbols,
  listNames: listNames,
  allSymbols: allSymbols,
  contains: contains,
  addSymbol: addSymbol,
  removeSymbol: removeSymbol,
  moveSymbol: moveSymbol,
  selectList: selectList,
  addList: addList,
  renameList: renameList,
  removeList: removeList,
  setValue: setValue
}
