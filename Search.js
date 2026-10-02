// Search results from more than one source, as one list.
//
// Lists arrive in the order their sources should lead — the exchange's own
// index before Yahoo's for Taiwan, because it knows the Chinese name and the
// board. The first entry for an instrument wins, so one instrument never
// appears twice under two names.

function merge(lists) {
  var out = []
  var seen = {}
  var sources = (lists && typeof lists.length === "number") ? lists : []
  for (var i = 0; i < sources.length; i++) {
    var list = sources[i]
    if (!list || typeof list.length !== "number") continue
    for (var j = 0; j < list.length; j++) {
      var item = list[j]
      if (!item || !item.key || seen[item.key]) continue
      seen[item.key] = true
      out.push(item)
    }
  }
  return out
}

if (typeof module !== "undefined") module.exports = {
  merge: merge
}
