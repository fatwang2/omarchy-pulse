import QtQuick
import Quickshell
import Quickshell.Io

// The watchlist, read from `~/.config/omarchy/pulse/watchlist.json`.
//
// Omarchy configures through files, so the list is a file rather than an
// in-panel editor. `watchChanges` means an edit lands without restarting the
// shell: save the file and the rows change.
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

  function load(raw) {
    var text = String(raw || "").replace(/^\s+|\s+$/g, "")
    if (!text) {
      root.error = ""
      root.symbols = []
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
    root.changed()
  }

  property FileView file: FileView {
    path: root.configPath
    watchChanges: true
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
