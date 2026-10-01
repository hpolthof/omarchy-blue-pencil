import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Persistent state for Blue Pencil: drafts (history.json) and settings
// (settings.json). Several instances (one per monitor) share the files; they
// only ever write in response to a user action or an advice event, never as a
// consequence of loading.
Item {
  id: root
  visible: false

  // ---------------------------------------------------------------- public

  property bool loaded: false
  property var drafts: []
  property string currentId: ""
  property var current: Model.newDraft("d-0", 0)
  property var settings: Model.normalizeSettings(null)
  property string saveState: "saved"

  // ---------------------------------------------------------------- paths

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")) + "/omarchy/blue-pencil"
  readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")) + "/omarchy/blue-pencil"
  readonly property string historyPath: stateDir + "/history.json"
  readonly property string settingsPath: configDir + "/settings.json"

  // --------------------------------------------------------------- internals

  property bool _dirsReady: false
  property bool _historyLoaded: false
  property bool _settingsLoaded: false
  property bool _historyDirty: false
  property bool _settingsDirty: false
  property var _recentHistory: []   // texts this instance wrote recently (echo filter)
  property var _recentSettings: []
  readonly property bool _ready: _dirsReady && loaded

  function _now() { return Date.now() }

  function _remember(list, text) {
    var next = list.slice(-5)
    next.push(text)
    return next
  }

  // Replace `current` and rebuild `drafts` (persisted = non-empty only).
  function _setCurrent(d) {
    root.current = d
    root.currentId = d.id
    var out = []
    for (var i = 0; i < root.drafts.length; i++) if (root.drafts[i].id !== d.id) out.push(root.drafts[i])
    if (!Model.isEmptyDraft(d)) out.push(d)
    out.sort(function(a, b) { return b.updatedAt - a.updatedAt })
    root.drafts = out
  }

  // Apply fn to the draft with this id (current by default). Returns result or null.
  function _patchDraft(id, fn) {
    var target = id || root.currentId
    if (target === root.currentId) {
      var nc = fn(root.current)
      if (!nc) return null
      root._setCurrent(nc)
      return nc
    }
    var out = []
    var res = null
    for (var i = 0; i < root.drafts.length; i++) {
      if (root.drafts[i].id === target) {
        res = fn(root.drafts[i])
        out.push(res || root.drafts[i])
      } else {
        out.push(root.drafts[i])
      }
    }
    if (!res) return null
    out.sort(function(a, b) { return b.updatedAt - a.updatedAt })
    root.drafts = out
    return res
  }

  function _fresh() {
    var taken = []
    for (var i = 0; i < root.drafts.length; i++) taken.push(root.drafts[i].id)
    return Model.newDraft(Model.makeId(root._now(), taken), root._now())
  }

  function _markLoadedIfDone() {
    if (root._historyLoaded && root._settingsLoaded && !root.loaded) root.loaded = true
  }

  function _copy(o) { return Object.assign({}, o) }

  // ------------------------------------------------------------------ saving

  function _scheduleSave() {
    root.saveState = "pending"
    saveTimer.restart()
  }

  function _saveHistoryNow() {
    saveTimer.stop()
    if (!root._ready) {
      root._historyDirty = true
      root.saveState = "pending"
      return
    }
    root._historyDirty = false
    var text = Model.historyJson(root.currentId, root.drafts)
    root._recentHistory = root._remember(root._recentHistory, text)
    historyFile.setText(text)
  }

  function _saveSettingsNow() {
    if (!root._ready) {
      root._settingsDirty = true
      return
    }
    root._settingsDirty = false
    var text = JSON.stringify(root.settings, null, 2)
    root._recentSettings = root._remember(root._recentSettings, text)
    settingsFile.setText(text)
  }

  on_ReadyChanged: {
    if (!_ready) return
    if (_historyDirty) _saveHistoryNow()
    if (_settingsDirty) _saveSettingsNow()
  }

  function flush() {
    if (saveTimer.running || root._historyDirty) root._saveHistoryNow()
  }

  Timer {
    id: saveTimer
    interval: 800
    onTriggered: root._saveHistoryNow()
  }

  // ----------------------------------------------------------------- loading

  function _applyHistory(text) {
    var parsed = Model.parseJson(text, null)
    var norm = parsed ? Model.normalizeHistory(parsed, root._now()) : null
    if (!norm) {
      if (String(text || "").trim() !== "") console.warn("[blue-pencil] history.json is not usable; starting empty (file kept until the next change)")
      norm = { currentId: "", drafts: [] }
    }
    var pending = saveTimer.running || root._historyDirty
    var local = root.current
    if (pending) {
      // Unsaved local edits win for the current draft; adopt everything else.
      var merged = []
      for (var i = 0; i < norm.drafts.length; i++) if (norm.drafts[i].id !== local.id) merged.push(norm.drafts[i])
      root.drafts = merged
      root._setCurrent(local)
      return
    }
    root.drafts = norm.drafts
    var keepLocalEmpty = Model.isEmptyDraft(local) && root.loaded
    if (keepLocalEmpty) {
      root._setCurrent(local)
      return
    }
    var found = null
    for (var j = 0; j < norm.drafts.length; j++) if (norm.drafts[j].id === norm.currentId) found = norm.drafts[j]
    if (!found && norm.drafts.length > 0 && root.loaded) {
      // Keep the draft this instance is showing if it still exists.
      for (var k = 0; k < norm.drafts.length; k++) if (norm.drafts[k].id === root.currentId) found = norm.drafts[k]
    }
    root._setCurrent(found || root._fresh())
  }

  function _applySettings(text) {
    var parsed = Model.parseJson(text, null)
    if (!parsed && String(text || "").trim() !== "") console.warn("[blue-pencil] settings.json is not usable; using defaults (file kept until the next change)")
    var next = Model.normalizeSettings(parsed)
    if (JSON.stringify(next) !== JSON.stringify(root.settings)) root.settings = next
  }

  FileView {
    id: historyFile
    path: root.historyPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      var t = text()
      if (root._historyLoaded && root._recentHistory.indexOf(t) >= 0) return
      root._applyHistory(t)
      root._historyLoaded = true
      root._markLoadedIfDone()
    }
    onLoadFailed: function(error) {
      // Missing file: start empty. Never write because of this.
      if (!root._historyLoaded) {
        root._applyHistory("")
        root._historyLoaded = true
        root._markLoadedIfDone()
      }
    }
    onFileChanged: reload()
    onSaved: if (!saveTimer.running && !root._historyDirty) root.saveState = "saved"
    onSaveFailed: function(error) {
      console.warn("[blue-pencil] could not save history: " + error)
      root.saveState = "error"
    }
  }

  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      var t = text()
      if (root._settingsLoaded && root._recentSettings.indexOf(t) >= 0) return
      root._applySettings(t)
      root._settingsLoaded = true
      root._markLoadedIfDone()
    }
    onLoadFailed: function(error) {
      if (!root._settingsLoaded) {
        root._applySettings("")
        root._settingsLoaded = true
        root._markLoadedIfDone()
      }
    }
    onFileChanged: reload()
    onSaveFailed: function(error) { console.warn("[blue-pencil] could not save settings: " + error) }
  }

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", root.stateDir, root.configDir]
    running: true
    onRunningChanged: if (!running) root._dirsReady = true
  }

  Component.onCompleted: root._setCurrent(root._fresh())

  // ------------------------------------------------------------- operations

  function updateCurrent(patch) {
    var nc = root._copy(root.current)
    var keys = ["text", "goal", "tone", "adviceOpen"]
    for (var i = 0; i < keys.length; i++) {
      var k = keys[i]
      if (patch && patch[k] !== undefined) nc[k] = k === "adviceOpen" ? patch[k] === true : String(patch[k])
    }
    nc.updatedAt = root._now()
    root._setCurrent(nc)
    root._scheduleSave()
  }

  function newDraft() {
    root.flush()
    if (Model.isEmptyDraft(root.current) && !root.current.advice) return
    root._setCurrent(root._fresh())
    root._saveHistoryNow()
  }

  function openDraft(id) {
    root.flush()
    for (var i = 0; i < root.drafts.length; i++) {
      if (root.drafts[i].id === id) {
        root._setCurrent(root.drafts[i])
        root._saveHistoryNow()
        return
      }
    }
  }

  function deleteDraft(id) {
    var rest = []
    for (var i = 0; i < root.drafts.length; i++) if (root.drafts[i].id !== id) rest.push(root.drafts[i])
    root.drafts = rest
    if (id === root.currentId) root._setCurrent(rest.length > 0 ? rest[0] : root._fresh())
    root._saveHistoryNow()
  }

  function clearHistory() {
    root.drafts = []
    root._setCurrent(root._fresh())
    root._saveHistoryNow()
  }

  // draftId is optional (extension): defaults to the current draft.
  function beginAdvice(provider, model, draftId) {
    var r = root._patchDraft(draftId, function(d) {
      var nd = root._copy(d)
      nd.advice = { at: root._now(), provider: String(provider || ""), model: String(model || ""), tips: [] }
      nd.adviceOpen = true
      nd.updatedAt = root._now()
      return nd
    })
    if (r) root._saveHistoryNow()
  }

  // draftId is optional (extension): defaults to the current draft.
  function appendTip(tip, draftId) {
    var r = root._patchDraft(draftId, function(d) {
      var nd = root._copy(d)
      var adv = d.advice ? root._copy(d.advice) : { at: root._now(), provider: "", model: "", tips: [] }
      var tips = adv.tips.slice()
      tips.push({
        id: Model.nextTipId(tips),
        kind: Model.KIND_LABELS[tip.kind] ? tip.kind : "clarity",
        title: String(tip.title || ""),
        body: String(tip.body || ""),
        quote: String(tip.quote || ""),
        done: false
      })
      adv.tips = tips
      nd.advice = adv
      nd.updatedAt = root._now()
      return nd
    })
    if (r) root._saveHistoryNow()
  }

  function setTipDone(tipId, done) {
    var r = root._patchDraft("", function(d) {
      if (!d.advice) return null
      var nd = root._copy(d)
      var adv = root._copy(d.advice)
      adv.tips = d.advice.tips.map(function(t) {
        if (t.id !== tipId) return t
        var nt = root._copy(t)
        nt.done = done === true
        return nt
      })
      nd.advice = adv
      nd.updatedAt = root._now()
      return nd
    })
    if (r) root._saveHistoryNow()
  }

  function updateSettings(patch) {
    var next = root._copy(root.settings)
    for (var k in patch) next[k] = patch[k]
    root.settings = Model.normalizeSettings(next)
    root._saveSettingsNow()
  }
}
