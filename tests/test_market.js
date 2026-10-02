const test = require("node:test")
const assert = require("node:assert/strict")

const { load } = require("./qmljs.js")

const Market = load("Market.js")

test("split markets share one badge but keep separate identities", () => {
  assert.equal(Market.displayLabel("sh"), "CN")
  assert.equal(Market.displayLabel("sz"), "CN")
  assert.equal(Market.displayLabel("kr"), "KR")
  assert.equal(Market.displayLabel("kq"), "KR")
  assert.notEqual(Market.priority("sh"), Market.priority("sz"))
})

test("currency follows the venue", () => {
  assert.equal(Market.currencyCode("us"), "USD")
  assert.equal(Market.currencyCode("hk"), "HKD")
  assert.equal(Market.currencyCode("sz"), "CNY")
  assert.equal(Market.currencyCode("jp"), "JPY")
  assert.equal(Market.currencyCode("kq"), "KRW")
  assert.equal(Market.currencyCode("metalCN"), "CNY")
})

test("crypto never closes", () => {
  assert.equal(Market.isOpen("crypto", Date.UTC(2026, 7, 22, 3, 0)), true) // a Saturday
})

test("weekends close every venue that has one", () => {
  const saturday = Date.UTC(2026, 7, 22, 3, 0)
  for (const market of ["hk", "sh", "sz", "jp", "kr", "tw"]) {
    assert.equal(Market.isOpen(market, saturday), false, market)
  }
})

test("the Tokyo lunch break is a real gap in the tape", () => {
  const day = (h, m) => Date.UTC(2026, 7, 20, h - 9, m) // Tokyo is UTC+9
  assert.equal(Market.isOpen("jp", day(10, 0)), true)
  assert.equal(Market.isOpen("jp", day(12, 0)), false) // 11:30-12:30 break
  assert.equal(Market.isOpen("jp", day(13, 0)), true)
  // Seoul trades straight through the same hour.
  assert.equal(Market.isOpen("kr", Date.UTC(2026, 7, 20, 3, 0)), true) // 12:00 KST
})

test("the Chinese midday break closes both boards", () => {
  const shanghai = (h, m) => Date.UTC(2026, 7, 20, h - 8, m)
  assert.equal(Market.isOpen("sh", shanghai(10, 0)), true)
  assert.equal(Market.isOpen("sh", shanghai(12, 0)), false)
  assert.equal(Market.isOpen("sz", shanghai(14, 0)), true)
  assert.equal(Market.isOpen("sz", shanghai(15, 30)), false)
})

test("a DST market defers to the runtime rather than an assumed offset", () => {
  // US and metal carry no fixed offset; they are polled rather than guessed at.
  assert.equal(Market.isOpen("us", Date.UTC(2026, 7, 22, 3, 0)), true)
})

test("both Taiwanese boards share one badge and trade in TWD", () => {
  assert.equal(Market.displayLabel("tw"), "TW")
  assert.equal(Market.displayLabel("two"), "TW")
  assert.equal(Market.currencyCode("tw"), "TWD")
  assert.equal(Market.currencyCode("two"), "TWD")
  assert.equal(Market.timeZone("two"), "Asia/Taipei")
  assert.notEqual(Market.priority("tw"), Market.priority("two"))
})

test("Taipei trades 09:00 to 13:30 straight through, on weekdays", () => {
  const taipei = (h, m) => Date.UTC(2026, 9, 2, h - 8, m) // a Friday; Taipei is UTC+8
  assert.equal(Market.isOpen("tw", taipei(8, 59)), false)
  assert.equal(Market.isOpen("tw", taipei(9, 0)), true)
  assert.equal(Market.isOpen("tw", taipei(12, 0)), true) // no lunch break
  assert.equal(Market.isOpen("two", taipei(13, 29)), true)
  assert.equal(Market.isOpen("two", taipei(13, 30)), false)
  assert.equal(Market.isOpen("tw", Date.UTC(2026, 9, 3, 2, 0)), false) // Saturday 10:00
})
