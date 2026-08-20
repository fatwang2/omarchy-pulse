import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// The watchlist. Rows are keyed by symbol so a price tick updates a delegate in
// place instead of rebuilding the list — handing a fresh array to the view on
// every refresh destroys and recreates every delegate, which flickers the list
// and throws away the scroll position.
Column {
  id: root

  required property var rows
  required property color textColor
  required property color riseColor
  required property color fallColor
  required property color accentColor
  required property color mutedColor
  required property string panelFontFamily
  property string status: "idle"
  property string message: ""
  property double nowMs: 0

  property string filterText: ""
  property bool searching: false
  property int selectedIndex: 0
  property bool detailOpen: false

  readonly property var visibleRows: Model.filterRows(rows, filterText)
  readonly property var selectedRow: (selectedIndex >= 0 && selectedIndex < visibleRows.length)
    ? visibleRows[selectedIndex]
    : null

  signal refreshRequested()

  function moveSelection(delta) {
    var count = visibleRows.length
    if (count === 0) return
    selectedIndex = Math.max(0, Math.min(count - 1, selectedIndex + delta))
    list.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function focusSearch() {
    searching = true
    filterField.forceActiveFocus()
  }

  function clearSearch() {
    filterText = ""
    searching = false
    filterField.text = ""
  }

  onVisibleRowsChanged: {
    if (selectedIndex >= visibleRows.length) selectedIndex = Math.max(0, visibleRows.length - 1)
  }

  spacing: Style.space(8)

  Item {
    id: header
    width: parent.width
    implicitHeight: Style.space(24)

    // The count line names the filter's effect rather than leaving a short list
    // unexplained: "3 of 18" is the difference between a filter and an outage.
    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.searching
      text: root.filterText !== ""
        ? (root.visibleRows.length + " of " + root.rows.length + " symbols")
        : (root.rows.length + (root.rows.length === 1 ? " symbol" : " symbols"))
      color: root.mutedColor
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.caption
    }

    TextField {
      id: filterField
      anchors.left: parent.left
      anchors.right: searchButton.left
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      visible: root.searching
      placeholderText: "Filter"
      onTextChanged: root.filterText = text
      Keys.onEscapePressed: root.clearSearch()
    }

    Row {
      id: searchButton
      anchors.right: statusDot.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.searching ? "✕" : "⌕"
        color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.55)
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.bodySmall
      }
      TapHandler {
        onTapped: root.searching ? root.clearSearch() : root.focusSearch()
      }
    }

    StatusDot {
      id: statusDot
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      status: root.status
      textColor: root.textColor
      liveColor: root.riseColor
      errorColor: root.fallColor
      panelFontFamily: root.panelFontFamily
    }
  }

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
    // the message line and the panel's own maximum leave it.
    height: Math.min(contentHeight, Style.space(520))
    visible: root.visibleRows.length > 0
    clip: true
    model: root.visibleRows
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
    visible: root.visibleRows.length === 0
    text: root.rows.length === 0
      ? "No symbols yet. Add them to ~/.config/omarchy/pulse/watchlist.json"
      : "Nothing matches “" + root.filterText + "”"
    color: root.mutedColor
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }
}
