import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Right column: the editor's notes plus run status / errors.
Item {
  id: root

  property var host: null
  property color foreground: Color.foreground

  signal closeRequested()
  signal askAgainRequested()
  signal openSettingsRequested()
  signal quoteHovered(string quote)
  signal quoteUnhovered()

  readonly property var store: host && host.store ? host.store : null
  readonly property var current: store && store.current ? store.current : null
  readonly property var tips: current && current.advice && current.advice.tips ? current.advice.tips : []
  readonly property bool hasAdvice: current && current.advice ? true : false
  readonly property bool running: host ? host.adviceRunning === true : false
  readonly property string errorText: host && host.adviceError ? String(host.adviceError) : ""
  readonly property string errorCode: host && host.adviceErrorCode ? String(host.adviceErrorCode) : ""

  readonly property int doneCount: {
    var n = 0
    for (var i = 0; i < tips.length; i++) if (tips[i].done) n++
    return n
  }
  // Open tips first, done ones sink; original order kept within each group.
  readonly property var orderedTips: {
    var open = [], done = []
    for (var i = 0; i < tips.length; i++) (tips[i].done ? done : open).push(tips[i])
    return open.concat(done)
  }

  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color faint: Qt.darker(foreground, 1.85)

  property real nowMs: Date.now()
  readonly property int elapsedSec: {
    var start = host && host.adviceStartedAt ? Number(host.adviceStartedAt) : 0
    return start > 0 ? Math.max(0, Math.floor((nowMs - start) / 1000)) : 0
  }
  function formatElapsed(s) {
    var m = Math.floor(s / 60), r = s % 60
    return m + ":" + (r < 10 ? "0" : "") + r
  }

  function scrollBy(dy) {
    var maxY = Math.max(0, list.contentHeight - list.height)
    list.contentY = Math.max(0, Math.min(maxY, list.contentY + dy * Style.space(72)))
  }

  // Delegates are rebuilt when the order changes, so a hovered card can vanish
  // without a leave event.
  onOrderedTipsChanged: root.quoteUnhovered()

  Timer {
    interval: 1000
    repeat: true
    running: root.running
    triggeredOnStart: true
    onTriggered: root.nowMs = Date.now()
  }

  // ---------------------------------------------------------------- header
  Item {
    id: header
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: Math.max(headerText.implicitHeight, Style.space(22))

    PanelSectionHeader {
      id: headerText
      anchors.left: parent.left
      anchors.right: headerButtons.left
      anchors.verticalCenter: parent.verticalCenter
      foreground: root.foreground
      elide: Text.ElideRight
      text: root.tips.length > 0
            ? "ADVICE · " + root.doneCount + " of " + root.tips.length + " done"
            : "ADVICE"
    }

    Row {
      id: headerButtons
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.xs

      PanelActionButton {
        iconText: Model.GLYPH.refresh
        tooltipText: "Ask again"
        foreground: root.foreground
        enabled: !root.running
        onClicked: root.askAgainRequested()
      }
      PanelActionButton {
        iconText: Model.GLYPH.close
        tooltipText: "Close advice"
        foreground: root.foreground
        onClicked: root.closeRequested()
      }
    }
  }

  // ---------------------------------------------------------------- status
  Item {
    id: statusRow
    visible: root.running
    anchors.top: header.bottom
    anchors.topMargin: Style.spacing.rowGap
    anchors.left: parent.left
    anchors.right: parent.right
    height: visible ? Math.max(cancelButton.implicitHeight, statusLabel.implicitHeight) : 0

    Rectangle {
      id: dot
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(8)
      height: width
      radius: width / 2
      color: Color.accent

      SequentialAnimation on opacity {
        running: root.running
        loops: Animation.Infinite
        NumberAnimation { from: 1.0; to: 0.25; duration: 650; easing.type: Easing.InOutQuad }
        NumberAnimation { from: 0.25; to: 1.0; duration: 650; easing.type: Easing.InOutQuad }
      }
    }

    Text {
      id: statusLabel
      anchors.left: dot.right
      anchors.leftMargin: Style.spacing.lg
      anchors.right: cancelButton.left
      anchors.rightMargin: Style.spacing.lg
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      elide: Text.ElideRight
      text: (root.host && root.host.adviceMessage ? String(root.host.adviceMessage) : "Working…")
            + " · " + root.formatElapsed(root.elapsedSec)
      color: root.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }

    Button {
      id: cancelButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: "Cancel"
      fontSize: Style.font.bodySmall
      bordered: true
      onClicked: if (root.host) root.host.cancelAdvice()
    }
  }

  // ----------------------------------------------------------------- error
  Rectangle {
    id: errorCard
    visible: root.errorText !== "" && !root.running
    anchors.top: statusRow.visible ? statusRow.bottom : header.bottom
    anchors.topMargin: Style.spacing.rowGap
    anchors.left: parent.left
    anchors.right: parent.right
    height: visible ? errorCol.implicitHeight + Style.spacing.xl * 2 : 0
    radius: Style.cornerRadius
    color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.10)
    border.width: Math.max(1, Style.normalBorderWidth)
    border.color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.45)

    Column {
      id: errorCol
      x: Style.spacing.xl
      y: Style.spacing.xl
      width: parent.width - Style.spacing.xl * 2
      spacing: Style.spacing.md

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.errorText
        color: Color.urgent
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        wrapMode: Text.WordWrap
      }
      Text {
        visible: text !== ""
        width: parent.width
        textFormat: Text.PlainText
        text: root.errorCode === "not-signed-in" ? "Sign in with `claude` / `codex` in a terminal, then ask again."
            : root.errorCode === "not-installed" ? "Run a scan in Settings."
            : root.errorCode === "rate-limit" ? "The AI service is rate limiting you. Wait a moment and ask again."
            : root.errorCode === "timeout" ? "That took too long. Try again, or a shorter text."
            : root.errorCode === "unsafe" ? "Blue Pencil only sends your text to an AI that runs without tools. Try the other provider in Settings."
            : ""
        color: root.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }
      Button {
        visible: root.errorCode === "not-installed" || root.errorCode === "not-signed-in"
        text: "Open settings"
        fontSize: Style.font.bodySmall
        bordered: true
        onClicked: root.openSettingsRequested()
      }
    }
  }

  // ------------------------------------------------------------------ tips
  Flickable {
    id: list
    anchors.top: errorCard.visible ? errorCard.bottom : (statusRow.visible ? statusRow.bottom : header.bottom)
    anchors.topMargin: Style.spacing.rowGap
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    contentWidth: width
    contentHeight: tipColumn.height

    Column {
      id: tipColumn
      width: list.width
      spacing: Style.spacing.lg

      Repeater {
        model: root.orderedTips
        delegate: TipCard {
          required property var modelData
          width: tipColumn.width
          tip: modelData
          foreground: root.foreground
          onDoneToggled: function(done) {
            if (root.store) root.store.setTipDone(modelData.id, done)
          }
          onHoverStarted: root.quoteHovered(modelData.quote ? String(modelData.quote) : "")
          onHoverEnded: root.quoteUnhovered()
        }
      }

      Text {
        visible: !root.running && root.errorText === "" && root.tips.length === 0
        width: parent.width
        topPadding: Style.spacing.panelGap
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: root.hasAdvice ? "Nothing to flag. Looks good." : "No notes yet. Ask for advice to get started."
        color: root.faint
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        visible: root.tips.length > 0 && root.doneCount === root.tips.length && !root.running
        width: parent.width
        topPadding: Style.spacing.sm
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
        text: "All notes done."
        color: root.faint
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
}
