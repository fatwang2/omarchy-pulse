import QtQuick
import qs.Commons
import "../Model.js" as Model

// The quote detail. Everything here is a fact the row had no space for, in the
// order someone asks for it: what it costs, what it did today, and where the
// number came from. Provenance is not an afterthought — a delayed price and a
// real-time price look identical until the panel says which one this is.
Column {
  id: root

  required property var row
  required property color textColor
  required property color riseColor
  required property color fallColor
  required property color mutedColor
  required property string panelFontFamily
  property double nowMs: 0

  signal dismissed()

  readonly property var quote: row ? row.quote : null
  readonly property bool hasQuote: !!quote
  readonly property real changePercent: row ? Number(row.changePercent || 0) : 0
  readonly property color movementColor: !hasQuote
    ? mutedColor
    : (changePercent > 0 ? riseColor : (changePercent < 0 ? fallColor : textColor))

  function fieldText(value) {
    return (typeof value === "number" && isFinite(value)) ? Model.formatPrice(value) : "—"
  }

  function delayText() {
    if (!hasQuote) return "—"
    var delay = quote.sourceDelaySeconds
    if (delay === null || delay === undefined) return "unknown"
    if (delay <= 0) return "real time"
    return "delayed " + Math.round(delay / 60) + " min"
  }

  function timestampText() {
    if (!hasQuote || !quote.timestampMs) return "—"
    var date = new Date(quote.timestampMs)
    return Qt.formatDateTime(date, "yyyy-MM-dd HH:mm:ss")
  }

  spacing: Style.space(10)

  component Field: Item {
    required property string label
    required property string value
    property color valueColor: root.textColor
    implicitHeight: Style.space(28)

    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: parent.label
      color: root.mutedColor
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.caption
    }
    Text {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: parent.value
      color: parent.valueColor
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }
  }

  Item {
    width: parent.width
    implicitHeight: Style.space(46)

    Column {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(3)

      Text {
        text: root.row ? root.row.displayCode : ""
        color: root.textColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }
      Text {
        text: (root.row && root.row.name) ? String(root.row.name).toUpperCase() : "—"
        color: root.mutedColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Column {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(3)

      Text {
        anchors.right: parent.right
        text: root.hasQuote ? Model.formatPrice(root.quote.price) : "—"
        color: root.textColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }
      Text {
        anchors.right: parent.right
        text: root.hasQuote
          ? (Model.formatChange(root.row.change) + "  " + Model.formatPercent(root.row.changePercent))
          : "—"
        color: root.movementColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  Rectangle {
    width: parent.width
    height: 1
    color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.15)
  }

  Column {
    width: parent.width

    Field { width: parent.width; label: "Open"; value: root.fieldText(root.hasQuote ? root.quote.open : null) }
    Field { width: parent.width; label: "High"; value: root.fieldText(root.hasQuote ? root.quote.high : null) }
    Field { width: parent.width; label: "Low"; value: root.fieldText(root.hasQuote ? root.quote.low : null) }
    Field {
      width: parent.width
      label: "Amplitude"
      value: (root.row && typeof root.row.amplitudePercent === "number")
        ? root.row.amplitudePercent.toFixed(2) + "%"
        : "—"
    }
    Field {
      width: parent.width
      label: "Prev close"
      value: root.fieldText(root.hasQuote ? root.quote.previousClose : null)
    }
    Field {
      width: parent.width
      label: "Volume"
      value: root.hasQuote ? Model.formatVolume(root.quote.volume) : "—"
    }
    // The last completed regular session, shown only when the live price is
    // from some other session — otherwise it would repeat the line above it.
    Field {
      width: parent.width
      visible: root.hasQuote && !!root.quote.regularSession
      label: "At the close"
      value: (root.hasQuote && root.quote.regularSession)
        ? (Model.formatPrice(root.quote.regularSession.price)
           + "  " + Model.formatPercent(root.row.regularChangePercent))
        : "—"
      valueColor: (root.row && typeof root.row.regularChangePercent === "number")
        ? (root.row.regularChangePercent > 0
            ? root.riseColor
            : (root.row.regularChangePercent < 0 ? root.fallColor : root.textColor))
        : root.textColor
    }
  }

  Rectangle {
    width: parent.width
    height: 1
    color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.15)
  }

  Column {
    width: parent.width

    Field {
      width: parent.width
      label: "Currency"
      value: root.hasQuote ? String(root.quote.currencyCode || "—") : "—"
    }
    Field {
      width: parent.width
      label: "Source"
      value: root.hasQuote
        ? (String(root.quote.sourceName || "—") + " · " + root.delayText())
        : "—"
    }
    Field { width: parent.width; label: "As of"; value: root.timestampText() }
  }
}
