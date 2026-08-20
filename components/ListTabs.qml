import QtQuick
import qs.Commons

// The named-list strip, the way the macOS popover carries New / Position /
// Watching across its top. Tabs switch which list the rows below show; the
// trailing "+" creates a list. Renaming and deleting live in settings — a tab
// strip that edits itself on the wrong click loses lists.
Item {
  id: root

  required property var names
  required property string activeName
  required property color textColor
  required property color accentColor
  required property string panelFontFamily

  signal selected(string name)
  signal addRequested()

  implicitHeight: Style.space(24)

  Flickable {
    // Lists are user-named and unbounded; the strip scrolls rather than
    // shrinking labels into ambiguity.
    anchors.left: parent.left
    anchors.right: addButton.left
    anchors.rightMargin: Style.space(6)
    height: parent.height
    contentWidth: tabRow.implicitWidth
    contentHeight: height
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Row {
      id: tabRow
      height: parent.height
      spacing: Style.space(4)

      Repeater {
        model: root.names

        Rectangle {
          id: tab
          required property string modelData
          readonly property bool active: modelData === root.activeName

          height: parent.height
          implicitWidth: tabLabel.implicitWidth + Style.space(16)
          radius: 0
          color: active
            ? Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.12)
            : tabHover.hovered
              ? Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.06)
              : "transparent"

          HoverHandler { id: tabHover }
          TapHandler { onTapped: root.selected(tab.modelData) }

          Text {
            id: tabLabel
            anchors.centerIn: parent
            text: tab.modelData
            color: tab.active
              ? root.textColor
              : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.55)
            font.family: root.panelFontFamily
            font.pixelSize: Style.font.caption
            font.bold: tab.active
          }
        }
      }
    }
  }

  Rectangle {
    id: addButton
    anchors.right: parent.right
    height: parent.height
    width: Style.space(22)
    radius: 0
    color: addHover.hovered
      ? Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.06)
      : "transparent"

    HoverHandler { id: addHover }
    TapHandler { onTapped: root.addRequested() }

    Text {
      anchors.centerIn: parent
      text: "+"
      color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.55)
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
