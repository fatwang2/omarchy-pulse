const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const { load } = require("./qmljs.js")

const TWSE = load("TWSEAdapter.js")
const SymbolID = load("SymbolID.js")

function fixture(name) {
  return JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures", name), "utf8"))
}

const NOW = 1790904600000

test("only Taiwanese securities and the two indices go to TWSE", () => {
  for (const raw of ["2330.TW", "6488.TWO", "TAIEX.TW", "TPEX.TWO"]) {
    assert.equal(TWSE.supports(SymbolID.parse(raw)), true, raw)
  }
  for (const raw of ["AAPL", "700.HK", "^KS11", "BTC/USDT", "GC"]) {
    assert.equal(TWSE.supports(SymbolID.parse(raw)), false, raw)
  }
})

test("one request carries many channels, named the way MIS names them", () => {
  const symbols = ["2330.TW", "6488.TWO", "TAIEX.TW", "TPEX.TWO", "AAPL"].map(SymbolID.parse)
  const spec = TWSE.requestFor(symbols)
  assert.deepEqual(spec.channels, ["tse_2330.tw", "otc_6488.tw", "tse_t00.tw", "otc_o00.tw"])
  assert.equal(spec.url,
    "https://mis.twse.com.tw/stock/api/getStockInfo.jsp?ex_ch="
    + "tse_2330.tw%7Cotc_6488.tw%7Ctse_t00.tw%7Cotc_o00.tw&json=1&delay=0&lang=zh_tw")
  assert.equal(TWSE.requestFor([SymbolID.parse("AAPL")]), null)
})

test("batches never exceed the source's batch size", () => {
  const symbols = []
  for (let i = 0; i < 120; i++) symbols.push(SymbolID.create("tw", String(1000 + i)))
  const batches = TWSE.batches(symbols)
  assert.deepEqual(batches.map((b) => b.length), [50, 50, 20])
  assert.deepEqual(TWSE.batches([]), [])
  assert.deepEqual(TWSE.DESCRIPTOR.rateLimit, { minIntervalMs: 3000, batchSize: 50 })
})

test("a price comes from z, then pz, then the nested trade", () => {
  const symbols = ["2330.TW", "0050.TW", "6488.TWO", "TAIEX.TW", "3008.TW", "00679B.TW"].map(SymbolID.parse)
  const quotes = TWSE.parseQuotes(symbols, fixture("twse_quotes.json"), NOW)
  assert.deepEqual(quotes.map((q) => q.symbol), ["2330.TW", "0050.TW", "6488.TWO", "TAIEX.TW"])
  const [tsmc, etf, otc, taiex] = quotes
  assert.equal(tsmc.price, 2505)      // only trade.z carried it
  assert.equal(etf.price, 112.45)     // z
  assert.equal(otc.price, 1080)       // pz
  assert.equal(taiex.price, 48370.27)
})

test("a TWSE quote is real time, in TWD, with lots turned into shares", () => {
  const quotes = TWSE.parseQuotes([SymbolID.parse("2330.TW"), SymbolID.parse("TAIEX.TW")],
    fixture("twse_quotes.json"), NOW)
  const [tsmc, taiex] = quotes
  assert.equal(tsmc.market, "tw")
  assert.equal(tsmc.name, "台積電")
  assert.equal(tsmc.currencyCode, "TWD")
  assert.equal(tsmc.previousClose, 2510)
  assert.equal(tsmc.open, 2505)
  assert.equal(tsmc.high, 2515)
  assert.equal(tsmc.low, 2500)
  assert.equal(tsmc.volume, 3302000)
  assert.equal(tsmc.timestampMs, 1790904479000)
  assert.equal(tsmc.sourceID, "twse")
  assert.equal(tsmc.sourceName, "TWSE Market Info")
  assert.equal(tsmc.sourceDelaySeconds, 0)
  assert.equal(tsmc.marketState, "regular")
  // The source has no intraday series; leaving the key out is how it says so.
  assert.equal(Object.prototype.hasOwnProperty.call(tsmc, "series"), false)
  // Index volume is not a share count.
  assert.equal(taiex.volume, null)
})

test("missing reference fields fall back rather than invent", () => {
  const payload = { msgArray: [{ c: "2330", ex: "tse", z: "2500.0000", y: "-", o: "-" }] }
  const [quote] = TWSE.parseQuotes([SymbolID.parse("2330.TW")], payload, NOW)
  assert.equal(quote.previousClose, 2500)
  assert.equal(quote.open, null)
  assert.equal(quote.timestampMs, NOW)
  assert.deepEqual(TWSE.parseQuotes([SymbolID.parse("2330.TW")], {}, NOW), [])
})

