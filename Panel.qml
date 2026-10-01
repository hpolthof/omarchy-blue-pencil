import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Blue Pencil panel. Compact (editor only) until advice is requested, then it
// grows to the right and shows the advice column. Passive mirror of the host:
// all state lives in host.store.
Panel {
  id: root
  moduleName: "io.github.hpolthof.blue-pencil"

  property Item anchorItem: null
  property var host: null
  readonly property var barIdentity: host || root

  // welcome | editor | history | settings
  property string view: "editor"
  // While true the initial view follows store.loaded / onboarded.
  property bool autoView: true

  readonly property var store: host && host.store ? host.store : null
  readonly property var current: store && store.current ? store.current : null
  readonly property var cfg: store && store.settings ? store.settings : ({})
  readonly property bool adviceOpen: current ? current.adviceOpen === true : false
  readonly property bool wide: view === "editor" && adviceOpen

  readonly property color foreground: bar ? bar.foreground : Color.foreground

  readonly property string metaLine: {
    var pid = cfg.provider ? String(cfg.provider) : ""
    if (pid === "") return "No AI set up"
    var name = pid.charAt(0).toUpperCase() + pid.slice(1)
    var model = cfg.model ? String(cfg.model) : ""
    var provs = cfg.scan && cfg.scan.providers ? cfg.scan.providers : []
    for (var i = 0; i < provs.length; i++) {
      if (provs[i].id !== pid) continue
      if (provs[i].name) name = String(provs[i].name)
      var ms = provs[i].models || []
      for (var j = 0; j < ms.length; j++)
        if (ms[j].id === model && ms[j].name) model = String(ms[j].name)
    }
    return model !== "" ? name + " · " + model : name
  }

  // ------------------------------------------------------------ actions

  function initialView() {
    return store && store.loaded && !cfg.onboarded ? "welcome" : "editor"
  }

  function setView(v) {
    root.autoView = false
    root.view = v
  }

  function restoreFocus() {
    if (!root.opened) return
    if (root.view === "editor") editorPane.focusInitial()
    else if (root.view === "history") historyView.takeFocus()
    else setupView.takeFocus()
  }

  function open() {
    root.autoView = true
    root.view = root.initialView()
    root.controller.show()
    Qt.callLater(root.restoreFocus)
  }

  function close() {
    root.controller.hide()
    if (root.store) root.store.flush()
    editorPane.clearHighlight()
  }

  function newText() {
    if (!root.store) return
    root.store.newDraft()
    root.setView("editor")
    Qt.callLater(root.restoreFocus)
  }

  function toggleHistory() { root.setView(root.view === "history" ? "editor" : "history") }
  function toggleSettings() { root.setView(root.view === "settings" ? "editor" : "settings") }

  function openSetup() { root.setView(root.cfg.onboarded ? "settings" : "welcome") }

  function getAdvice() {
    if (!root.host || !root.store) return
    if (!root.cfg.provider) { root.openSetup(); return }
    root.host.requestAdvice()
  }

  function showAdvice() {
    if (root.store) root.store.updateCurrent({ adviceOpen: true })
  }

  function hideAdvice() {
    editorPane.clearHighlight()
    if (root.store) root.store.updateCurrent({ adviceOpen: false })
  }

  onOpenedChanged: {
    if (root.opened) Qt.callLater(root.restoreFocus)
    else editorPane.clearHighlight()
  }
  onViewChanged: Qt.callLater(root.restoreFocus)

  Connections {
    target: root.store
    ignoreUnknownSignals: true
    function onLoadedChanged() {
      if (root.autoView && root.opened) root.view = root.initialView()
    }
  }

  // ---------------------------------------------------------------- popup

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened

    readonly property int compactWidth: panel.fittedContentWidth(Style.space(560))
    readonly property int wideWidth: panel.fittedContentWidth(Style.space(1040))

    focusTarget: root.view === "editor" ? editorPane.initialFocusItem
               : (root.view === "history" ? historyView : setupView)
    contentWidth: root.wide ? wideWidth : compactWidth
    // The editor needs room to write; the other views are as tall as their
    // content and grow (animated) when it does, e.g. after a scan.
    readonly property real chromeHeight: header.visible
      ? header.height + Style.spacing.rowGap + headerRule.height + Style.spacing.panelGap : 0
    readonly property real viewHeight: root.view === "history" ? historyView.implicitHeight
      : (root.view === "editor" ? Style.space(640) : setupView.implicitHeight)
    contentHeight: root.view === "editor"
      ? panel.fittedContentHeight(Style.space(640))
      : panel.fittedContentHeight(Math.min(chromeHeight + viewHeight, Style.space(640)))

    Behavior on contentHeight {
      NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    Behavior on contentWidth {
      NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    Item {
      id: keyRoot
      anchors.fill: parent

      // Ctrl combos reaching here come from the catcher or from views that
      // did not consume them; text inputs handle the same set themselves.
      Keys.onPressed: function(event) {
        if (!(event.modifiers & Qt.ControlModifier) || root.view === "welcome") return
        if (event.key === Qt.Key_N) { root.newText(); event.accepted = true }
        else if (event.key === Qt.Key_H) { root.toggleHistory(); event.accepted = true }
        else if (event.key === Qt.Key_Comma) { root.toggleSettings(); event.accepted = true }
        else if (root.view === "editor" && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
          root.getAdvice(); event.accepted = true
        }
      }

      PanelKeyCatcher {
        id: keyCatcher
        anchors.fill: parent
        blocked: root.view !== "editor" || editorPane.typing
        onCloseRequested: root.close()
        onMoveRequested: function(dx, dy) { if (dy !== 0 && root.wide) advicePane.scrollBy(dy) }
        onTabRequested: function(direction) { editorPane.focusInitial() }
      }

      // ── Header ──────────────────────────────────────────────────────────
      PanelHero {
        id: header
        visible: root.view !== "welcome"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        title: "Blue Pencil"
        meta: root.metaLine
        foreground: root.foreground
        iconComponent: Component {
          QuillIcon {
            size: Style.font.display
            color: Color.accent
          }
        }
        trailingControl: Component {
          Row {
            spacing: Style.spacing.xs
            PanelActionButton {
              iconText: Model.GLYPH.plus
              tooltipText: "New text"
              foreground: root.foreground
              onClicked: root.newText()
            }
            PanelActionButton {
              iconText: Model.GLYPH.history
              tooltipText: "History"
              foreground: root.foreground
              onClicked: root.toggleHistory()
            }
            PanelActionButton {
              iconText: Model.GLYPH.settings
              tooltipText: "Settings"
              foreground: root.foreground
              onClicked: root.toggleSettings()
            }
          }
        }
      }

      PanelSeparator {
        id: headerRule
        visible: header.visible
        anchors.top: header.bottom
        anchors.topMargin: Style.spacing.rowGap
        foreground: root.foreground
      }

      // ── Body ────────────────────────────────────────────────────────────
      Item {
        id: body
        anchors.top: header.visible ? headerRule.bottom : parent.top
        anchors.topMargin: header.visible ? Style.spacing.panelGap : 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true

        // The editor keeps the compact width no matter how wide the panel is.
        readonly property real inset: panel.contentWidth - keyRoot.width
        readonly property real editorWidth: Math.max(Style.space(200), panel.compactWidth - inset)
        readonly property real columnGap: Style.spacing.panelGap * 2
        readonly property real adviceWidth: Math.max(0, panel.wideWidth - inset - editorWidth - columnGap)

        EditorPane {
          id: editorPane
          visible: root.view === "editor"
          x: 0
          width: body.editorWidth
          height: parent.height
          host: root.host
          foreground: root.foreground
          onCloseRequested: root.close()
          onAdviceRequested: root.getAdvice()
          onShowAdviceRequested: root.showAdvice()
          onNewRequested: root.newText()
          onHistoryRequested: root.toggleHistory()
          onSettingsRequested: root.toggleSettings()
        }

        // Divider + advice column; stay mounted during the shrink animation.
        readonly property bool adviceShown: root.view === "editor" && (root.adviceOpen || panel.contentWidth > panel.compactWidth + 1)

        PanelSeparator {
          visible: body.adviceShown
          x: body.editorWidth + body.columnGap / 2
          width: 1
          height: parent.height
          foreground: root.foreground
          strength: 0.12
        }

        AdvicePane {
          id: advicePane
          visible: body.adviceShown
          x: body.editorWidth + body.columnGap
          width: body.adviceWidth
          height: parent.height
          host: root.host
          foreground: root.foreground
          opacity: root.adviceOpen ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 140 } }
          onCloseRequested: root.hideAdvice()
          onAskAgainRequested: root.getAdvice()
          onOpenSettingsRequested: root.openSetup()
          onQuoteHovered: function(quote) { editorPane.highlightQuote(quote) }
          onQuoteUnhovered: editorPane.clearHighlight()
        }

        HistoryView {
          id: historyView
          visible: root.view === "history"
          anchors.fill: parent
          host: root.host
          onBack: root.setView("editor")
        }

        SetupView {
          id: setupView
          visible: root.view === "welcome" || root.view === "settings"
          anchors.fill: parent
          host: root.host
          mode: root.view === "welcome" ? "welcome" : "settings"
          onBack: root.setView("editor")
        }
      }
    }
  }
}
