const test = require("node:test")
const assert = require("node:assert/strict")

const { load } = require("./qmljs.js")

const Search = load("Search.js")

const r = (key, name) => ({ key: key, name: name })

test("sources lead in the order given and an instrument appears once", () => {
  const merged = Search.merge([
    [r("2330.TW", "台積電"), r("6488.TWO", "環球晶")],
    [r("2330.TW", "Taiwan Semiconductor"), r("TSM", "TSMC ADR")]
  ])
  assert.deepEqual(merged.map((x) => x.key), ["2330.TW", "6488.TWO", "TSM"])
  assert.equal(merged[0].name, "台積電")
})

test("missing or malformed lists are skipped", () => {
  assert.deepEqual(Search.merge([null, [r("AAPL", "Apple")], undefined, [null]]).map((x) => x.key), ["AAPL"])
  assert.deepEqual(Search.merge([]), [])
})
