import QtQuick
import QtQuick.Shapes
import qs.Commons

// The official Proton Pass mark, drawn natively from its SVG so it takes
// the theme colour instead of the brand purple gradient — the same
// approach ProtonIcon.qml (VPN plugin) and TailscaleIcon.qml use.
//
// Source: proton.me Proton Pass icon (viewBox 0 0 512 512). The mark is
// two overlapping rounded squares. Two layers in ONE theme colour: the
// rear square at a lower opacity, the front square opaque, so it reads
// with the same front/back depth as the brand logo.
//
// Both layers bind `fillColor` straight to `root.color` (reactive), and
// the rear layer's fade comes from `opacity` on its own Shape — not from
// Qt.rgba(color.r, color.g, color.b, a), which doesn't re-evaluate when
// the colour (i.e. the theme) changes because .r/.g/.b sub-property reads
// aren't tracked as dependencies.
//
// Proton and Proton Pass are trademarks of Proton AG. This is an
// unofficial community plugin, not affiliated with or endorsed by Proton.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  // Opacity of the rear square. Lower = more contrast between the lobes.
  property real backAlpha: 0.45

  readonly property real viewBox: 512
  readonly property string markRear: "M154 64.7c35.7-35.7 53.6-53.6 74.2-60.3 18.1-5.9 37.6-5.9 55.7 0 20.6 6.7 38.4 24.5 74.2 60.3l89.3 89.3c35.7 35.7 53.6 53.6 60.3 74.2 5.9 18.1 5.9 37.6 0 55.7-6.7 20.6-24.6 38.4-60.3 74.2L358 447.3c-35.7 35.7-53.6 53.6-74.2 60.3-18.1 5.9-37.6 5.9-55.7 0-20.6-6.7-38.5-24.6-74.2-60.3l-16.8-18.8c-10.2-11.4-15.2-17.1-18.9-23.6-3.2-5.7-5.6-11.9-7-18.4-1.6-7.2-1.6-14.9-1.6-30.1V155.5c0-15.3 0-22.9 1.6-30.1 1.4-6.4 3.8-12.6 7-18.3 3.6-6.5 8.7-12.2 18.9-23.6z"
  readonly property string markFront: "M147.6 71.1c17.9-17.9 26.8-26.8 37.1-30.1 9.1-2.9 18.8-2.9 27.9 0 10.3 3.3 19.2 12.3 37.1 30.1L383.5 205c17.9 17.9 26.8 26.8 30.1 37.1 2.9 9.1 2.9 18.8 0 27.9-3.3 10.3-12.3 19.2-30.1 37.1L249.6 440.9c-17.9 17.9-26.8 26.8-37.1 30.1-9.1 2.9-18.8 2.9-27.9 0-10.3-3.3-19.2-12.3-37.1-30.1L64.7 358C29 322.3 11.1 304.5 4.4 283.9c-5.9-18.1-5.9-37.6 0-55.7 6.7-20.6 24.5-38.5 60.3-74.2z"

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  Item {
    anchors.centerIn: parent
    width: root.viewBox
    height: root.viewBox
    // Draw at the native 512px box, then scale the geometry down so the
    // curves stay crisp rather than being rasterised then stretched.
    scale: Math.min(root.width, root.height) / root.viewBox

    // Rear square (larger, top-right lobe) — faded via Shape opacity.
    Shape {
      anchors.fill: parent
      antialiasing: true
      layer.enabled: true
      layer.samples: 4
      opacity: root.backAlpha
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        fillColor: root.color
        strokeWidth: 0
        strokeColor: "transparent"
        PathSvg { path: root.markRear }
      }
    }

    // Front square (smaller, bottom-left lobe) — opaque, on top.
    Shape {
      anchors.fill: parent
      antialiasing: true
      layer.enabled: true
      layer.samples: 4
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        fillColor: root.color
        strokeWidth: 0
        strokeColor: "transparent"
        PathSvg { path: root.markFront }
      }
    }
  }
}
