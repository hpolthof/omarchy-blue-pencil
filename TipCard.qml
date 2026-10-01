import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// One editor's note. Checking it strikes the title, dims it and hides the body;
// clicking a done title expands the body again.
Rectangle {
  id: root

  property var tip: null
  property color foreground: Color.foreground

  signal doneToggled(bool done)
  signal hoverStarted()
  signal hoverEnded()

  readonly property bool done: tip ? tip.done === true : false
  property bool expanded: false
  readonly property bool showBody: !done || expanded
  readonly property string kind: tip && tip.kind ? String(tip.kind) : ""
  readonly property string kindLabel: Model.KIND_LABELS && Model.KIND_LABELS[kind] ? Model.KIND_LABELS[kind] : kind
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color kindColor: kind === "pitfall" ? Color.urgent
                                    : kind === "keep" ? Color.accent : dim
  readonly property real pad: Style.spacing.xl
  readonly property real boxSize: Style.space(16)

  implicitHeight: content.implicitHeight + pad * 2
  height: implicitHeight
  radius: Style.cornerRadius
  color: hover.hovered ? Style.hoverFill : Style.normalFill

  Behavior on color { ColorAnimation { duration: 60 } }

  onDoneChanged: if (!done) expanded = false

  HoverHandler {
    id: hover
    onHoveredChanged: hovered ? root.hoverStarted() : root.hoverEnded()
  }

  Item {
    id: checkBox
    x: root.pad
    y: root.pad
    width: root.boxSize
    height: root.boxSize

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius / 2
      color: root.done ? Style.selectedAccentFill : "transparent"
      border.width: Math.max(1, Style.normalBorderWidth)
      border.color: root.done || checkMouse.containsMouse ? Color.accent : Qt.darker(root.foreground, 1.6)

      Text {
        anchors.centerIn: parent
        visible: root.done
        textFormat: Text.PlainText
        text: Model.GLYPH.check
        color: Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }

    MouseArea {
      id: checkMouse
      anchors.fill: parent
      anchors.margins: -Style.spacing.sm
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.doneToggled(!root.done)
    }
  }

  Column {
    id: content
    x: root.pad + root.boxSize + Style.spacing.xl
    y: root.pad
    width: root.width - x - root.pad
    spacing: Style.spacing.xs

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.kindLabel.toUpperCase()
      color: root.kindColor
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.0
      elide: Text.ElideRight
      opacity: root.done ? 0.6 : 1
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.tip && root.tip.title ? String(root.tip.title) : ""
      color: root.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.bold: true
      font.strikeout: root.done
      wrapMode: Text.WordWrap
      opacity: root.done ? 0.5 : 1

      MouseArea {
        anchors.fill: parent
        enabled: root.done
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.expanded = !root.expanded
      }
    }

    Text {
      visible: root.showBody
      width: parent.width
      height: visible ? implicitHeight : 0
      textFormat: Text.PlainText
      text: root.tip && root.tip.body ? String(root.tip.body) : ""
      color: root.done ? root.dim : Qt.darker(root.foreground, 1.15)
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
    }
  }
}
