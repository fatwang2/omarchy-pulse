import QtQuick
import qs.Commons
import "../Model.js" as Model

// The rows of the active list, with the feed's state as a footer — where the
// macOS popover keeps its "Streaming live" line. The view renders; membership,
// tabs and search live with the panel.
Column {
  id: root

  required property var rows
  required property color textColor
  required property color riseColor
  required property color fallColor
  required property color mutedColor
  required property string panelFontFamily
  property string status: "idle"
  property string message: ""
  property double nowMs: 0

  property int selectedIndex: 0
  property bool detailOpen: false

  readonly property var selectedRow: (selectedIndex >= 0 && selectedIndex < rows.length)
    ? rows[selectedIndex]
    : null

  function moveSelection(delta) {
    var count = rows.length
    if (count === 0) return
    selectedIndex = Math.max(0, Math.min(count - 1, selectedIndex + delta))
    list.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  onRowsChanged: {
    if (selectedIndex >= rows.length) selectedIndex = Math.max(0, rows.length - 1)
  }

  spacing: Style.space(8)

  Text {
    width: parent.width
    visible: root.message !== ""
    text: root.message
    color: root.mutedColor
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  ListView {
    id: list
    width: parent.width
    // The list is the panel's only elastic surface: it takes what the header,
    // the tabs and the footer leave it.
    height: Math.min(contentHeight, Style.space(520))
    visible: root.rows.length > 0
    clip: true
    model: root.rows
    currentIndex: root.selectedIndex
    boundsBehavior: Flickable.StopAtBounds
    reuseItems: true

    delegate: WatchlistRow {
      required property var modelData
      required property int index
      row: modelData
      striped: index % 2 === 1
      selected: index === root.selectedIndex
      nowMs: root.nowMs
      textColor: root.textColor
      riseColor: root.riseColor
      fallColor: root.fallColor
      mutedColor: root.mutedColor
      panelFontFamily: root.panelFontFamily
      onActivated: {
        root.selectedIndex = index
        root.detailOpen = true
      }
    }
  }

  Text {
    width: parent.width
    visible: root.rows.length === 0
    text: "This list is empty. Press / to add a symbol."
    color: root.mutedColor
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  // The feed footer: either the panel has current prices or it says why not,
  // in the corner the eye checks last.
  Item {
    width: parent.width
    implicitHeight: Style.space(18)

    StatusDot {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      status: root.status
      textColor: root.textColor
      liveColor: root.riseColor
      errorColor: root.fallColor
      panelFontFamily: root.panelFontFamily
    }

    Text {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: root.rows.length + (root.rows.length === 1 ? " symbol" : " symbols")
      color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.35)
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
