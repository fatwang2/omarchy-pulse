// TWSE Market Info (mis.twse.com.tw), the exchange's own public quote feed.
//
// There is no PulseCore source to port here. Taiwan arrived in Pulse for macOS
// 0.15.10, after the app stopped being open source, so what follows is that
// release's behaviour as observed — endpoints, field precedence, pacing and
// the search filter — re-expressed, with the two departures marked where they
// happen: the nested trade price, and search reading the exchanges' daily
// files rather than MIS's name index.
//
// Unlike Yahoo, one request carries many symbols, so this source is batched.
// It quotes both Taiwanese boards and their two benchmark indices and has no
// candles or intraday series: charts and the row's line stay on Yahoo, which
// also quotes every Taiwanese row and is what remains when this source has no
// price.

.import "SymbolID.js" as SymbolID

var ID = "twse"
var NAME = "TWSE Market Info"
var QUOTE_URL = "https://mis.twse.com.tw/stock/api/getStockInfo.jsp"

var MARKETS = ["tw", "two"]

// The macOS app spaces requests to this host three seconds apart. Fifty
// channels is well inside what one request answers — 120 was measured.
var DESCRIPTOR = {
  id: ID,
  name: NAME,
  markets: MARKETS,
  capabilities: ["quotes", "search"],
  delay: { tw: 0, two: 0 },
  rateLimit: { minIntervalMs: 3000, batchSize: 50 },
  suggestedPollIntervalMs: 15000
}

var BOARD_PREFIX = { tw: "tse", two: "otc" }
var INDEX_CHANNEL = { taiex: "tse_t00", tpex: "otc_o00" }

function trimmed(value) {
  return String(value === null || value === undefined ? "" : value).replace(/^\s+|\s+$/g, "")
}

// The MIS channel without its `.tw` tail — which is also how a response row
// names itself, as `ex + "_" + c`. MIS ignores Yahoo's `.TWO`: the board is
// the prefix.
function channelKey(symbol) {
  if (!symbol) return null
  if (SymbolID.isIndex(symbol)) return INDEX_CHANNEL[symbol.id] || null
  if (symbol.kind !== SymbolID.KIND_SECURITY) return null
  var prefix = BOARD_PREFIX[symbol.market]
  return prefix ? prefix + "_" + symbol.code : null
}

function supports(symbol) {
  return channelKey(symbol) !== null
}

function batches(symbols) {
  var size = DESCRIPTOR.rateLimit.batchSize
  var out = []
  for (var i = 0; i < symbols.length; i += size) out.push(symbols.slice(i, i + size))
  return out
}

function requestFor(symbols) {
  var channels = []
  for (var i = 0; i < symbols.length; i++) {
    var key = channelKey(symbols[i])
    if (key) channels.push(key + ".tw")
  }
  if (channels.length === 0) return null
  return {
    url: QUOTE_URL + "?ex_ch=" + encodeURIComponent(channels.join("|")) + "&json=1&delay=0&lang=zh_tw",
    channels: channels
  }
}

// MIS sends every number as text, and "-" for "nothing this snapshot".
function positiveNumber(value) {
  var number = parseFloat(trimmed(value))
  return (isFinite(number) && number > 0) ? number : null
}

function quoteFromRow(symbol, row, nowMs) {
  // `z` is the last trade in this snapshot and `pz` the one before it; Pulse
  // for macOS reads them in that order and drops the row when both are "-".
  // During the continuous session they are "-" on almost every snapshot of a
  // stock, and the last trade is only in the nested `trade` object — so in that
  // release most Taiwanese rows fall back to Yahoo's delayed price. Reading
  // `trade.z` last is the one deliberate departure from that release.
  var price = positiveNumber(row.z)
  if (price === null) price = positiveNumber(row.pz)
  if (price === null) price = positiveNumber(row.trade && row.trade.z)
  if (price === null) return null

  var previous = positiveNumber(row.y)
  var lots = parseFloat(trimmed(row.v))
  var tlong = parseFloat(trimmed(row.tlong))
  return {
    symbol: SymbolID.toString(symbol),
    market: symbol.market,
    name: trimmed(row.n) || null,
    currencyCode: SymbolID.currencyCode(symbol),
    price: price,
    previousClose: previous === null ? price : previous,
    open: positiveNumber(row.o),
    high: positiveNumber(row.h),
    low: positiveNumber(row.l),
    // Volume is in lots of a thousand shares; an index has no share count.
    volume: (!SymbolID.isIndex(symbol) && isFinite(lots) && lots >= 0) ? lots * 1000 : null,
    turnover: null,
    sourceID: ID,
    sourceName: NAME,
    sourceDelaySeconds: 0,
    regularSession: null,
    timestampMs: (isFinite(tlong) && tlong > 0) ? tlong : Number(nowMs),
    marketState: "regular"
    // No `series` key: this source has none, and the panel keeps the line
    // another source drew rather than blanking it.
  }
}

