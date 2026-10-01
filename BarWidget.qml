import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Host: owns the Store, the advice/scan processes and the panel. Panel.qml
// binds directly to the properties below.
BarWidget {
  id: root
  moduleName: "io.github.hpolthof.blue-pencil"

  readonly property string binPath: String(Qt.resolvedUrl("bin/blue-pencil")).replace(/^file:\/\//, "")

  property alias store: bpStore

  // ---- advice state (read-only for the UI)
  property bool adviceRunning: false
  property string advicePhase: ""
  property string adviceMessage: ""
  property double adviceStartedAt: 0
  property string adviceError: ""
  property string adviceErrorCode: ""
  // The draft the running request belongs to; the editor locks that draft.
  readonly property string adviceDraftId: root.adviceRunning ? root._adviceDraftId : ""

  // ---- scan state
  property bool scanRunning: false
  property string scanError: ""

  // internals
  property string _adviceDraftId: ""
  property bool _adviceTerminal: false
  property bool _adviceCancelled: false
  property string _advicePayload: ""

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  Store { id: bpStore }

  // Errors belong to the draft they were raised for; switching texts clears them.
  Connections {
    target: bpStore
    function onCurrentIdChanged() {
      if (root.adviceRunning) return
      root.adviceError = ""
      root.adviceErrorCode = ""
    }
  }

  // ---------------------------------------------------------------- panel

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("anchorItem" in target) target.anchorItem = button
    if ("host" in target) target.host = root
    if ("bar" in target) target.bar = root.bar
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (root.opened) root.close(); else root.open() }

  onBarChanged: root.injectPanel()

  // ---------------------------------------------------------------- advice

  function _failAdvice(code, message) {
    root.adviceErrorCode = code
    root.adviceError = message
    root.advicePhase = ""
    root.adviceMessage = ""
  }

  function requestAdvice() {
    if (root.adviceRunning) return
    var s = bpStore.settings
    if (!s.provider) return
    var cur = bpStore.current
    root.adviceError = ""
    root.adviceErrorCode = ""
    if (String(cur.text).trim() === "") {
      bpStore.updateCurrent({ adviceOpen: true })
      root._failAdvice("empty-text", "Write something first, then ask for advice.")
      return
    }
    root._adviceDraftId = cur.id
    root._adviceTerminal = false
    root._adviceCancelled = false
    root._advicePayload = JSON.stringify({
      provider: s.provider,
      model: s.model,
      text: cur.text,
      goal: cur.goal,
      tone: cur.tone,
      maxTips: s.maxTips
    })
    bpStore.beginAdvice(s.provider, s.model, cur.id)
    root.advicePhase = "starting"
    root.adviceMessage = "Starting…"
    root.adviceStartedAt = Date.now()
    root.adviceRunning = true
    adviceProc.stdinEnabled = true
    adviceProc.command = [root.binPath, "advise"]
    adviceProc.running = true
  }

  function cancelAdvice() {
    if (!root.adviceRunning) return
    root._adviceCancelled = true
    if (adviceProc.running) adviceProc.signal(15)
    else root._finishAdvice()
  }

  function _finishAdvice() {
    if (!root.adviceRunning) return
    root.adviceRunning = false
    root.advicePhase = ""
    root.adviceMessage = ""
    if (!root._adviceTerminal && !root._adviceCancelled)
      root._failAdvice("failed", "Advice stopped unexpectedly.")
  }

  function _onAdviceLine(line) {
    if (root._adviceCancelled) return
    var ev = Model.parseJson(line, null)
    if (!ev || typeof ev !== "object") return
    if (ev.type === "status") {
      if (typeof ev.phase === "string") root.advicePhase = ev.phase
      if (typeof ev.message === "string") root.adviceMessage = ev.message
    } else if (ev.type === "tip") {
      if (ev.tip && typeof ev.tip === "object") bpStore.appendTip(ev.tip, root._adviceDraftId)
    } else if (ev.type === "done") {
      root._adviceTerminal = true
    } else if (ev.type === "error") {
      root._adviceTerminal = true
      root._failAdvice(String(ev.code || "failed"), String(ev.message || "Advice failed."))
    }
  }

  Process {
    id: adviceProc
    stdinEnabled: true
    stdout: SplitParser { onRead: function(line) { root._onAdviceLine(line) } }
    onStarted: {
      write(root._advicePayload + "\n")
      // Closing the write channel sends EOF; the backend reads one object.
      stdinEnabled = false
    }
    onRunningChanged: if (!running) root._finishAdvice()
  }

  // ------------------------------------------------------------------ scan

  function runScan() {
    if (root.scanRunning) return
    root.scanError = ""
    root.scanRunning = true
    scanProc.exitSeen = false
    scanProc.outSeen = false
    scanProc.outText = ""
    scanProc.command = [root.binPath, "scan"]
    scanProc.running = true
  }

  function _finishScan(code) {
    root.scanRunning = false
    var result = code === 0 ? Model.parseJson(scanProc.outText, null) : null
    if (!result || !Array.isArray(result.providers)) {
      root.scanError = code === 0 ? "The scan returned something unexpected." : "The scan failed."
      return
    }
    bpStore.updateSettings({ scan: { at: Date.now(), providers: result.providers } })
    var patch = Model.pickProvider(bpStore.settings, result.providers)
    if (Object.keys(patch).length > 0) bpStore.updateSettings(patch)
  }

  Process {
    id: scanProc
    property string outText: ""
    property bool exitSeen: false
    property bool outSeen: false
    property int exitCode: -1
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        scanProc.outText = text
        scanProc.outSeen = true
        if (scanProc.exitSeen) root._finishScan(scanProc.exitCode)
      }
    }
    onExited: function(code) {
      exitSeen = true
      exitCode = code
      if (outSeen) root._finishScan(code)
    }
  }

  // ---------------------------------------------------------------- lifecycle

  Component.onDestruction: bpStore.flush()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  IpcHandler {
    target: "io.github.hpolthof.blue-pencil"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    hasVisualContent: true
    fixedWidth: vertical ? -1 : quill.size + scaledHorizontalMargin * 2
    fixedHeight: vertical ? quill.size + scaledVerticalPadding * 2 : -1

    QuillIcon {
      id: quill
      anchors.centerIn: parent
      size: Math.round(Style.font.icon * 1.1)
      color: button.foreground
      strokeWidth: 2.1
      opacity: root.adviceRunning ? 0.55 : 1
      Behavior on opacity { NumberAnimation { duration: 400 } }
    }
    tooltipText: root.adviceRunning ? "Blue Pencil · thinking…" : "Blue Pencil"
    onPressed: function(mouseButton) { root.toggle() }
  }
}
