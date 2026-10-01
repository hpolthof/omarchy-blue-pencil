.pragma library

// Pure helpers for Blue Pencil. No QML types, no side effects.

var GLYPH = {
  pencil:   "󰏫",
  history:  "󰋚",
  plus:     "󰐕",
  settings: "󰒓",
  back:     "󰁍",
  close:    "󰅖",
  trash:    "󰆴",
  check:    "󰄬",
  refresh:  "󰑐"
}

var KIND_LABELS = {
  structure: "Structure",
  clarity: "Clarity",
  pitfall: "Pitfall",
  tone: "Tone",
  keep: "Keep"
}

var DEFAULT_SETTINGS = {
  version: 1,
  onboarded: false,
  provider: "",
  model: "",
  maxTips: 6,
  scan: { at: 0, providers: [] }
}

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

function _str(v) { return typeof v === "string" ? v : "" }
function _num(v, d) { return typeof v === "number" && isFinite(v) ? v : d }

function _clip(t, n) {
  return t.length > n ? t.substring(0, n - 1).replace(/\s+$/, "") + "…" : t
}

// A line like "Hi Jan," or "Dear neighbours," says nothing about the text.
function _isSalutation(line) {
  return /,$/.test(line) && line.split(/\s+/).length <= 4
}

// The first line of the text worth showing: skips blank lines and greetings.
function draftSnippet(draft) {
  if (!draft) return ""
  var lines = _str(draft.text).split("\n")
  var first = ""
  for (var i = 0; i < lines.length; i++) {
    var t = lines[i].replace(/\s+/g, " ").trim()
    if (t === "") continue
    if (first === "") first = t
    if (!_isSalutation(t)) return _clip(t, 120)
  }
  return _clip(first, 120)
}

// The goal says what a text is for, so it makes the best title; texts
// without one fall back to their first meaningful line.
function draftTitle(draft) {
  if (!draft) return "Untitled"
  var g = _str(draft.goal).replace(/\s+/g, " ").trim()
  if (g !== "") return _clip(g, 70)
  var t = draftSnippet(draft)
  return t !== "" ? _clip(t, 70) : "Untitled"
}

function wordCount(text) {
  var t = _str(text).trim()
  if (t === "") return 0
  return t.split(/\s+/).length
}

function _pad(n) { return n < 10 ? "0" + n : "" + n }
function _hhmm(d) { return _pad(d.getHours()) + ":" + _pad(d.getMinutes()) }

function relativeTime(ms, nowMs) {
  var now = nowMs === undefined || nowMs === null ? Date.now() : nowMs
  var diff = now - ms
  if (!isFinite(diff) || diff < 60000) return "Just now"
  if (diff < 3600000) return Math.floor(diff / 60000) + " min ago"
  var d = new Date(ms)
  var n = new Date(now)
  var startToday = new Date(n.getFullYear(), n.getMonth(), n.getDate()).getTime()
  if (ms >= startToday) return "Today " + _hhmm(d)
  var startYesterday = new Date(n.getFullYear(), n.getMonth(), n.getDate() - 1).getTime()
  if (ms >= startYesterday) return "Yesterday " + _hhmm(d)
  var s = d.getDate() + " " + MONTHS[d.getMonth()]
  if (d.getFullYear() !== n.getFullYear()) s += " " + d.getFullYear()
  return s
}

function tipStats(draft) {
  var tips = draft && draft.advice && draft.advice.tips ? draft.advice.tips : []
  var done = 0
  for (var i = 0; i < tips.length; i++) if (tips[i].done) done++
  return { total: tips.length, done: done, open: tips.length - done }
}

// ------------------------------------------------------------ store helpers

function isEmptyDraft(draft) {
  return !draft || (_str(draft.text) === "" && _str(draft.goal) === "" && _str(draft.tone) === "")
}

function newDraft(id, now) {
  return { id: id, createdAt: now, updatedAt: now, text: "", goal: "", tone: "", adviceOpen: false, advice: null }
}

function makeId(now, taken) {
  var id = "d-" + now
  var n = 0
  while (taken && taken.indexOf(id) >= 0) { n++; id = "d-" + now + "-" + n }
  return id
}

function _normTip(t, i) {
  if (!t || typeof t !== "object") return null
  return {
    id: _str(t.id) || ("t" + (i + 1)),
    kind: KIND_LABELS[t.kind] ? t.kind : "clarity",
    title: _str(t.title),
    body: _str(t.body),
    quote: _str(t.quote),
    done: t.done === true
  }
}

