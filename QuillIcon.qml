import QtQuick
import QtQuick.Shapes

// Blue Pencil's mark: a quill with the line of ink it just left behind.
// Drawn as strokes on a 24-unit grid so it follows the theme colour and
// stays crisp at any size. Source artwork: assets/quill.svg.
Item {
  id: root

  property real size: 16
  property color color: "white"
  property real strokeWidth: 1.5

  implicitWidth: size
  implicitHeight: size

  Shape {
    width: 24
    height: 24
    scale: root.size / 24
    transformOrigin: Item.TopLeft
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeColor: root.color
      strokeWidth: root.strokeWidth
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      // Shaft, curving from the nib to the tip.
      PathSvg { path: "M3.2 20.8 Q 11.6 13.4 21 2.6" }
    }
    ShapePath {
      strokeColor: root.color
      strokeWidth: root.strokeWidth
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      // Outer vane, split twice like a real feather.
      PathSvg { path: "M9.4 14.4 C 6.8 12.2 7.6 8.8 10.0 7.0 L 11.2 8.6 L 11.6 6.0 C 13.6 4.6 16.6 3.2 21 2.6" }
    }
    ShapePath {
      strokeColor: root.color
      strokeWidth: root.strokeWidth
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      // Inner vane.
      PathSvg { path: "M21 2.6 C 20.2 5.8 18.6 8.0 16.4 9.6 L 15.0 9.0 L 14.8 10.8 C 13.6 11.6 12.4 12.2 11.2 12.6" }
    }
    ShapePath {
      strokeColor: root.color
      strokeWidth: root.strokeWidth
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      // The line of writing it left behind.
      PathSvg { path: "M6.4 20.6 c 0.8 -1.6 2.2 -1.6 2.6 0 c 0.4 1.6 2.0 1.6 2.6 0 c 0.6 -1.6 2.0 -1.6 2.6 0 c 0.5 1.4 2.0 1.4 3.4 0" }
    }
  }
}
