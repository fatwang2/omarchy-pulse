import QtQuick
import qs.Commons
import qs.Ui

// Settings, in Omarchy's own furniture: PanelSectionHeader introduces each
// section, PanelSeparator divides them, ButtonGroup carries the exclusive
// choices, Dropdown the pick-one-of-many. Watchlist membership is not here —
// adding lives behind the header's search, removal in the quote detail —
// because settings is for how the plugin behaves, not what it watches.
Column {
  id: root

  required property var watchlist
  required property color textColor
  required property color mutedColor
  required property string panelFontFamily

  // Which list name is being renamed inline, or "" when none is.
  property string renamingList: ""

  spacing: Style.space(10)

  // --- Bar ------------------------------------------------------------------

  PanelSectionHeader {
    text: "BAR"
    foreground: root.textColor
    fontFamily: root.panelFontFamily
  }

  ButtonGroup {
    width: parent.width
    foreground: root.textColor
    fontFamily: root.panelFontFamily
    fontSize: Style.font.caption
    options: [
      { value: "icon", label: "Icon" },
      { value: "pinned", label: "Pinned quote" },
      { value: "carousel", label: "Carousel" }
    ]
    value: root.watchlist.barDisplay
    onChanged: function (mode) { root.watchlist.setValue("barDisplay", mode) }
  }

  // Only the pinned mode names a symbol; the other two have nothing to pick.
  Dropdown {
    width: parent.width
    visible: root.watchlist.barDisplay === "pinned"
    label: "Pinned symbol"
    foreground: root.textColor
    fontFamily: root.panelFontFamily
    options: root.watchlist.allSymbols
    value: root.watchlist.pinnedSymbol
    onChanged: function (symbol) { root.watchlist.setValue("pinnedSymbol", symbol) }
  }

  Dropdown {
    width: parent.width
    visible: root.watchlist.barDisplay === "carousel"
    label: "Rotate every"
    foreground: root.textColor
    fontFamily: root.panelFontFamily
    options: [
      { value: "3", label: "3 seconds" },
      { value: "6", label: "6 seconds" },
      { value: "10", label: "10 seconds" },
      { value: "30", label: "30 seconds" }
    ]
    value: String(root.watchlist.carouselIntervalSeconds)
    onChanged: function (seconds) { root.watchlist.setValue("carouselIntervalSeconds", Number(seconds)) }
  }

  PanelSeparator { foreground: root.textColor }

  // --- Refresh --------------------------------------------------------------

  PanelSectionHeader {
    text: "REFRESH"
    foreground: root.textColor
    fontFamily: root.panelFontFamily
  }

  ButtonGroup {
    width: parent.width
    foreground: root.textColor
    fontFamily: root.panelFontFamily
    fontSize: Style.font.caption
    // The floor is Yahoo's per-IP budget, not a preference; anything faster
    // than the source can change is spent requests.
    options: [
      { value: "30", label: "30s" },
      { value: "60", label: "60s" },
      { value: "120", label: "2m" },
      { value: "300", label: "5m" }
    ]
    value: String(root.watchlist.pollIntervalSeconds)
    onChanged: function (seconds) { root.watchlist.setValue("pollIntervalSeconds", Number(seconds)) }
  }

  PanelSeparator { foreground: root.textColor }

  // --- Lists ----------------------------------------------------------------

  PanelSectionHeader {
    text: "LISTS"
    foreground: root.textColor
    fontFamily: root.panelFontFamily
  }

  Column {
    width: parent.width
    spacing: 0

    Repeater {
      model: root.watchlist.listNames

      Rectangle {
        id: listRow
        required property string modelData
        required property int index
        readonly property bool renaming: root.renamingList === modelData
        readonly property int symbolCount: {
          var config = root.watchlist.config
          var i = config.lists.map(function (l) { return l.name }).indexOf(modelData)
          return i >= 0 ? config.lists[i].symbols.length : 0
        }

        width: parent.width
        implicitHeight: Style.space(30)
        radius: 0
        color: listHover.hovered
          ? Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.06)
          : (index % 2 === 1
              ? Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.025)
              : "transparent")

        HoverHandler { id: listHover }

        Row {
          visible: !listRow.renaming
          anchors.left: parent.left
          anchors.leftMargin: Style.space(6)
          anchors.right: listActions.left
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: listRow.modelData
            color: root.textColor
            font.family: root.panelFontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: listRow.symbolCount + (listRow.symbolCount === 1 ? " symbol" : " symbols")
            color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.35)
            font.family: root.panelFontFamily
            font.pixelSize: Style.font.caption
          }
        }

        TextField {
          visible: listRow.renaming
          anchors.left: parent.left
          anchors.right: listActions.left
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          foreground: root.textColor
          text: listRow.modelData
          onVisibleChanged: if (visible) { forceActiveFocus(); selectAll() }
          onAccepted: {
            root.watchlist.renameList(listRow.modelData, text)
            root.renamingList = ""
          }
          Keys.onEscapePressed: root.renamingList = ""
        }

        Row {
          id: listActions
          anchors.right: parent.right
          anchors.rightMargin: Style.space(4)
          anchors.verticalCenter: parent.verticalCenter
          spacing: 0
          visible: !listRow.renaming

          PanelActionButton {
            iconText: "󰑕"
            tooltipText: "Rename"
            foreground: root.mutedColor
            fontFamily: root.panelFontFamily
            fontSize: Style.font.bodySmall
            onClicked: root.renamingList = listRow.modelData
          }

          PanelActionButton {
            // The last list is not removable; the button says so by dimming
            // rather than by disappearing and leaving the rows misaligned.
            enabled: root.watchlist.listNames.length > 1
            opacity: enabled ? 1.0 : 0.3
            iconText: "󰩺"
            tooltipText: enabled ? "Delete list" : "The last list stays"
            foreground: root.mutedColor
            fontFamily: root.panelFontFamily
            fontSize: Style.font.bodySmall
            onClicked: root.watchlist.removeList(listRow.modelData)
          }
        }
      }
    }
  }

  PanelSeparator { foreground: root.textColor }

  // --- Sources --------------------------------------------------------------
  //
  // The frame the macOS app's multi-provider layer will fill in. One source is
  // wired today; the rest are named so the shape of the panel does not change
  // when they arrive — only the rows light up.

  PanelSectionHeader {
    text: "DATA SOURCES"
    foreground: root.textColor
    fontFamily: root.panelFontFamily
  }

  Column {
    width: parent.width
    spacing: 0

    component SourceRow: Item {
      id: sourceRow
      required property string name
      required property string detail
      property bool wired: false
      width: parent.width
      implicitHeight: Style.space(32)
      opacity: wired ? 1.0 : 0.45

      Column {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(6)
        anchors.right: stateLabel.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Text {
          text: sourceRow.name
          color: root.textColor
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          width: parent.width
          text: sourceRow.detail
          color: root.mutedColor
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        id: stateLabel
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        text: sourceRow.wired ? "ACTIVE" : "PLANNED"
        color: root.mutedColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.caption
      }
    }

    SourceRow {
      name: "Yahoo Finance"
      detail: "US real time · HK/CN ~15 min · JP/KR ~20 min · metals"
      wired: true
    }
    SourceRow {
      name: "Binance"
      detail: "Crypto pairs, live over WebSocket"
    }
    SourceRow {
      name: "Longbridge"
      detail: "Real-time HK / US / A-shares with your account"
    }
    SourceRow {
      name: "Naver"
      detail: "Korea real time and Korean-language search"
    }
  }

  Text {
    width: parent.width
    text: "Saved to " + root.watchlist.configPath
    color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.35)
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.caption
    elide: Text.ElideMiddle
  }
}