// One quote per symbol that MIS priced, in the order asked. A symbol with no
// price is simply absent; the Yahoo quote for it stands.
function parseQuotes(symbols, payload, nowMs) {
  var rows = payload && payload.msgArray
  if (!rows || typeof rows.length !== "number") return []
  var byChannel = {}
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i] || {}
    if (!row.ex || !row.c) continue
    byChannel[(String(row.ex) + "_" + String(row.c)).toLowerCase()] = row
  }
  var quotes = []
  for (var j = 0; j < symbols.length; j++) {
    var key = channelKey(symbols[j])
    var match = key ? byChannel[key.toLowerCase()] : null
    if (!match) continue
    var quote = quoteFromRow(symbols[j], match, nowMs)
    if (quote) quotes.push(quote)
  }
  return quotes
}

// --- Search ---------------------------------------------------------------
//
// Search reads the two exchanges' daily open-data files and matches locally.
// This is the second departure from Pulse for macOS 0.15.10, which asks MIS's
// own name index (getStockNames.jsp) per query. That index cannot serve it:
// it answers rtcode 9999 to any query whose UTF-8 holds a 0x85 byte — 元, 光,
// 全 and about one CJK character in thirty-two — so 元大 finds nothing, and a
// broad prefix such as 富邦 lists every warrant on it and takes longer than
// ten seconds. The files are the previous trading day's listings, so a stock
// listed today is found tomorrow; Yahoo's direct match covers it until then.

var NAME_LISTS = [
  { market: "tw", url: "https://openapi.twse.com.tw/v1/exchangeReport/STOCK_DAY_ALL",
    codeKey: "Code", nameKey: "Name" },
  { market: "two", url: "https://www.tpex.org.tw/openapi/v1/tpex_mainboard_daily_close_quotes",
    codeKey: "SecuritiesCompanyCode", nameKey: "CompanyName" }
]

var SEARCH_LIMIT = 12
var EXCHANGE_NAMES = { tw: "TWSE", two: "TPEx" }

// The exchanges answer codes and Chinese names, which is exactly what Yahoo
// cannot: it answers 400 to Chinese text. A full symbol such as `2330.TW` is
// left to Yahoo's direct match, which already resolves it.
function searchable(query) {
  var text = trimmed(query)
  if (!text) return null
  return (/^\d{2,6}[A-Za-z]?$/.test(text) || /[\u3400-\u9fff\uf900-\ufaff]/.test(text)) ? text : null
}

// One board's file, as search entries in the file's order.
function parseNameList(market, payload) {
  var list = null
  for (var l = 0; l < NAME_LISTS.length; l++) {
    if (NAME_LISTS[l].market === market) list = NAME_LISTS[l]
  }
  if (!list || !payload || typeof payload.length !== "number") return []
  var entries = []
  var seen = {}
  for (var i = 0; i < payload.length; i++) {
    var row = payload[i] || {}
    var code = trimmed(row[list.codeKey]).toUpperCase()
    // Six characters and up is where warrants live (03002T, 701064). Pulse
    // for macOS keeps only the ETFs there, and every ETF code starts with 00.
    if (code.length >= 6 && code.indexOf("00") !== 0) continue
    var symbol = SymbolID.create(market, code)
    if (!symbol) continue
    var key = SymbolID.toString(symbol)
    if (seen[key]) continue
    seen[key] = true
    entries.push({
      key: key,
      symbol: symbol,
      displayCode: SymbolID.displayCode(symbol),
      market: market,
      name: trimmed(row[list.nameKey]) || key,
      exchangeName: EXCHANGE_NAMES[market],
      type: code.indexOf("00") === 0 ? "etf" : "equity"
    })
  }
  return entries
}

// Shorter codes first, so a stock (2881) leads its issuer's ETFs (00405A):
// the exchanges list ETFs first, and 富邦 would otherwise fill the page with
// Fubon's funds before 富邦金.
function byCode(a, b) {
  if (a.displayCode.length !== b.displayCode.length) return a.displayCode.length - b.displayCode.length
  return a.displayCode < b.displayCode ? -1 : (a.displayCode > b.displayCode ? 1 : 0)
}

// An exact code first, then codes that start with the query, then names that
// start with it, then names that hold it anywhere; by code within each.
function searchNames(entries, query) {
  var text = trimmed(query).toUpperCase()
  if (!text || !entries || typeof entries.length !== "number") return []
  var ranked = [[], [], [], []]
  for (var i = 0; i < entries.length; i++) {
    var entry = entries[i]
    var code = entry.displayCode.toUpperCase()
    var at = String(entry.name).toUpperCase().indexOf(text)
    if (code === text) ranked[0].push(entry)
    else if (code.indexOf(text) === 0) ranked[1].push(entry)
    else if (at === 0) ranked[2].push(entry)
    else if (at > 0) ranked[3].push(entry)
  }
  var out = []
  for (var r = 0; r < ranked.length && out.length < SEARCH_LIMIT; r++) {
    out = out.concat(ranked[r].sort(byCode))
  }
  return out.slice(0, SEARCH_LIMIT)
}

if (typeof module !== "undefined") module.exports = {
  ID: ID,
  NAME: NAME,
  DESCRIPTOR: DESCRIPTOR,
  channelKey: channelKey,
  supports: supports,
  batches: batches,
  requestFor: requestFor,
  parseQuotes: parseQuotes,
  NAME_LISTS: NAME_LISTS,
  searchable: searchable,
  parseNameList: parseNameList,
  searchNames: searchNames
}