test("search runs for codes and Chinese text, not for English words", () => {
  assert.equal(TWSE.searchable("2330"), "2330")
  assert.equal(TWSE.searchable(" 00679b "), "00679b")
  assert.equal(TWSE.searchable("台積"), "台積")
  assert.equal(TWSE.searchable("nvidia"), null)
  assert.equal(TWSE.searchable("2330.TW"), null) // a full symbol is Yahoo's direct match
  assert.equal(TWSE.searchable("  "), null)
})

test("the name lists are the two exchanges' daily open-data files", () => {
  assert.deepEqual(TWSE.NAME_LISTS.map((list) => [list.market, list.url]), [
    ["tw", "https://openapi.twse.com.tw/v1/exchangeReport/STOCK_DAY_ALL"],
    ["two", "https://www.tpex.org.tw/openapi/v1/tpex_mainboard_daily_close_quotes"]
  ])
})

function nameIndex() {
  return TWSE.parseNameList("tw", fixture("twse_stock_day_all.json"))
    .concat(TWSE.parseNameList("two", fixture("tpex_daily_close.json")))
}

test("a name list keeps stocks and ETFs on their board and drops warrants and ETNs", () => {
  const entries = nameIndex()
  assert.deepEqual(entries.map((e) => e.key), [
    "2330.TW", "0050.TW", "00631L.TW", "006208.TW", "2301.TW", "1101B.TW",
    "6488.TWO", "00679B.TWO", "8069.TWO"
  ])
  const [tsmc] = entries
  assert.equal(tsmc.name, "台積電")
  assert.equal(tsmc.displayCode, "2330")
  assert.equal(tsmc.market, "tw")
  assert.equal(tsmc.exchangeName, "TWSE")
  assert.equal(tsmc.type, "equity")
  const bond = entries.find((e) => e.key === "00679B.TWO")
  assert.equal(bond.exchangeName, "TPEx")
  assert.equal(bond.type, "etf")
  assert.equal(entries.find((e) => e.key === "2301.TW").name, "光寶科")
  assert.deepEqual(TWSE.parseNameList("tw", null), [])
  assert.deepEqual(TWSE.parseNameList("tw", { rtcode: "9999" }), [])
  assert.deepEqual(TWSE.parseNameList("us", fixture("twse_stock_day_all.json")), [])
})

test("a Chinese name is found anywhere in it, whatever its bytes", () => {
  const entries = nameIndex()
  // 元 and 光 are UTF-8 E5 85 xx. MIS's own name index answers 9999 to any
  // query holding a 0x85 byte, which is why it is not asked.
  assert.deepEqual(TWSE.searchNames(entries, "元大").map((r) => r.key),
    ["0050.TW", "00631L.TW", "00679B.TWO"])
  assert.deepEqual(TWSE.searchNames(entries, "光寶").map((r) => r.key), ["2301.TW"])
  assert.deepEqual(TWSE.searchNames(entries, "台50").map((r) => r.key), ["006208.TW"])
  assert.deepEqual(TWSE.searchNames(entries, "台灣50").map((r) => r.key), ["0050.TW", "00631L.TW"])
})

test("a code match leads, exact before prefix, then names, by code within each", () => {
  const entries = nameIndex()
  assert.deepEqual(TWSE.searchNames(entries, "0050").map((r) => r.key), ["0050.TW"])
  assert.deepEqual(TWSE.searchNames(entries, "00679b").map((r) => r.key), ["00679B.TWO"])
  assert.deepEqual(TWSE.searchNames(entries, "006").map((r) => r.key), ["006208.TW", "00631L.TW", "00679B.TWO"])
  // "50" is no code's prefix here, but it is in three names.
  assert.deepEqual(TWSE.searchNames(entries, "50").map((r) => r.key), ["0050.TW", "006208.TW", "00631L.TW"])
  assert.deepEqual(TWSE.searchNames(entries, "  "), [])
  assert.deepEqual(TWSE.searchNames(null, "2330"), [])
})

test("a name that starts with the query leads one that only holds it, and a stock leads an ETF", () => {
  const entries = nameIndex()
  // The exchanges list ETFs first. Without this, 富邦 would fill the page with
  // Fubon's ETFs before 富邦金 itself.
  assert.deepEqual(TWSE.searchNames(entries, "台").map((r) => r.key),
    ["2330.TW", "1101B.TW", "0050.TW", "006208.TW", "00631L.TW"])
})

test("search stops at the result limit", () => {
  const entries = []
  for (let i = 0; i < 40; i++) {
    entries.push(...TWSE.parseNameList("tw", [{ Code: String(1100 + i), Name: "測試" + i }]))
  }
  assert.equal(TWSE.searchNames(entries, "測試").length, 12)
  assert.deepEqual(TWSE.searchNames(entries, "11").slice(0, 2).map((r) => r.key), ["1100.TW", "1101.TW"])
})
