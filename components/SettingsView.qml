import QtQuick
import qs.Commons
import qs.Ui
import "../SymbolID.js" as SymbolID
import "../Market.js" as Market

// The watchlist editor.
//
// The file stays the source of truth — this writes to it, and an edit made in
// a text editor shows up here without a restart. It exists because the one
// thing a watchlist is made of, an ordered list of instruments, is the one
// thing neither `omarchy bar set` nor a declarative settings schema can carry.
Column {
  id: root

  required property var watchlist
  required property var search
  required property color textColor
  required property color riseColor
  required property color fallColor
  required property color mutedColor
  required property string panelFontFamily

  readonly property var symbols: watchlist ? watchlist.canonicalSymbols() : []
  readonly property var barModes: ["icon", "pinned", "carousel"]
  readonly property var barModeLabels: ({
    icon: "Icon only",
    pinned: "Pinned quote",
    carousel: "Carousel"
  })

  spacing: Style.space(12)

  // The same badge the watchlist shows. Both Chinese boards read CN and both
  // Korean boards read KR — an instrument must not carry one badge on the list
  // and a different one on the screen that edits the list.
  function marketLabelFor(key) {
    var parsed = SymbolID.parse(key)
    return parsed ? Market.displayLabel(parsed.market) : ""
  }

  // --- Add ------------------------------------------------------------------

  Column {
    width: parent.width
    spacing: Style.space(6)

    Text {
      text: "ADD SYMBOL"
      color: root.mutedColor
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.caption
    }

    TextField {
      id: queryField
      width: parent.width
      placeholderText: "Search name or code — nvidia, 600519.SH, 7203.T"
      onTextChanged: root.search.query = text
      Keys.onEscapePressed: {
        text = ""
        root.search.clear()
      }
    }

    Text {
      width: parent.width
      visible: root.search.searching || root.search.message !== ""
      text: root.search.searching ? "Searching…" : root.search.message
      color: root.mutedColor
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    // Results are capped at five: this list sits above the watchlist it is
    // about to change, and pushing that off screen to show a sixth candidate
    // is the wrong trade.
    Column {
      width: parent.width
      visible: root.search.results.length > 0
      spacing: 0

      Repeater {
        model: root.search.results.slice(0, 5)

        Rectangle {
          id: resultRow
          required property var modelData
          required property int index
          readonly property bool alreadyAdded: root.watchlist.contains(modelData.key)

          width: parent.width
          implicitHeight: Style.space(32)
          radius: 0
          color: resultHover.hovered
            ? Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.06)
            : "transparent"

          HoverHandler { id: resultHover }
          TapHandler {
            enabled: !resultRow.alreadyAdded
            onTapped: {
              root.watchlist.addSymbol(resultRow.modelData.key)
              queryField.text = ""
              root.search.clear()
            }
          }

          Row {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(6)
            anchors.right: addedMark.left
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: resultRow.modelData.displayCode
              color: root.textColor
              font.family: root.panelFontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            MarketBadge {
              anchors.verticalCenter: parent.verticalCenter
              label: Market.displayLabel(resultRow.modelData.market)
              textColor: root.textColor
              panelFontFamily: root.panelFontFamily
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: Math.max(0, resultRow.width - Style.space(150))
              text: resultRow.modelData.name
                ? String(resultRow.modelData.name)
                : "Add by code"
              color: root.mutedColor
              font.family: root.panelFontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          // A symbol already on the list says so rather than offering an add
          // that would silently do nothing.
          Text {
            id: addedMark
            anchors.right: parent.right
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            text: resultRow.alreadyAdded ? "ON LIST" : "+"
            color: resultRow.alreadyAdded ? root.mutedColor : root.textColor
            font.family: root.panelFontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  Rectangle {
    width: parent.width
    height: 1
    color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.15)
  }

  // --- Reorder and remove ---------------------------------------------------

  Column {
    width: parent.width
    spacing: Style.space(6)

    Text {
      text: "WATCHLIST — " + root.symbols.length + (root.symbols.length === 1 ? " SYMBOL" : " SYMBOLS")
      color: root.mutedColor
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.caption
    }

    Column {
      width: parent.width
      spacing: 0

      Repeater {
        model: root.symbols

        Rectangle {
          id: symbolRow
          required property string modelData
          required property int index

          width: parent.width
          implicitHeight: Style.space(30)
          radius: 0
          color: rowHover.hovered
            ? Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.06)
            : (index % 2 === 1
                ? Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.025)
                : "transparent")

          HoverHandler { id: rowHover }

          Row {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: SymbolID.displayCode(SymbolID.parse(symbolRow.modelData))
              color: root.textColor
              font.family: root.panelFontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            MarketBadge {
              anchors.verticalCenter: parent.verticalCenter
              label: root.marketLabelFor(symbolRow.modelData)
              textColor: root.textColor
              panelFontFamily: root.panelFontFamily
            }
          }

          // Reordering is two buttons rather than a drag. A drag inside a
          // popup that closes on outside clicks is a gesture that loses its
          // own list halfway through.
          Row {
            anchors.right: parent.right
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(10)

            component RowAction: Text {
              required property string glyph
              required property bool enabledAction
              signal triggered()
              anchors.verticalCenter: parent.verticalCenter
              text: glyph
              color: enabledAction
                ? Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.65)
                : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.20)
              font.family: root.panelFontFamily
              font.pixelSize: Style.font.bodySmall
              TapHandler {
                enabled: parent.enabledAction
                onTapped: parent.triggered()
              }
            }

            RowAction {
              glyph: "↑"
              enabledAction: symbolRow.index > 0
              onTriggered: root.watchlist.moveSymbol(symbolRow.modelData, -1)
            }
            RowAction {
              glyph: "↓"
              enabledAction: symbolRow.index < root.symbols.length - 1
              onTriggered: root.watchlist.moveSymbol(symbolRow.modelData, 1)
            }
            RowAction {
              glyph: "✕"
              enabledAction: true
              onTriggered: root.watchlist.removeSymbol(symbolRow.modelData)
            }
          }
        }
      }
    }

    Text {
      width: parent.width
      visible: root.symbols.length === 0
      text: "Nothing on the list yet. Search above, or edit " + root.watchlist.configPath
      color: root.mutedColor
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }

  Rectangle {
    width: parent.width
    height: 1
    color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.15)
  }

  // --- Bar ------------------------------------------------------------------

  Column {
    width: parent.width
    spacing: Style.space(6)

    Text {
      text: "BAR"
      color: root.mutedColor
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.caption
    }

    Rectangle {
      width: parent.width
      implicitHeight: Style.space(26)
      radius: 0
      color: "transparent"
      border.width: 1
      border.color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.18)

      Row {
        anchors.fill: parent

        Repeater {
          model: root.barModes

          Rectangle {
            required property string modelData
            required property int index
            readonly property bool active: root.watchlist.barDisplay === modelData

            width: parent.width / root.barModes.length
            height: parent.height
            radius: 0
            color: active
              ? Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.12)
              : "transparent"

            Rectangle {
              visible: index > 0
              anchors.left: parent.left
              width: 1
              height: parent.height
              color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.18)
            }

            Text {
              anchors.centerIn: parent
              text: root.barModeLabels[parent.modelData]
              color: root.textColor
              font.family: root.panelFontFamily
              font.pixelSize: Style.font.caption
              font.bold: parent.active
            }

            TapHandler { onTapped: root.watchlist.setBarDisplay(parent.modelData) }
          }
        }
      }
    }

    // Only the pinned mode names a symbol; the other two have nothing to pick.
    Row {
      width: parent.width
      visible: root.watchlist.barDisplay === "pinned"
      spacing: Style.space(6)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "Pinned"
        color: root.mutedColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.caption
      }

      Flow {
        width: parent.width - Style.space(60)
        spacing: Style.space(4)

        Repeater {
          model: root.symbols

          Rectangle {
            required property string modelData
            readonly property bool active: root.watchlist.canonical(root.watchlist.pinnedSymbol) === modelData

            implicitWidth: pinLabel.implicitWidth + Style.space(10)
            implicitHeight: Style.space(18)
            radius: 0
            color: active
              ? Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.14)
              : "transparent"
            border.width: 1
            border.color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, active ? 0.35 : 0.15)

            Text {
              id: pinLabel
              anchors.centerIn: parent
              text: SymbolID.displayCode(SymbolID.parse(parent.modelData))
              color: root.textColor
              font.family: root.panelFontFamily
              font.pixelSize: Style.font.caption
            }

            TapHandler { onTapped: root.watchlist.setPinnedSymbol(parent.modelData) }
          }
        }
      }
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
