// Yahoo Finance v8 chart (unofficial API), ported from PulseCore's
// `YahooProvider.swift`.
//
// One source covering US, HK, Shanghai, Shenzhen, Tokyo, both Korean boards and
// the COMEX/NYMEX metal contracts. Crypto is deliberately absent: Binance is the
// sole source of truth for pairs, and Yahoo's spot metal symbols have never
// worked, so `XAU`/`XAG` are refused here rather than quietly priced off a
// futures contract that is not what the row asks for.

.import "SymbolID.js" as SymbolID

var ID = "yahoo"
var NAME = "Yahoo Finance"
var BASE = "https://query1.finance.yahoo.com/v8/finance/chart/"

// Per-market delay in seconds, as published or measured. Zero means the tape.
// Seoul measures ~21 minutes behind and Tokyo is licensed the same way; both
// round to the 20 minutes Yahoo states.
var DELAY = {
  us: 0, hk: 900, sh: 900, sz: 900, jp: 1200, kr: 1200, kq: 1200, metal: 600
}

var MARKETS = ["us", "hk", "sh", "sz", "jp", "kr", "kq", "metal"]

// Yahoo rate-limits hard per IP. One symbol per request, a second apart, and a
// 60-second cadence — liveliness is not this source's job.
var DESCRIPTOR = {
  id: ID,
  name: NAME,
  markets: MARKETS,
  capabilities: ["quotes", "candles"],
  delay: DELAY,
  rateLimit: { minIntervalMs: 1000, batchSize: 1 },
  suggestedPollIntervalMs: 60000
}

var INDEX_WIRE = {
  sp500: "^GSPC", nasdaqComposite: "^IXIC", dowJonesIndustrial: "^DJI",
  nasdaq100: "^NDX", vix: "^VIX", russell1000: "^RUI", russell2000: "^RUT",
  hangSeng: "^HSI", hangSengTech: "^HSTECH",
  shanghaiComposite: "000001.SS", shenzhenComponent: "399001.SZ", chiNext: "399006.SZ",
  nikkei225: "^N225", kospi: "^KS11"
}

var SUFFIX = { hk: ".HK", sh: ".SS", sz: ".SZ", jp: ".T", kr: ".KS", kq: ".KQ" }

function padded(code, width) {
  var value = String(code)
  while (value.length < width) value = "0" + value
  return value
}

// Yahoo's wire spelling for one identity. HK is padded back to four digits,
// which is the width Yahoo indexes; Pulse stores it unpadded.
function wireSymbol(symbol) {
  if (!symbol) return null
  if (SymbolID.isCrypto(symbol)) return null
  if (SymbolID.isMetal(symbol)) {
    // `=F` is Yahoo's continuous front-month futures notation. Spot has no
    // working symbol at all, so it is refused rather than approximated.
    if (SymbolID.isSpotMetal(symbol)) return null
    if (symbol.market === "metalCN") return null
    return SymbolID.code(symbol) + "=F"
  }
  if (SymbolID.isIndex(symbol)) return INDEX_WIRE[symbol.id] || null
  var code = SymbolID.code(symbol)
  if (symbol.market === "us") return code
  if (symbol.market === "hk") return padded(code, 4) + ".HK"
  var suffix = SUFFIX[symbol.market]
  return suffix ? code + suffix : null
}

function supports(symbol) {
  return wireSymbol(symbol) !== null
}

// US symbols are read over a two-day, one-minute window with pre/post included,
// because that is the only shape that carries an extended-session price. Two
// days rather than one: during pre-market a one-day window makes
// `chartPreviousClose` the close *before* the last regular session, which is
// exactly the reference that session's own change needs.
function requestFor(symbol) {
  var wire = wireSymbol(symbol)
  if (!wire) return null
  var extended = symbol.market === "us"
  var query = extended
    ? "interval=1m&range=2d&includePrePost=true"
    : "interval=1d&range=1d&includePrePost=false"
  return {
    url: BASE + encodeURIComponent(wire) + "?" + query,
    wireSymbol: wire,
    extended: extended
  }
}

function firstFinite(values) {
  if (!values) return null
  for (var i = 0; i < values.length; i++) {
    if (typeof values[i] === "number" && isFinite(values[i])) return values[i]
  }
  return null
}

function chartResult(payload) {
  var chart = payload && payload.chart
  if (!chart) return null
  if (chart.error) return null
  var results = chart.result
  return (results && results.length > 0) ? results[0] : null
}

function ohlcSeries(result) {
  var indicators = result && result.indicators
  var quotes = indicators && indicators.quote
  return (quotes && quotes.length > 0) ? quotes[0] : null
}

// The last bar that actually printed. Yahoo pads the window with null closes
// past the current time, so scanning backwards is the only way to find it.
function latestClose(result) {
  var timestamps = result && result.timestamp
  var series = ohlcSeries(result)
  var closes = series && series.close
  if (!timestamps || !closes) return null
  var count = Math.min(timestamps.length, closes.length)
  for (var i = count - 1; i >= 0; i--) {
    var close = closes[i]
    if (typeof close === "number" && isFinite(close)) {
      return { price: close, timestampMs: timestamps[i] * 1000 }
    }
  }
  return null
}

