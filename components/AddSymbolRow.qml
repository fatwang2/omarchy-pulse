import QtQuick
import qs.Commons
import qs.Ui
import "../Market.js" as Market

// The add flow, summoned by the header's search button the way the macOS
// magnifier summons its search field. It adds to whichever list is active,
// and folds away when dismissed or when a symbol lands.
Column {
  id: root

  required property var watchlist
  required property var search
  required property color textColor
  required property color mutedColor
  required property string panelFontFamily

  signal dismissed()

  function focusInput() {
    queryField.forceActiveFocus()
  }

  function clear() {
    queryField.text = ""
    root.search.clear()
  }

  spacing: Style.space(6)

  TextField {
    id: queryField
    width: parent.width
    placeholderText: "Add — name or code: nvidia, 600519.SH, 7203.T"
    onTextChanged: root.search.query = text
    Keys.onEscapePressed: {
      root.clear()
      root.dismissed()
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

  // Results are capped at five: this sits above the list it is about to
  // change, and pushing that list off screen to show a sixth candidate is the
  // wrong trade.
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
        implicitHeight: Style.space(30)
        radius: 0
        color: resultHover.hovered
          ? Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.06)
          : "transparent"

        HoverHandler { id: resultHover }
        TapHandler {
          enabled: !resultRow.alreadyAdded
          onTapped: {
            root.watchlist.addSymbol(resultRow.modelData.key)
            root.clear()
            root.dismissed()
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
            width: Math.max(0, resultRow.width - Style.space(160))
            text: resultRow.modelData.name ? String(resultRow.modelData.name) : "Add by code"
            color: root.mutedColor
            font.family: root.panelFontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        // A symbol already on the active list says so rather than offering an
        // add that would silently do nothing.
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

  PanelSeparator {}
}
