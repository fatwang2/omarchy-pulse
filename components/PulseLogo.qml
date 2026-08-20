import QtQuick

// The Pulse mark: a single tick line, drawn rather than shipped as an asset so
// it takes the bar's own foreground color and stays sharp at every bar scale.
// It is a mark, not a brand asset, so it has no fixed colors of its own.
Canvas {
  id: root

  // Required rather than defaulted: a fallback hex is a color that survives
  // into production looking wrong on every theme but the one it was written
  // against. Every caller passes the surface's own foreground down.
  required property color foregroundColor
  property real strokeScale: 0.11

  onForegroundColorChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()

    var w = width
    var h = height
    var stroke = Math.max(1, Math.round(Math.min(w, h) * strokeScale))

    ctx.strokeStyle = foregroundColor
    ctx.lineWidth = stroke
    ctx.lineJoin = "round"
    ctx.lineCap = "round"

    // A flat baseline into one spike and out again — the shape of a heartbeat
    // trace, which is the same shape as a market that just moved.
    ctx.beginPath()
    ctx.moveTo(w * 0.06, h * 0.58)
    ctx.lineTo(w * 0.30, h * 0.58)
    ctx.lineTo(w * 0.42, h * 0.22)
    ctx.lineTo(w * 0.56, h * 0.82)
    ctx.lineTo(w * 0.68, h * 0.42)
    ctx.lineTo(w * 0.78, h * 0.58)
    ctx.lineTo(w * 0.94, h * 0.58)
    ctx.stroke()
  }
}