function withinPeriod(period, seconds) {
  return !!period && seconds >= period.start && seconds < period.end
}

function marketStateFor(timestampMs, periods) {
  var seconds = Math.floor(Number(timestampMs) / 1000)
  if (withinPeriod(periods && periods.pre, seconds)) return "preMarket"
  if (withinPeriod(periods && periods.regular, seconds)) return "regular"
  if (withinPeriod(periods && periods.post, seconds)) return "postMarket"
  return "closed"
}

// What the displayed change is measured against. In an extended session the
// reference is the regular close, so the number reads as "since the bell"
// rather than "since yesterday".
function referenceClose(state, regularPrice, previousClose, chartPreviousClose) {
  if (state === "preMarket" || state === "postMarket" || state === "overnight") return regularPrice
  if (typeof previousClose === "number" && isFinite(previousClose)) return previousClose
  if (typeof chartPreviousClose === "number" && isFinite(chartPreviousClose)) return chartPreviousClose
  return regularPrice
}

// The last completed regular session, attached to extended-session quotes so
// the row can show that day's result beside the live extended price.
// Pre-market: the day has not opened, so the last regular close *is*
// `previousClose`, and its own reference is the close before the window.
function regularSessionClose(state, regularPrice, previousClose, chartPreviousClose) {
  if (state === "preMarket") return { price: regularPrice, previousClose: chartPreviousClose }
  if (state === "postMarket" || state === "overnight") return { price: regularPrice, previousClose: previousClose }
  return null
}

// Today's regular open: the first bar at or after the regular period start.
// The window's first bar is yesterday's 04:00 pre-market print on a two-day
// range, and before the open there is no "today's open" to show at all.
function regularSessionOpen(result) {
  var periods = result.meta && result.meta.currentTradingPeriod
  var start = periods && periods.regular && periods.regular.start
  var timestamps = result.timestamp
  var series = ohlcSeries(result)
  var opens = series && series.open
  if (!start || !timestamps || !opens) return null
  var count = Math.min(timestamps.length, opens.length)
  for (var i = 0; i < count; i++) {
    if (timestamps[i] < start) continue
    if (typeof opens[i] === "number" && isFinite(opens[i])) return opens[i]
  }
  return null
}

// Parses one chart response into a quote. Returns null when the payload
// carries no price, which is Yahoo's way of saying the symbol does not exist.
function parseQuote(symbol, payload, extended) {
  var result = chartResult(payload)
  if (!result || !result.meta) return null
  var meta = result.meta
  var regularPrice = meta.regularMarketPrice
  if (typeof regularPrice !== "number" || !isFinite(regularPrice)) return null

  var nowMs = null
  var quote = {
    symbol: SymbolID.toString(symbol),
    market: symbol.market,
    name: meta.longName || meta.shortName || null,
    currencyCode: meta.currency || SymbolID.currencyCode(symbol),
    high: typeof meta.regularMarketDayHigh === "number" ? meta.regularMarketDayHigh : null,
    low: typeof meta.regularMarketDayLow === "number" ? meta.regularMarketDayLow : null,
    volume: typeof meta.regularMarketVolume === "number" ? meta.regularMarketVolume : null,
    turnover: null,
    sourceID: ID,
    sourceName: NAME,
    sourceDelaySeconds: DELAY[symbol.market] === undefined ? null : DELAY[symbol.market],
    regularSession: null
  }

  if (!extended) {
    var previous = meta.previousClose
    if (typeof previous !== "number" || !isFinite(previous)) previous = meta.chartPreviousClose
    if (typeof previous !== "number" || !isFinite(previous)) previous = regularPrice
    var series = ohlcSeries(result)
    quote.price = regularPrice
    quote.previousClose = previous
    quote.open = firstFinite(series && series.open)
    quote.timestampMs = typeof meta.regularMarketTime === "number" ? meta.regularMarketTime * 1000 : null
    quote.marketState = "regular"
    return quote
  }

  var latest = latestClose(result)
  var regularTimeMs = typeof meta.regularMarketTime === "number" ? meta.regularMarketTime * 1000 : null
  var state = latest ? marketStateFor(latest.timestampMs, meta.currentTradingPeriod) : "regular"
  quote.price = latest ? latest.price : regularPrice
  quote.previousClose = referenceClose(state, regularPrice, meta.previousClose, meta.chartPreviousClose)
  quote.open = regularSessionOpen(result)
  quote.timestampMs = latest ? latest.timestampMs : regularTimeMs
  quote.marketState = state
  quote.regularSession = regularSessionClose(state, regularPrice, meta.previousClose, meta.chartPreviousClose)
  return quote
}

if (typeof module !== "undefined") module.exports = {
  ID: ID,
  NAME: NAME,
  DESCRIPTOR: DESCRIPTOR,
  DELAY: DELAY,
  wireSymbol: wireSymbol,
  supports: supports,
  requestFor: requestFor,
  parseQuote: parseQuote,
  latestClose: latestClose,
  marketStateFor: marketStateFor,
  referenceClose: referenceClose,
  regularSessionClose: regularSessionClose,
  regularSessionOpen: regularSessionOpen
}
