import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// First-run welcome and the settings page. Handles its own keys.
Item {
  id: root

  property QtObject host: null
  property string mode: "welcome"   // "welcome" | "settings"
  signal back()

  function takeFocus() { root.forceActiveFocus() }

  readonly property bool isWelcome: mode === "welcome"
  readonly property var settings: (host && host.store && host.store.settings) ? host.store.settings : ({})
  readonly property var scan: settings.scan ? settings.scan : ({})
  readonly property var providers: scan.providers ? scan.providers : []
  readonly property string providerId: settings.provider ? String(settings.provider) : ""
  readonly property string modelId: settings.model ? String(settings.model) : ""
  readonly property int maxTips: settings.maxTips ? settings.maxTips : 6
  readonly property bool scanning: host ? !!host.scanRunning : false
  readonly property string scanError: (host && host.scanError) ? String(host.scanError) : ""
  readonly property color foreground: Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color faint: Qt.darker(foreground, 1.85)

  function usable(p) { return !!(p && p.installed && p.signedIn) }

  readonly property var selectedProvider: {
    for (var i = 0; i < providers.length; i++)
      if (providers[i].id === providerId) return providers[i]
    return null
  }
  readonly property bool canStart: usable(selectedProvider)
  readonly property var modelOptions: {
    var out = []
    var ms = selectedProvider && selectedProvider.models ? selectedProvider.models : []
    for (var i = 0; i < ms.length; i++)
      out.push({ value: String(ms[i].id), label: String(ms[i].name || ms[i].id) })
    return out
  }

  // Keyboard stops, in visual order.
  readonly property var stops: {
    var s = []
    for (var i = 0; i < providers.length; i++) s.push("p" + i)
    if (providers.length > 0) {
      s.push("model")
      s.push("tips")
    }
    s.push("scan")
    if (isWelcome) {
      s.push("start")
      s.push("skip")
    }
    return s
  }
  property int cursor: 0
  readonly property string cursorKey: stops[Math.min(cursor, stops.length - 1)]

  onStopsChanged: if (cursor >= stops.length) cursor = Math.max(0, stops.length - 1)
  onVisibleChanged: if (visible) { cursor = _initialCursor(); Qt.callLater(takeFocus) }
  onProvidersChanged: cursor = _initialCursor()
  onProviderIdChanged: cursor = _initialCursor()

  // Start where the user's choice is, so the cursor highlight and the
  // selection agree; before any scan that is the scan button.
  function _initialCursor() {
    // Also runs while the view is still being built, before stops exist.
    var st = Array.isArray(stops) ? stops : []
    var pv = Array.isArray(providers) ? providers : []
    for (var i = 0; i < pv.length; i++) {
      if (pv[i] && pv[i].id === providerId) {
        var at = st.indexOf("p" + i)
        if (at >= 0) return at
      }
    }
    var scan = st.indexOf("scan")
    return scan >= 0 ? scan : 0
  }

  implicitHeight: Math.min((isWelcome ? 0 : header.height + sep.height) + content.height, Style.space(640))
  focus: true

  function _finish() {
    if (host && host.store) host.store.updateSettings({ onboarded: true })
    root.back()
  }

  function _select(i) {
    var p = providers[i]
    if (!usable(p) || !host || !host.store) return
    host.store.updateSettings({ provider: p.id, model: String(p.defaultModel || "") })
  }

  function _setTips(n) {
    n = Math.max(3, Math.min(10, n))
    if (host && host.store && n !== maxTips) host.store.updateSettings({ maxTips: n })
  }

  function _scan() { if (host && !scanning) host.runScan() }

  function _activate(key) {
    if (key.charAt(0) === "p") _select(parseInt(key.substring(1)))
    else if (key === "model") { if (modelOptions.length > 0) modelDd.open() }
    else if (key === "tips") _setTips(maxTips + 1)
    else if (key === "scan") _scan()
    else if (key === "start") { if (canStart) _finish() }
    else if (key === "skip") _finish()
  }

  function _move(d) {
    cursor = Math.max(0, Math.min(stops.length - 1, cursor + d))
    Qt.callLater(_ensureVisible)
  }

  function _itemFor(key) {
    if (key.charAt(0) === "p") return provRep.itemAt(parseInt(key.substring(1)))
    if (key === "model") return modelBox
    if (key === "tips") return tipsBox
    if (key === "scan") return scanBtn
    if (key === "start") return startBtn
    if (key === "skip") return skipBtn
    return null
  }

  function _ensureVisible() {
    var it = _itemFor(cursorKey)
    if (!it) return
    var y = it.mapToItem(content, 0, 0).y
    var h = it.height
    if (y < flick.contentY) flick.contentY = Math.max(0, y - Style.spacing.rowGap)
    else if (y + h > flick.contentY + flick.height) flick.contentY = y + h - flick.height + Style.spacing.rowGap
  }

  Keys.onPressed: function(event) {
    var k = event.key
    var t = event.text
    if (k === Qt.Key_Escape) root.back()
    else if (k === Qt.Key_Down || k === Qt.Key_Tab || t === "j") root._move(1)
    else if (k === Qt.Key_Up || k === Qt.Key_Backtab || t === "k") root._move(-1)
    else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) root._activate(root.cursorKey)
    else if (root.cursorKey === "tips" && (k === Qt.Key_Left || t === "h" || t === "-")) root._setTips(root.maxTips - 1)
    else if (root.cursorKey === "tips" && (k === Qt.Key_Right || t === "l" || t === "+")) root._setTips(root.maxTips + 1)
    else return
    event.accepted = true
  }

  // Return keyboard focus after the dropdown popup closes.
  Connections {
    target: modelDd
    function onPopupOpenChanged() { if (!modelDd.popupOpen) Qt.callLater(root.takeFocus) }
  }

  // ------------------------------------------------------------ header (settings)
  Item {
    id: header
    visible: !root.isWelcome
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: root.isWelcome ? 0 : Style.spacing.controlHeight + Style.spacing.rowGap * 2

    Row {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.controlGap
      PanelActionButton {
        iconText: Model.GLYPH.back
        tooltipText: "Back"
        foreground: root.foreground
        anchors.verticalCenter: parent.verticalCenter
        onClicked: root.back()
      }
      Text {
        textFormat: Text.PlainText
        text: "Settings"
        color: root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }

  PanelSeparator {
    id: sep
    visible: !root.isWelcome
    anchors.top: header.bottom
    foreground: root.foreground
  }

  // ------------------------------------------------------------ content
  Flickable {
    id: flick
    anchors.top: root.isWelcome ? parent.top : sep.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    contentHeight: content.height
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: content
      width: flick.width
      topPadding: Style.spacing.panelGap
      bottomPadding: Style.spacing.panelGap
      spacing: Style.spacing.panelGap

      // Welcome copy
      Column {
        visible: root.isWelcome
        width: parent.width
        spacing: Style.spacing.rowGap
        PanelHero {
          width: parent.width
          title: "Welcome to Blue Pencil"
          meta: "Keep your voice. Skip the slop."
          foreground: root.foreground
          iconComponent: Component {
            QuillIcon {
              size: Style.font.display
              color: Color.accent
            }
          }
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          lineHeight: 1.15
          text: "You can spot AI-written text from a mile away. It is smooth, polite and interchangeable, and it sounds like nobody in particular."
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          lineHeight: 1.15
          text: "Blue Pencil works the other way round. You write. When you want a second pair of eyes, the AI reads along like an old-fashioned editor with a blue pencil: it marks what is unclear, what could be built better, and what is so typically you that it should stay. It never writes a sentence for you, so whatever you send out still sounds like the person who wrote it."
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: "To give advice it uses an AI command-line tool that is already on this computer. A scan checks whether Claude Code or Codex is installed and signed in. Nothing you write is sent during the scan."
          color: root.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }

      // Providers
      Column {
        visible: root.providers.length > 0
        width: parent.width
        spacing: Style.spacing.xs

        PanelSectionHeader { text: "AI TOOL"; foreground: root.foreground }

        Repeater {
          id: provRep
          model: root.providers

          delegate: Rectangle {
            id: prow
            required property var modelData
            required property int index
            readonly property bool ok: root.usable(modelData)
            readonly property bool selected: ok && modelData.id === root.providerId
            readonly property bool hasCursor: root.cursorKey === "p" + index

            width: parent.width
            height: Style.spacing.controlHeight + Style.spacing.rowGap
            radius: Style.cornerRadius
            color: (hasCursor || pMouse.containsMouse && ok) ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"

            MouseArea {
              id: pMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: prow.ok ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: { root.cursor = root.stops.indexOf("p" + prow.index); root._select(prow.index); root.takeFocus() }
            }

            Row {
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.controlPaddingX
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.controlGap

              // radio indicator
              Text {
                textFormat: Text.PlainText
                text: prow.selected ? "◉" : (prow.ok ? "○" : "·")
                color: prow.selected ? Color.accent : (prow.ok ? root.foreground : root.faint)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                textFormat: Text.PlainText
                text: prow.ok ? "✓" : "–"
                color: prow.ok ? Color.accent : root.dim
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                textFormat: Text.PlainText
                text: String(prow.modelData.name || prow.modelData.id)
                color: prow.ok ? root.foreground : root.dim
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: prow.selected
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                textFormat: Text.PlainText
                text: {
                  var d = prow.modelData
                  if (!d.installed) return "Not installed"
                  if (!d.signedIn) return "Not signed in"
                  return "Signed in"
                }
                color: root.dim
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                anchors.verticalCenter: parent.verticalCenter
              }
            }
            Text {
              visible: String(prow.modelData.error || "") !== ""
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.controlPaddingX
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, parent.width * 0.4)
              textFormat: Text.PlainText
              text: String(prow.modelData.error || "")
              color: Color.urgent
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }
      }

      // Model
      Item {
        id: modelBox
        visible: root.providers.length > 0
        width: parent.width
        height: modelDd.implicitHeight

        Dropdown {
          id: modelDd
          width: parent.width
          label: "Model"
          options: root.modelOptions
          hasCursor: root.cursorKey === "model"
          onChanged: function(v) {
            if (root.host && root.host.store) root.host.store.updateSettings({ model: v })
          }
          onHovered: function(on) { if (on) root.cursor = root.stops.indexOf("model") }
        }
        Binding { target: modelDd; property: "value"; value: root.modelId }
      }

      // Max tips
      Item {
        id: tipsBox
        visible: root.providers.length > 0
        width: parent.width
        height: Style.spacing.controlHeight + Style.spacing.rowGap

        Rectangle {
          anchors.fill: parent
          radius: Style.cornerRadius
          color: root.cursorKey === "tips" ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
        }
        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.controlPaddingX
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "Max tips"
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
        Row {
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.controlPaddingX
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.controlGap
          PanelActionButton {
            iconText: "−"
            enabled: root.maxTips > 3
            foreground: root.foreground
            tooltipText: "Fewer tips"
            anchors.verticalCenter: parent.verticalCenter
            onClicked: { root.cursor = root.stops.indexOf("tips"); root._setTips(root.maxTips - 1) }
          }
          Text {
            width: Style.space(28)
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: String(root.maxTips)
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
          }
          PanelActionButton {
            iconText: "+"
            enabled: root.maxTips < 10
            foreground: root.foreground
            tooltipText: "More tips"
            anchors.verticalCenter: parent.verticalCenter
            onClicked: { root.cursor = root.stops.indexOf("tips"); root._setTips(root.maxTips + 1) }
          }
        }
      }

      // Scan
      Column {
        width: parent.width
        spacing: Style.spacing.xs

        Row {
          spacing: Style.spacing.controlGap
          Button {
            id: scanBtn
            text: root.scanning ? "Scanning…" : (root.providers.length === 0 ? "Scan for AI tools" : "Rescan")
            iconText: Model.GLYPH.refresh
            iconSpinning: root.scanning
            bordered: true
            enabled: !root.scanning
            opacity: enabled ? 1 : 0.6
            hasCursor: root.cursorKey === "scan"
            onClicked: { root.cursor = root.stops.indexOf("scan"); root._scan(); root.takeFocus() }
          }
          Text {
            visible: !root.isWelcome && Number(root.scan.at || 0) > 0
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Last scan: " + Model.relativeTime(root.scan.at, Date.now())
            color: root.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }
        Text {
          visible: root.scanError !== ""
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: root.scanError
          color: Color.urgent
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }

      // Welcome actions
      Row {
        visible: root.isWelcome
        spacing: Style.spacing.controlGap
        Button {
          id: startBtn
          text: "Start writing"
          bordered: true
          enabled: root.canStart
          opacity: enabled ? 1 : 0.4
          hasCursor: root.cursorKey === "start"
          onClicked: { root.cursor = root.stops.indexOf("start"); root._finish() }
        }
        Button {
          id: skipBtn
          text: "Skip"
          hasCursor: root.cursorKey === "skip"
          onClicked: root._finish()
        }
      }

      // Settings note
      Text {
        visible: !root.isWelcome
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "Advice runs headless through the CLI without tools. Your text is sent to the provider you choose only when you press Get advice."
        color: root.faint
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
  }
}
