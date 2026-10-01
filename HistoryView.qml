import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// History of persisted drafts. Handles its own keys (Panel blocks its catcher).
Item {
  id: root

  property QtObject host: null
  signal back()

  function takeFocus() { root.forceActiveFocus() }

  readonly property var drafts: (host && host.store && host.store.drafts) ? host.store.drafts : []
  readonly property string currentId: (host && host.store && host.store.currentId) ? host.store.currentId : ""
  readonly property color foreground: Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color faint: Qt.darker(foreground, 1.85)

  property int cursor: 0
  property string confirmId: ""
  property double now: Date.now()

  implicitHeight: Math.min(header.height + sep.height + listColumn.height, Style.space(640))
  focus: true
  activeFocusOnTab: false

  onDraftsChanged: {
    if (cursor >= drafts.length) cursor = Math.max(0, drafts.length - 1)
    if (confirmId !== "" && !_has(confirmId)) confirmId = ""
  }
  onVisibleChanged: if (visible) { now = Date.now(); cursor = 0; confirmId = ""; Qt.callLater(takeFocus) }

  function _has(id) {
    for (var i = 0; i < drafts.length; i++) if (drafts[i].id === id) return true
    return false
  }

  function _open(i) {
    if (i < 0 || i >= drafts.length || !host || !host.store) return
    host.store.openDraft(drafts[i].id)
    root.back()
  }

  function _confirmDelete() {
    if (confirmId !== "" && host && host.store) host.store.deleteDraft(confirmId)
    confirmId = ""
  }

  function _move(delta) {
    if (drafts.length === 0) return
    cursor = Math.max(0, Math.min(drafts.length - 1, cursor + delta))
    confirmId = ""
    Qt.callLater(_ensureVisible)
  }

  function _ensureVisible() {
    var it = rows.itemAt(cursor)
    if (!it) return
    var top = it.y
    var bottom = it.y + it.height
    if (top < flick.contentY) flick.contentY = top
    else if (bottom > flick.contentY + flick.height) flick.contentY = bottom - flick.height
  }

  Timer {
    interval: 30000
    repeat: true
    running: root.visible
    onTriggered: root.now = Date.now()
  }

  Keys.onPressed: function(event) {
    if (confirmAll.opened) {
      if (confirmAll.handleKey(event)) event.accepted = true
      return
    }
    var k = event.key
    var t = event.text
    if (root.confirmId !== "") {
      if (k === Qt.Key_Return || k === Qt.Key_Enter || t === "y") root._confirmDelete()
      else if (k === Qt.Key_Escape || t === "n") root.confirmId = ""
      event.accepted = true
      return
    }
    if (k === Qt.Key_Escape) root.back()
    else if (k === Qt.Key_Down || t === "j") root._move(1)
    else if (k === Qt.Key_Up || t === "k") root._move(-1)
    else if (k === Qt.Key_Return || k === Qt.Key_Enter) root._open(root.cursor)
    else if (k === Qt.Key_Delete || t === "x") {
      if (root.cursor < root.drafts.length) root.confirmId = root.drafts[root.cursor].id
    } else return
    event.accepted = true
  }

  // ------------------------------------------------------------ header
  Item {
    id: header
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: Style.spacing.controlHeight + Style.spacing.rowGap * 2

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
        text: "History"
        color: root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Button {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: "Clear all"
      iconText: Model.GLYPH.trash
      bordered: true
      enabled: root.drafts.length > 0
      opacity: enabled ? 1 : 0.4
      onClicked: confirmAll.opened = true
    }
  }

  PanelSeparator {
    id: sep
    anchors.top: header.bottom
    foreground: root.foreground
  }

  // ------------------------------------------------------------ empty
  Text {
    visible: root.drafts.length === 0
    anchors.top: sep.bottom
    anchors.topMargin: Style.spacing.panelGap * 2
    anchors.left: parent.left
    anchors.right: parent.right
    horizontalAlignment: Text.AlignHCenter
    textFormat: Text.PlainText
    text: "No texts yet."
    color: root.dim
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  // ------------------------------------------------------------ list
  Flickable {
    id: flick
    anchors.top: sep.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    contentHeight: listColumn.height
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: listColumn
      width: flick.width
      spacing: Style.spacing.xs

      Repeater {
        id: rows
        model: root.drafts

        delegate: Rectangle {
          id: row
          required property var modelData
          required property int index

          readonly property bool isCursor: root.cursor === index
          readonly property bool isCurrent: modelData.id === root.currentId
          readonly property bool confirming: root.confirmId === modelData.id
          readonly property var stats: Model.tipStats(modelData)

          width: listColumn.width
          height: textCol.implicitHeight + Style.spacing.rowGap * 2
          radius: Style.cornerRadius
          color: confirming ? Util.alpha(Color.urgent, 0.12)
               : (isCursor || rowMouse.containsMouse) ? Style.hoverFillFor(root.foreground, Color.accent)
               : "transparent"

          MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.cursor = row.index
            onClicked: root._open(row.index)
          }

          Column {
            id: textCol
            anchors.left: parent.left
            anchors.right: actions.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.spacing.controlPaddingX
            anchors.rightMargin: Style.spacing.controlGap
            spacing: Style.spacing.xs

            Row {
              width: parent.width
              spacing: Style.spacing.controlGap
              Text {
                textFormat: Text.PlainText
                width: Math.min(implicitWidth, parent.width - (row.isCurrent ? currentTag.width + parent.spacing : 0))
                text: Model.draftTitle(row.modelData)
                color: row.isCursor ? Color.accent : root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
                elide: Text.ElideRight
              }
              Text {
                id: currentTag
                visible: row.isCurrent
                textFormat: Text.PlainText
                text: "● current"
                color: Color.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: {
                var w = Model.wordCount(row.modelData.text || "") + " words"
                var hasGoal = String(row.modelData.goal || "").trim() !== ""
                var snip = hasGoal ? Model.draftSnippet(row.modelData) : ""
                return snip !== "" ? w + " · " + snip : w
              }
              color: root.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: Model.relativeTime(row.modelData.updatedAt, root.now) + " · "
                    + (row.stats.total > 0 ? row.stats.done + " of " + row.stats.total + " tips done" : "No advice yet")
              color: root.faint
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
          }

          Item {
            id: actions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: Style.spacing.controlPaddingX
            width: row.confirming ? confirmRow.width : trashBtn.width
            height: Style.space(26)

            PanelActionButton {
              id: trashBtn
              visible: !row.confirming
              anchors.verticalCenter: parent.verticalCenter
              iconText: Model.GLYPH.trash
              foreground: root.foreground
              hoverColor: Color.urgent
              tooltipText: "Delete (x)"
              onClicked: { root.cursor = row.index; root.confirmId = row.modelData.id }
            }

            Row {
              id: confirmRow
              visible: row.confirming
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.controlGap
              Text {
                textFormat: Text.PlainText
                text: "Delete?"
                color: Color.urgent
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                anchors.verticalCenter: parent.verticalCenter
              }
              Button {
                text: "Yes"
                bordered: true
                fontSize: Style.font.bodySmall
                verticalPadding: Style.spacing.xs
                onClicked: root._confirmDelete()
              }
              Button {
                text: "No"
                bordered: true
                fontSize: Style.font.bodySmall
                verticalPadding: Style.spacing.xs
                onClicked: root.confirmId = ""
              }
            }
          }
        }
      }
    }
  }

  ConfirmDialog {
    id: confirmAll
    anchors.fill: parent
    z: 10
    message: "Delete all texts? This cannot be undone."
    cancelText: "Cancel"
    confirmText: "Delete all"
    onCanceled: { opened = false; root.takeFocus() }
    onConfirmed: {
      opened = false
      if (root.host && root.host.store) root.host.store.clearHistory()
      root.takeFocus()
    }
    onOpenedChanged: if (opened) selectedIndex = 0
  }
}
