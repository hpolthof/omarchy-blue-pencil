import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Left column: goal, tone, the writing area and a footer. Talks to the store
// through `host`; never rewrites the user's text.
Item {
  id: root

  property var host: null
  property color foreground: Color.foreground

  signal closeRequested()
  signal adviceRequested()
  signal showAdviceRequested()
  signal newRequested()
  signal historyRequested()
  signal settingsRequested()

  readonly property var store: host && host.store ? host.store : null
  readonly property var current: store && store.current ? store.current : null
  readonly property string currentId: store && store.currentId ? String(store.currentId) : ""
  readonly property string storeText: current && current.text ? String(current.text) : ""
  readonly property string storeGoal: current && current.goal ? String(current.goal) : ""
  readonly property string storeTone: current && current.tone ? String(current.tone) : ""

  readonly property bool typing: goalField.activeFocus || toneField.activeFocus || area.activeFocus
  readonly property Item initialFocusItem: (storeText === "" && storeGoal === "") ? goalField : area

  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color faint: Qt.darker(foreground, 1.85)

  readonly property var tips: current && current.advice && current.advice.tips ? current.advice.tips : []
  readonly property int openTips: {
    var n = 0
    for (var i = 0; i < tips.length; i++) if (!tips[i].done) n++
    return n
  }
  readonly property bool adviceOpen: current ? current.adviceOpen === true : false
  readonly property bool adviceRunning: host ? host.adviceRunning === true : false
  readonly property bool hasAdvice: tips.length > 0 || adviceRunning
  // While the AI reads this draft, the draft is read-only: notes are anchored
  // to the exact words that were sent.
  readonly property bool locked: adviceRunning && currentId !== "" && host && host.adviceDraftId === currentId

  property bool _syncing: false
  property var hl: []

  // ------------------------------------------------------------ sync

  function syncFields(force) {
    root._syncing = true
    if (force || !goalField.activeFocus) { if (goalField.text !== storeGoal) goalField.text = storeGoal }
    if (force || !toneField.activeFocus) { if (toneField.text !== storeTone) toneField.text = storeTone }
    if (force || !area.activeFocus) {
      if (area.text !== storeText) {
        area.text = storeText
        if (force) flick.contentY = 0
      }
    }
    root._syncing = false
  }

  onCurrentIdChanged: { clearHighlight(); syncFields(true) }
  onStoreTextChanged: syncFields(false)
  onStoreGoalChanged: syncFields(false)
  onStoreToneChanged: syncFields(false)
  Component.onCompleted: syncFields(true)

  // ------------------------------------------------------------ focus / keys

  function focusInitial() { initialFocusItem.forceActiveFocus() }
  function focusEditor() { area.forceActiveFocus() }

  // Ctrl combos are safe to intercept even inside text inputs.
  function handleKey(event) {
    if (!(event.modifiers & Qt.ControlModifier)) return false
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { adviceRequested(); return true }
    if (event.key === Qt.Key_N) { newRequested(); return true }
    if (event.key === Qt.Key_H) { historyRequested(); return true }
    if (event.key === Qt.Key_Comma) { settingsRequested(); return true }
    return false
  }

  // ------------------------------------------------------------ highlight

  function clearHighlight() { if (hl.length > 0) hl = [] }

  function highlightQuote(quote) {
    var q = String(quote || "").trim()
    if (q === "") { clearHighlight(); return }
    var t = area.text
    var i = t.indexOf(q)
    if (i < 0) i = t.toLowerCase().indexOf(q.toLowerCase())
    if (i < 0) { clearHighlight(); return }
    var a = area.positionToRectangle(i)
    var b = area.positionToRectangle(i + q.length)
    var left = area.leftPadding
    var right = area.width - area.rightPadding
    var rects = []
    if (Math.abs(a.y - b.y) < 1) {
      rects.push({ x: a.x, y: a.y, w: Math.max(2, b.x - a.x), h: a.height })
    } else {
      rects.push({ x: a.x, y: a.y, w: Math.max(2, right - a.x), h: a.height })
      var step = Math.max(1, a.height)
      var n = 0
      for (var y = a.y + step; y < b.y - step / 2 && n < 80; y += step, n++)
        rects.push({ x: left, y: y, w: right - left, h: step })
      rects.push({ x: left, y: b.y, w: Math.max(2, b.x - left), h: b.height })
    }
    hl = rects
    var top = a.y
    var bottom = b.y + b.height
    if (top < flick.contentY || bottom > flick.contentY + flick.height) {
      var maxY = Math.max(0, flick.contentHeight - flick.height)
      flick.contentY = Math.max(0, Math.min(maxY, top - flick.height / 4))
    }
  }

  // ------------------------------------------------------------ layout

  Column {
    id: fieldsCol
    opacity: root.locked ? 0.55 : 1
    Behavior on opacity { NumberAnimation { duration: 180 } }
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Style.spacing.labelGap

    PanelSectionHeader {
      text: "GOAL"
      foreground: root.foreground
      width: parent.width
    }

    TextField {
      id: goalField
      width: parent.width
      readOnly: root.locked
      placeholderText: "What should this text achieve?"
      onTextChanged: if (!root._syncing && root.store) root.store.updateCurrent({ goal: text })
      onAccepted: toneField.forceActiveFocus()
      Keys.onEscapePressed: root.closeRequested()
      Keys.onTabPressed: toneField.forceActiveFocus()
      Keys.onBacktabPressed: area.forceActiveFocus()
      Keys.onPressed: function(event) { if (root.handleKey(event)) event.accepted = true }
    }

    Item { width: 1; height: Style.spacing.xs }

    PanelSectionHeader {
      text: "TONE"
      foreground: root.foreground
      width: parent.width
    }

    TextField {
      id: toneField
      width: parent.width
      readOnly: root.locked
      placeholderText: "How should it feel?"
      onTextChanged: if (!root._syncing && root.store) root.store.updateCurrent({ tone: text })
      onAccepted: area.forceActiveFocus()
      Keys.onEscapePressed: root.closeRequested()
      Keys.onTabPressed: area.forceActiveFocus()
      Keys.onBacktabPressed: goalField.forceActiveFocus()
      Keys.onPressed: function(event) { if (root.handleKey(event)) event.accepted = true }
    }
  }

  // Footer
  Item {
    id: footer
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: adviceButton.implicitHeight

    Text {
      id: statusText
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      readonly property string saveState: root.store ? String(root.store.saveState) : "saved"
      readonly property string saveLabel: saveState === "pending" ? "Saving…"
                                         : saveState === "error" ? "Save failed" : "Saved"
      text: root.locked ? "Locked while the AI reads your text"
                        : Model.wordCount(area.text) + " words · " + saveLabel
      color: saveState === "error" && !root.locked ? Color.urgent : root.faint
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }

    Button {
      id: adviceButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      bordered: true
      text: {
        if (root.hasAdvice && !root.adviceOpen)
          return root.adviceRunning ? "Show advice…" : "Show advice (" + root.openTips + " open)"
        return "Get advice"
      }
      enabled: root.adviceRunning ? (root.hasAdvice && !root.adviceOpen) : area.text.trim() !== ""
      opacity: enabled ? 1 : 0.5
      onClicked: {
        if (root.hasAdvice && !root.adviceOpen) root.showAdviceRequested()
        else root.adviceRequested()
      }
    }
  }

  // Writing area frame
  BorderSurface {
    id: frame
    opacity: root.locked ? 0.55 : 1
    Behavior on opacity { NumberAnimation { duration: 180 } }
    anchors.top: fieldsCol.bottom
    anchors.topMargin: Style.spacing.rowGap
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: footer.top
    anchors.bottomMargin: Style.spacing.rowGap

    readonly property bool _hot: frameHover.hovered
    readonly property var _spec: Border.controlSpec(area.activeFocus ? "focus" : (_hot ? "hover-cursor" : "normal"),
                                                    root.foreground, Color.accent)
    color: Style.controlFill(area.activeFocus, _hot, root.foreground, Color.accent)
    borderSpec: _spec
    radius: Style.cornerRadius

    HoverHandler { id: frameHover }

    Flickable {
      id: flick
      anchors.fill: parent
      anchors.margins: Style.normalBorderWidth
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      contentWidth: width
      contentHeight: area.height

      ScrollBar.vertical: ScrollBar {
        id: vbar
        policy: ScrollBar.AsNeeded
        background: null
        contentItem: Rectangle {
          implicitWidth: Style.space(4)
          radius: width / 2
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, vbar.pressed ? 0.5 : 0.28)
        }
      }

      TextArea.flickable: TextArea {
        id: area
        width: flick.width
        readOnly: root.locked
        height: Math.max(implicitHeight, flick.height)
        wrapMode: TextEdit.Wrap
        textFormat: TextEdit.PlainText
        selectByMouse: true
        placeholderText: "Start writing, or paste your draft…"
        placeholderTextColor: Qt.darker(root.foreground, 1.6)
        color: root.foreground
        selectionColor: Style.selectionFillFor(root.foreground, Color.accent)
        selectedTextColor: root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        leftPadding: Style.spacing.controlPaddingX
        rightPadding: Style.spacing.controlPaddingX
        topPadding: Style.spacing.inputPaddingY
        bottomPadding: Style.spacing.inputPaddingY

        // Highlights live in the background so they sit behind the text.
        background: Item {
          Repeater {
            model: root.hl
            delegate: Rectangle {
              required property var modelData
              x: modelData.x
              y: modelData.y
              width: modelData.w
              height: modelData.h
              radius: Style.cornerRadius / 2
              color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.30)
            }
          }
        }

        onTextChanged: {
          if (root.hl.length > 0) root.clearHighlight()
          if (!root._syncing && root.store) root.store.updateCurrent({ text: text })
        }
        onWidthChanged: root.clearHighlight()

        // Keep the caret visible while typing.
        onCursorRectangleChanged: {
          if (!activeFocus) return
          var r = cursorRectangle
          if (r.y < flick.contentY) flick.contentY = r.y
          else if (r.y + r.height > flick.contentY + flick.height)
            flick.contentY = r.y + r.height - flick.height
        }

        Keys.onEscapePressed: root.closeRequested()
        Keys.onTabPressed: goalField.forceActiveFocus()
        Keys.onBacktabPressed: toneField.forceActiveFocus()
        Keys.onPressed: function(event) { if (root.handleKey(event)) event.accepted = true }
      }
    }
  }
}
