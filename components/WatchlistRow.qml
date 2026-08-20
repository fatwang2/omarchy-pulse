import QtQuick
import qs.Commons
import "../Model.js" as Model

// One instrument. The row is built to be read in the time it takes to glance
// at the bar and look away again: code and price on the baseline, everything
// that qualifies them one step dimmer underneath.
Rectangle {
  id: root

  required property var row
  required property color textColor
  required property color riseColor
  required property color fallColor
  required property color mutedColor
  required property string panelFontFamily
  property bool selected: false
  property bool striped: false
  property double nowMs: 0

  signal activated()

  readonly property var quote: row.quote
  readonly property bool hasQuote: !!quote
  readonly property bool stale: hasQuote && Model.isStale(quote, nowMs)
  readonly property real changePercent: Number(row.changePercent || 0)
  // Flat is not a rise. A zero change takes the neutral foreground so the eye
  // is not told something moved when nothing did.
  readonly property color movementColor: !hasQuote
    ? mutedColor
    : (changePercent > 0 ? riseColor : (changePercent < 0 ? fallColor : textColor))
  readonly property string sessionLabel: Model.sessionLabel(quote)

  width: ListView.view ? ListView.view.width : implicitWidth
  implicitHeight: Style.space(42)
  radius: 0
  color: selected
    ? Qt.rgba(textColor.r, textColor.g, textColor.b, 0.10)
    : hover.hovered
      ? Qt.rgba(textColor.r, textColor.g, textColor.b, 0.05)
      : striped
        ? Qt.rgba(textColor.r, textColor.g, textColor.b, 0.025)
        : "transparent"

  HoverHandler { id: hover }
  TapHandler { onTapped: root.activated() }

  Column {
    id: identity
    anchors.left: parent.left
    anchors.leftMargin: Style.space(9)
    anchors.right: chart.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(3)

    Row {
      spacing: Style.space(6)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.row.displayCode
        color: root.textColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      MarketBadge {
        anchors.verticalCenter: parent.verticalCenter
        label: root.row.marketLabel
        textColor: root.textColor
        panelFontFamily: root.panelFontFamily
      }

      // Only extended sessions get a marker. A regular session is the default
      // state of a watchlist and does not need saying.
      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.sessionLabel !== ""
        text: root.sessionLabel
        color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.45)
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.caption
      }
    }

    // The name is uppercased; an error is not. An error is a sentence, and
    // shouting it reads as a fault in the app rather than a label on the row.
    Text {
      width: parent.width
      text: root.row.error
        ? root.row.error
        : (root.row.name ? String(root.row.name).toUpperCase() : "—")
      color: root.mutedColor
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  Sparkline {
    id: chart
    anchors.right: figures.left
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(58)
    height: Style.space(22)
    series: root.hasQuote ? root.quote.series : null
    previousClose: root.hasQuote ? Number(root.quote.previousClose || 0) : 0
    lineColor: root.movementColor
    guideColor: root.textColor
  }

  Column {
    id: figures
    anchors.right: parent.right
    anchors.rightMargin: Style.space(9)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(104)
    spacing: Style.space(3)

    Text {
      anchors.right: parent.right
      text: root.hasQuote ? Model.formatPrice(root.quote.price) : "—"
      color: root.textColor
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      // A price that has stopped arriving is dimmed rather than hidden: the
      // last known number is still the best answer available.
      opacity: root.stale ? 0.55 : 1.0
    }

    Row {
      anchors.right: parent.right
      spacing: Style.space(6)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.stale
        text: "STALE"
        color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.40)
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.hasQuote ? Model.formatPercent(root.row.changePercent) : "—"
        color: root.movementColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
