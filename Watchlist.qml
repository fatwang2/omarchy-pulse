import QtQuick
import Quickshell
import Quickshell.Io
import "SymbolID.js" as SymbolID

// The watchlist, stored at `~/.config/omarchy/pulse/watchlist.json`.
//
// Omarchy configures through files, so the file is the source of truth and the
// settings view is one of two editors for it — the other being any text editor.
// `watchChanges` keeps both honest: an edit from either side lands without
// restarting the shell, and a write from the panel is read straight back.
QtObject {
  id: root

  readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omarchy/pulse"
  readonly property string configPath: configDir + "/watchlist.json"

  property var symbols: []
  property int pollIntervalSeconds: 60
  // How the bar itself reads: "icon" stays discreet, "pinned" shows one symbol,
  // "carousel" rotates through the list.
  property string barDisplay: "icon"
  property string pinnedSymbol: ""
  property int carouselIntervalSeconds: 6
  property string error: ""
  property bool loaded: false

  // Keys this version does not understand are carried through a write
  // untouched. A newer Pulse's settings must survive being edited by an older
  // one, and silently dropping them is the one failure a user cannot see.
  property var passthrough: ({})

  signal changed()

  function stringList(value) {
    if (!value || typeof value.length !== "number") return []
    var out = []
    for (var i = 0; i < value.length; i++) {
      var entry = String(value[i] || "").replace(/^\s+|\s+$/g, "")
      if (entry) out.push(entry)
    }
    return out
  }

  function clampInt(value, fallback, minimum, maximum) {
    var n = Number(value)
    if (!isFinite(n)) return fallback
    return Math.max(minimum, Math.min(maximum, Math.round(n)))
  }

  readonly property var knownKeys: ["version", "symbols", "pollIntervalSeconds",
                                    "barDisplay", "pinnedSymbol", "carouselIntervalSeconds"]

  function load(raw) {
    var text = String(raw || "").replace(/^\s+|\s+$/g, "")
    if (!text) {
      root.error = ""
      root.symbols = []
      root.loaded = true
      root.changed()
      return
    }
    var parsed
    try {
      parsed = JSON.parse(text)
    } catch (e) {
      // A half-saved file is a normal state to observe with watchChanges on, so
      // the previous list is kept rather than blanked; the panel says why.
      root.error = "watchlist.json: " + e.message
      return
    }
    root.error = ""
    root.symbols = stringList(parsed.symbols)
    // Yahoo rate-limits per IP, so the floor is not a preference.
    root.pollIntervalSeconds = clampInt(parsed.pollIntervalSeconds, 60, 15, 3600)
    var display = String(parsed.barDisplay || "icon")
    root.barDisplay = (display === "pinned" || display === "carousel") ? display : "icon"
    root.pinnedSymbol = String(parsed.pinnedSymbol || "")
    root.carouselIntervalSeconds = clampInt(parsed.carouselIntervalSeconds, 6, 2, 120)

    var extra = ({})
    for (var key in parsed) {
      if (root.knownKeys.indexOf(key) < 0) extra[key] = parsed[key]
    }
    root.passthrough = extra
    root.loaded = true
    root.changed()
  }

  // --- Editing ------------------------------------------------------------
  //
  // Every mutation writes the whole file. The list is a few dozen lines, and a
  // single write is the only way the file and the panel cannot disagree.

  function canonical(raw) {
    var parsed = SymbolID.parse(raw)
    return parsed ? SymbolID.toString(parsed) : ""
  }

  // What the file will contain: canonical spellings, in order, deduplicated.
  // Writing canonical rather than what the user typed means `00700.HK` becomes
  // `700.HK` on the first edit and stays stable from then on.
  function canonicalSymbols() {
    var out = []
    var seen = ({})
    for (var i = 0; i < root.symbols.length; i++) {
      var key = canonical(root.symbols[i])
      if (!key || seen[key]) continue
      seen[key] = true
      out.push(key)
    }
    return out
  }

  function indexOfSymbol(raw) {
    return canonicalSymbols().indexOf(canonical(raw))
  }

  function contains(raw) {
    return indexOfSymbol(raw) >= 0
  }

  function addSymbol(raw) {
    var key = canonical(raw)
    if (!key || contains(key)) return false
    root.symbols = canonicalSymbols().concat([key])
    save()
    return true
  }

  function removeSymbol(raw) {
    var index = indexOfSymbol(raw)
    if (index < 0) return false
    var next = canonicalSymbols()
    next.splice(index, 1)
    root.symbols = next
    // A pinned symbol that just left the list would otherwise keep naming a row
    // that no longer exists.
    if (canonical(root.pinnedSymbol) === canonical(raw)) {
      root.pinnedSymbol = next.length > 0 ? next[0] : ""
    }
    save()
    return true
  }

  function moveSymbol(raw, delta) {
    var index = indexOfSymbol(raw)
    if (index < 0) return false
    var next = canonicalSymbols()
    var target = index + delta
    if (target < 0 || target >= next.length) return false
    var moved = next.splice(index, 1)[0]
    next.splice(target, 0, moved)
    root.symbols = next
    save()
    return true
  }

  function setBarDisplay(mode) {
    var display = String(mode || "icon")
    root.barDisplay = (display === "pinned" || display === "carousel") ? display : "icon"
    save()
  }

  function setPinnedSymbol(raw) {
    root.pinnedSymbol = canonical(raw)
    save()
  }

  function setPollInterval(seconds) {
    root.pollIntervalSeconds = clampInt(seconds, 60, 15, 3600)
    save()
  }

  function save() {
    // Refusing to write before the first successful read is what stops a
    // transient parse failure or a missing file from being persisted as an
    // empty watchlist.
    if (!root.loaded) return
    var payload = ({})
    for (var key in root.passthrough) payload[key] = root.passthrough[key]
    payload.version = 1
    payload.symbols = canonicalSymbols()
    payload.pollIntervalSeconds = root.pollIntervalSeconds
    payload.barDisplay = root.barDisplay
    payload.pinnedSymbol = root.pinnedSymbol
    payload.carouselIntervalSeconds = root.carouselIntervalSeconds
    file.setText(JSON.stringify(payload, null, 2) + "\n")
    root.changed()
  }

  property FileView file: FileView {
    id: file
    path: root.configPath
    watchChanges: true
    // The file is watched and written from the same process; a torn read of a
    // half-written file would show up as the parse error above.
    atomicWrites: true
    printErrors: false
    onLoaded: root.load(text())
    onFileChanged: reload()
    onLoadFailed: {
      root.error = "No watchlist at " + root.configPath
      root.symbols = []
      root.changed()
    }
  }
}
