import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "SymbolID.js" as SymbolID
import "components"

// Pulse for Omarchy.
//
// Glanceable market data in the bar: the watchlist you already keep, priced,
// without leaving what you are working on. The bar itself stays discreet by
// default — an icon — and can be turned into a pinned quote or a carousel for
// people who would rather not open anything at all.
Panel {
  id: root
  moduleName: "pulse.omarchy"
  ipcTarget: "pulse.omarchy"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color muted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property bool settingsOpen: false
  property var marketState: Model.initialState()
  readonly property var quoteRows: Model.rows(marketState)
  property double nowMs: Date.now()

  // The bar label follows the rows, so a carousel and a pinned quote read from
  // the same prices the panel shows rather than fetching their own.
  property int carouselIndex: 0
  readonly property var pricedRows: quoteRows.filter(function (row) { return !!row.quote })
  readonly property var pinnedRow: {
    if (watchlist.barDisplay === "carousel") {
      return pricedRows.length > 0 ? pricedRows[carouselIndex % pricedRows.length] : null
    }
    if (watchlist.barDisplay !== "pinned") return null
    var wanted = SymbolID.parse(watchlist.pinnedSymbol)
    var key = wanted ? SymbolID.toString(wanted) : ""
    for (var i = 0; i < pricedRows.length; i++) {
      if (pricedRows[i].key === key) return pricedRows[i]
    }
    // A pinned symbol that is not on the watchlist falls back to the first
    // priced row rather than showing nothing: an empty bar slot reads as a
    // broken widget, not as a configuration mistake.
    return pricedRows.length > 0 ? pricedRows[0] : null
  }
  readonly property bool showsLabel: watchlist.barDisplay !== "icon" && pinnedRow !== null
  readonly property string barLabel: pinnedRow
    ? (pinnedRow.displayCode + "  " + Model.formatPrice(pinnedRow.quote.price)
       + "  " + Model.formatPercent(pinnedRow.changePercent))
    : ""

  ThemePalette {
    id: palette
    fallbackRise: Color.accent
    fallbackFall: root.urgent
  }

  Watchlist {
    id: watchlist
    onChanged: root.marketState = Model.applySymbols(root.marketState, watchlist.symbols)
  }

  SymbolSearch { id: symbolSearch }

  // The panel is the reason to fetch, but not the only one: a pinned or
  // carousel bar label needs prices whether or not anything is open.
  QuoteFeed {
    id: feed
    active: root.opened || watchlist.barDisplay !== "icon"
    symbols: root.marketState.symbols
    pollIntervalSeconds: watchlist.pollIntervalSeconds
    onQuoteReceived: function (quote) { root.marketState = Model.applyQuote(root.marketState, quote) }
    onQuoteFailed: function (symbol, message) { root.marketState = Model.applyError(root.marketState, symbol, message) }
  }

  // Drives the stale marker. Thirty seconds is finer than the five-minute
  // staleness threshold it feeds, so a row crosses over within one tick of
  // actually being stale. The clock only runs while the panel is open, so it
  // is also read at open time — the shell can have been running for days, and
  // the first tick would otherwise be half a minute late.
  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  onOpenedChanged: if (root.opened) root.nowMs = Date.now()

  Timer {
    interval: Math.max(2, watchlist.carouselIntervalSeconds) * 1000
    running: watchlist.barDisplay === "carousel" && root.pricedRows.length > 1
    repeat: true
    onTriggered: root.carouselIndex = (root.carouselIndex + 1) % Math.max(1, root.pricedRows.length)
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { feed.refresh(); return "ok" }
    function settings(): string {
      root.settingsOpen = !root.settingsOpen
      if (!root.settingsOpen) symbolSearch.clear()
      return root.settingsOpen ? "open" : "closed"
    }
    // Drives the settings search without synthetic keystrokes, which is how it
    // gets exercised from a script or a test run.
    function find(query: string): string {
      root.settingsOpen = true
      symbolSearch.query = query
      return "searching"
    }
    function results(): string {
      return JSON.stringify({
        query: symbolSearch.query,
        searching: symbolSearch.searching,
        message: symbolSearch.message,
        results: symbolSearch.results.map(function (r) {
          return { key: r.key, market: r.market, type: r.type, name: r.name }
        })
      })
    }
    function add(symbol: string): string {
      return watchlist.addSymbol(symbol) ? "added" : "rejected"
    }
    function remove(symbol: string): string {
      return watchlist.removeSymbol(symbol) ? "removed" : "not on the list"
    }
    function status(): string {
      return JSON.stringify({
        symbols: root.marketState.symbols,
        quoted: Object.keys(root.marketState.quotes).length,
        errors: root.marketState.errors,
        feed: feed.status,
        barDisplay: watchlist.barDisplay,
        settingsOpen: root.settingsOpen,
        config: watchlist.configPath,
        configError: watchlist.error
      })
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.showsLabel ? root.barLabel : ""
    labelVisible: root.showsLabel
    hasVisualContent: true
    // The icon form takes the bar's square icon slot; a quote label is as wide
    // as the quote, so it opts out of the fixed slot rather than eliding a
    // price down to nothing.
    fixedWidth: (root.showsLabel && !vertical) ? -1 : slotSize
    fontSize: root.showsLabel ? Style.font.body : Style.bar.iconFont
    // The label is colored by direction, but the panel behind it always spells
    // the number out — color is the fast read, never the only one.
    foreground: root.showsLabel && root.pinnedRow
      ? (root.pinnedRow.changePercent > 0
          ? palette.rise
          : (root.pinnedRow.changePercent < 0 ? palette.fall : root.foreground))
      : root.foreground
    iconComponent: root.showsLabel ? null : iconMark
    tooltipText: root.showsLabel ? "Pulse" : (root.pricedRows.length > 0 ? root.barLabel || "Pulse" : "Pulse")
    active: false
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
      else if (buttonCode === Qt.MiddleButton) feed.refresh()
    }
  }

  Component {
    id: iconMark
    Item {
      PulseLogo {
        anchors.centerIn: parent
        width: Style.space(13)
        height: width
        foregroundColor: root.foreground
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(720))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // While the filter holds focus every key belongs to it, including the
      // panel's own single-letter shortcuts.
      blocked: watchlistView.searching || root.settingsOpen
      onMoveRequested: function (dx, dy) { if (dy !== 0) watchlistView.moveSelection(dy) }
      onActivateRequested: {
        if (watchlistView.visibleRows.length > 0) watchlistView.detailOpen = true
      }
      onCloseRequested: {
        if (root.settingsOpen) { root.settingsOpen = false; symbolSearch.clear() }
        else if (watchlistView.filterText !== "") watchlistView.clearSearch()
        else if (watchlistView.detailOpen) watchlistView.detailOpen = false
        else root.close()
      }
      onTextKey: function (text) {
        var key = String(text || "").toLowerCase()
        if (key === "/" || key === "f") watchlistView.focusSearch()
        else if (key === "r") feed.refresh()
        else if (key === "s") root.settingsOpen = true
      }

      Column {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        Item {
          id: header
          width: parent.width
          implicitHeight: Style.space(30)

          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(7)

            PulseLogo {
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(15)
              height: width
              foregroundColor: root.foreground
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "Pulse"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
          }

          // Back out of a sub-view without reaching for Escape, and the gear
          // that leads into the only sub-view you cannot reach from a row.
          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(10)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: watchlistView.detailOpen || root.settingsOpen
              text: "← Back"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              TapHandler {
                onTapped: {
                  if (root.settingsOpen) { root.settingsOpen = false; symbolSearch.clear() }
                  else watchlistView.detailOpen = false
                }
              }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: !root.settingsOpen
              text: "⚙"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              TapHandler {
                onTapped: {
                  watchlistView.detailOpen = false
                  root.settingsOpen = true
                }
              }
            }
          }
        }

        WatchlistView {
          id: watchlistView
          visible: !detailOpen && !root.settingsOpen
          width: parent.width
          rows: root.quoteRows
          status: feed.status
          message: watchlist.error
          nowMs: root.nowMs
          textColor: root.foreground
          riseColor: palette.rise
          fallColor: palette.fall
          accentColor: Color.accent
          mutedColor: root.muted
          panelFontFamily: root.fontFamily
          onRefreshRequested: feed.refresh()
        }

        SettingsView {
          visible: root.settingsOpen
          width: parent.width
          watchlist: watchlist
          search: symbolSearch
          textColor: root.foreground
          riseColor: palette.rise
          fallColor: palette.fall
          mutedColor: root.muted
          panelFontFamily: root.fontFamily
        }

        SymbolDetail {
          visible: !root.settingsOpen && watchlistView.detailOpen && watchlistView.selectedRow !== null
          width: parent.width
          row: watchlistView.selectedRow
          nowMs: root.nowMs
          textColor: root.foreground
          riseColor: palette.rise
          fallColor: palette.fall
          mutedColor: root.muted
          panelFontFamily: root.fontFamily
          onDismissed: watchlistView.detailOpen = false
        }
      }
    }
  }
}
