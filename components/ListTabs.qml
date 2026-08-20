import QtQuick
import qs.Commons
import qs.Ui

// The named-list strip, the way the macOS popover carries its lists across
// the top. Tabs switch lists; "+" creates one; the pencil enters edit mode,
// which is also where the rows below grow their reorder-and-remove controls.
// In edit mode a tab's label becomes an inline rename and a delete appears
// beside it — the macOS right-click menu, simplified to one visible state.
Item {
  id: root

  required property var names
  required property string activeName
  required property color textColor
  required property color accentColor
  required property string panelFontFamily
  property bool editMode: false
  property int listCount: names ? names.length : 0

  signal selected(string name)
  signal addRequested()
  signal renameRequested(string name, string newName)
  signal removeRequested(string name)

  // Which tab is being renamed. Cleared when edit mode ends.
  property string renaming: ""
  onEditModeChanged: if (!editMode) renaming = ""

  implicitHeight: Style.space(24)

  Flickable {
    // Lists are user-named and unbounded; the strip scrolls rather than
    // shrinking labels into ambiguity.
    anchors.left: parent.left
    anchors.right: tools.left
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
          readonly property bool renaming: root.renaming === modelData

          height: parent.height
          implicitWidth: renaming
            ? renameField.implicitWidth + Style.space(8)
            : tabContent.implicitWidth + Style.space(16)
          radius: 0
          color: active
            ? Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.12)
            : tabHover.hovered
              ? Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.06)
              : "transparent"

          HoverHandler { id: tabHover }
          TapHandler {
            enabled: !tab.renaming
            onTapped: {
              if (root.editMode) root.renaming = tab.modelData
              else root.selected(tab.modelData)
            }
          }

          Row {
            id: tabContent
            visible: !tab.renaming
            anchors.centerIn: parent
            spacing: Style.space(5)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: tab.modelData
              color: tab.active
                ? root.textColor
                : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.55)
              font.family: root.panelFontFamily
              font.pixelSize: Style.font.caption
              font.bold: tab.active
            }

            // Delete rides inside the tab only in edit mode. The last list is
            // not deletable — a strip with no tabs reads as a broken panel.
            Text {
              visible: root.editMode && root.listCount > 1
              anchors.verticalCenter: parent.verticalCenter
              text: "✕"
              color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.45)
              font.family: root.panelFontFamily
              font.pixelSize: Style.font.caption
              TapHandler { onTapped: root.removeRequested(tab.modelData) }
            }
          }

          TextField {
            id: renameField
            visible: tab.renaming
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Style.space(4)
            width: Math.max(Style.space(70), implicitWidth)
            foreground: root.textColor
            text: tab.modelData
            onVisibleChanged: if (visible) { forceActiveFocus(); selectAll() }
            onAccepted: {
              root.renameRequested(tab.modelData, text)
              root.renaming = ""
            }
            Keys.onEscapePressed: root.renaming = ""
          }
        }
      }
    }
  }

  Row {
    id: tools
    anchors.right: parent.right
    height: parent.height
    spacing: 0

    PanelActionButton {
      iconText: "󰐕"
      tooltipText: "New list"
      foreground: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.55)
      fontFamily: root.panelFontFamily
      onClicked: root.addRequested()
    }

    PanelActionButton {
      iconText: "󰏫"
      tooltipText: root.editMode ? "Done editing" : "Edit lists (e)"
      foreground: root.editMode
        ? root.textColor
        : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.55)
      fontFamily: root.panelFontFamily
      onClicked: root.editMode = !root.editMode
    }
  }
}