function _normAdvice(a) {
  if (!a || typeof a !== "object") return null
  var tips = []
  var src = Array.isArray(a.tips) ? a.tips : []
  for (var i = 0; i < src.length; i++) {
    var t = _normTip(src[i], i)
    if (t) tips.push(t)
  }
  return { at: _num(a.at, 0), provider: _str(a.provider), model: _str(a.model), tips: tips }
}

function normalizeDraft(d, now) {
  if (!d || typeof d !== "object" || !_str(d.id)) return null
  var created = _num(d.createdAt, now)
  return {
    id: d.id,
    createdAt: created,
    updatedAt: _num(d.updatedAt, created),
    text: _str(d.text),
    goal: _str(d.goal),
    tone: _str(d.tone),
    adviceOpen: d.adviceOpen === true,
    advice: _normAdvice(d.advice)
  }
}

// Returns { currentId, drafts } or null when the shape is unusable.
function normalizeHistory(obj, now) {
  if (!obj || typeof obj !== "object" || !Array.isArray(obj.drafts)) return null
  var out = []
  var seen = {}
  for (var i = 0; i < obj.drafts.length; i++) {
    var d = normalizeDraft(obj.drafts[i], now)
    if (!d || seen[d.id] || isEmptyDraft(d)) continue
    seen[d.id] = true
    out.push(d)
  }
  out.sort(function(a, b) { return b.updatedAt - a.updatedAt })
  return { currentId: _str(obj.currentId), drafts: out }
}

function normalizeSettings(obj) {
  var s = {
    version: 1,
    onboarded: false,
    provider: "",
    model: "",
    maxTips: 6,
    scan: { at: 0, providers: [] }
  }
  if (!obj || typeof obj !== "object") return s
  s.onboarded = obj.onboarded === true
  s.provider = _str(obj.provider)
  s.model = _str(obj.model)
  var m = Math.round(_num(obj.maxTips, 6))
  s.maxTips = Math.max(1, Math.min(20, m))
  if (obj.scan && typeof obj.scan === "object") {
    s.scan = {
      at: _num(obj.scan.at, 0),
      providers: Array.isArray(obj.scan.providers) ? obj.scan.providers : []
    }
  }
  return s
}

function historyJson(currentId, drafts) {
  var persisted = []
  var ids = []
  for (var i = 0; i < drafts.length; i++) {
    if (isEmptyDraft(drafts[i])) continue
    persisted.push(drafts[i])
    ids.push(drafts[i].id)
  }
  persisted.sort(function(a, b) { return b.updatedAt - a.updatedAt })
  return JSON.stringify({
    version: 1,
    currentId: ids.indexOf(currentId) >= 0 ? currentId : "",
    drafts: persisted
  }, null, 2)
}

function nextTipId(tips) {
  var max = 0
  for (var i = 0; i < tips.length; i++) {
    var m = /^t(\d+)$/.exec(tips[i].id || "")
    if (m) max = Math.max(max, parseInt(m[1], 10))
  }
  return "t" + (Math.max(max, tips.length) + 1)
}

function providerUsable(p) {
  return !!p && p.installed === true && p.signedIn === true
}

// Settings patch for the provider/model after a scan ({} when nothing to change).
function pickProvider(settings, providers) {
  var list = Array.isArray(providers) ? providers : []
  var cur = null
  for (var i = 0; i < list.length; i++) if (list[i].id === settings.provider) cur = list[i]
  var chosen = providerUsable(cur) ? cur : null
  if (!chosen) {
    for (var j = 0; j < list.length; j++) {
      if (providerUsable(list[j])) { chosen = list[j]; break }
    }
  }
  if (!chosen) return {}
  var models = Array.isArray(chosen.models) ? chosen.models : []
  var modelOk = false
  for (var k = 0; k < models.length; k++) if (models[k].id === settings.model) modelOk = true
  var patch = {}
  if (chosen.id !== settings.provider) patch.provider = chosen.id
  if (chosen.id !== settings.provider || !modelOk) {
    patch.model = chosen.defaultModel || (models.length > 0 ? models[0].id : "")
  }
  return patch
}

function parseJson(text, fallback) {
  try {
    var v = JSON.parse(String(text || ""))
    return v === null || v === undefined ? fallback : v
  } catch (e) {
    return fallback
  }
}
