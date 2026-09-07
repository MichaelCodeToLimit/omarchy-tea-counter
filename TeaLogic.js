.pragma library

// Pure logic for the tea counter: the caffeine model, day bucketing around
// a configurable rollover hour, aggregation, and (de)serialization.
//
// No QML, no I/O — TeaStore owns the file, Widget owns the pixels, and
// everything that can be reasoned about on paper lives here so the CLI in
// bin/omarchy-tea can mirror it exactly.

var VERSION = 1

// One full cup is 8oz of standard brewed black tea (~47 mg caffeine).
// Everything else scales off this single number, which the user can retune in widget settings.
var DEFAULT_BASE_MG = 47
var DEFAULT_ROLLOVER_HOUR = 4

var STRENGTHS = [
  { value: "black",  label: "Black",  short: "Black",  factor: 1.0 },
  { value: "green",  label: "Green",  short: "Green",  factor: 0.6 },
  { value: "herbal", label: "Herbal", short: "Herbal", factor: 0.0 },
  { value: "decaf",  label: "Decaf",  short: "Decaf",  factor: 0.04 }
]

var SIZES = [
  { value: "0.25", label: "¼",     fraction: 0.25 },
  { value: "0.5",  label: "½",     fraction: 0.5 },
  { value: "0.75", label: "¾",     fraction: 0.75 },
  { value: "1",    label: "1",     fraction: 1.0 },
  { value: "1.5",  label: "1½",    fraction: 1.5 }
]

var STYLES = [
  { value: "plain",      label: "Plain", short: "plain" },
  { value: "sweet",      label: "Sweet", short: "sweet" },
  { value: "milk",       label: "Milk",  short: "milk" },
  { value: "sweet-milk", label: "Both",  short: "sweet + milk" }
]

var DAY_LETTERS = ["M", "T", "W", "T", "F", "S", "S"]

// ---------------------------------------------------------------- lookups

function findOption(list, value, fallbackIndex) {
  var v = String(value === undefined || value === null ? "" : value).toLowerCase()
  if (v === "full") v = "black"
  else if (v === "half") v = "green"
  for (var i = 0; i < list.length; i++) if (list[i].value === v) return list[i]
  return list[fallbackIndex === undefined ? 0 : fallbackIndex]
}

function findStyleOption(list, value, fallbackIndex) {
  var v = String(value === undefined || value === null ? "" : value).toLowerCase()
  if (v === "black") v = "plain"
  else if (v === "creamy") v = "milk"
  else if (v === "sweet-creamy") v = "sweet-milk"
  for (var i = 0; i < list.length; i++) if (list[i].value === v) return list[i]
  return list[fallbackIndex === undefined ? 0 : fallbackIndex]
}

function strength(value) { return findOption(STRENGTHS, value, 0) }
function size(value) { return findOption(SIZES, value, 3) }
function style(value) { return findStyleOption(STYLES, value, 0) }

function strengthFactor(value) { return strength(value).factor }
function sizeFraction(value) { return size(value).fraction }

// ---------------------------------------------------------------- caffeine

function caffeineMg(strengthValue, sizeValue, baseMg) {
  var base = Number(baseMg)
  if (!isFinite(base) || base <= 0) base = DEFAULT_BASE_MG
  return Math.round(base * strengthFactor(strengthValue) * sizeFraction(sizeValue))
}

// ------------------------------------------------------------------ dates

function pad2(n) {
  return (n < 10 ? "0" : "") + n
}

function isoDate(d) {
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
}

// The day a timestamp belongs to. Shifting back by the rollover hour is what
// makes a 1:30am cup count toward the night before rather than opening a new
// day nobody has woken up into yet.
function dayKey(ms, rolloverHour) {
  var hour = Number(rolloverHour)
  if (!isFinite(hour) || hour < 0 || hour > 23) hour = DEFAULT_ROLLOVER_HOUR
  return isoDate(new Date(Number(ms) - hour * 3600000))
}

// Local noon, so adding/subtracting days can never be dragged across a
// boundary by a DST shift.
function dayKeyToDate(key) {
  var parts = String(key).split("-")
  return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]), 12, 0, 0, 0)
}

function addDays(key, n) {
  var d = dayKeyToDate(key)
  d.setDate(d.getDate() + n)
  return isoDate(d)
}

// Monday-start weeks. getDay() is Sunday-based, so rotate it.
function weekStartKey(key) {
  var d = dayKeyToDate(key)
  return addDays(key, -((d.getDay() + 6) % 7))
}

function monthKey(key) { return String(key).substr(0, 7) }
function yearKey(key) { return String(key).substr(0, 4) }

// The wall-clock instant a day/time pair maps to, undoing the rollover shift
// so backfilled entries land in the day the user picked.
function timestampFor(key, hours, minutes, rolloverHour) {
  var d = dayKeyToDate(key)
  var hour = Number(rolloverHour)
  if (!isFinite(hour) || hour < 0 || hour > 23) hour = DEFAULT_ROLLOVER_HOUR
  d.setHours(0, 0, 0, 0)
  var ms = d.getTime() + (Number(hours) * 60 + Number(minutes)) * 60000
  // A time earlier than the rollover hour belongs to the following calendar
  // date while still counting as this day.
  if (Number(hours) < hour) ms += 24 * 3600000
  return ms
}

// ----------------------------------------------------------------- format

function formatCups(n) {
  var v = Math.round(Number(n) * 100) / 100
  if (!isFinite(v)) return "0"
  return v === Math.round(v) ? String(Math.round(v)) : String(Math.round(v * 10) / 10)
}

function formatTime(ms) {
  var d = new Date(Number(ms))
  var h = d.getHours()
  var suffix = h < 12 ? "a" : "p"
  var h12 = h % 12
  if (h12 === 0) h12 = 12
  return h12 + ":" + pad2(d.getMinutes()) + suffix
}

function formatDayLabel(key, todayKey) {
  if (key === todayKey) return "Today"
  if (key === addDays(todayKey, -1)) return "Yesterday"
  var d = dayKeyToDate(key)
  var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  return months[d.getMonth()] + " " + d.getDate()
}

// What an entry actually was, for the today list. Preset entries keep their
// preset name; ad-hoc ones get described from their parts.
function describeEntry(entry) {
  if (entry && entry.preset) return String(entry.preset)
  return describeDrink(entry ? entry.strength : "black", entry ? entry.size : "1", entry ? entry.style : "plain")
}

function describeDrink(strengthValue, sizeValue, styleValue) {
  return strength(strengthValue).short + " " + size(sizeValue).label + " · " + style(styleValue).short
}

// ------------------------------------------------------------- aggregation

function emptyBucket() {
  return { cups: 0, mg: 0, count: 0 }
}

function addTo(bucket, cups, mg) {
  bucket.cups += cups
  bucket.mg += mg
  bucket.count += 1
}

// Everything the panel and the bar label need, in one pass over the log.
function aggregate(entries, rolloverHour, nowMs) {
  var list = entries || []
  var todayK = dayKey(nowMs, rolloverHour)
  var weekK = weekStartKey(todayK)
  var monthK = monthKey(todayK)
  var yearK = yearKey(todayK)

  var out = {
    todayKey: todayK,
    day: emptyBucket(),
    week: emptyBucket(),
    month: emptyBucket(),
    year: emptyBucket(),
    all: emptyBucket(),
    byDay: {},
    strip: [],
    today: [],
    firstDayKey: ""
  }

  for (var i = 0; i < list.length; i++) {
    var e = list[i]
    if (!e || !isFinite(Number(e.ts))) continue
    var cups = sizeFraction(e.size)
    var mg = Number(e.mg)
    if (!isFinite(mg)) mg = caffeineMg(e.strength, e.size, DEFAULT_BASE_MG)
    var k = dayKey(e.ts, rolloverHour)

    if (!out.byDay[k]) out.byDay[k] = emptyBucket()
    addTo(out.byDay[k], cups, mg)
    addTo(out.all, cups, mg)

    if (k === todayK) { addTo(out.day, cups, mg); out.today.push(e) }
    if (weekStartKey(k) === weekK) addTo(out.week, cups, mg)
    if (monthKey(k) === monthK) addTo(out.month, cups, mg)
    if (yearKey(k) === yearK) addTo(out.year, cups, mg)

    if (out.firstDayKey === "" || k < out.firstDayKey) out.firstDayKey = k
  }

  out.today.sort(function (a, b) { return Number(b.ts) - Number(a.ts) })

  // Mon..Sun of the current week, so the strip reads like a calendar row
  // rather than a rolling window whose columns shift under you each day.
  var peak = 0
  for (var d = 0; d < 7; d++) {
    var key = addDays(weekK, d)
    var bucket = out.byDay[key] || emptyBucket()
    if (bucket.mg > peak) peak = bucket.mg
    out.strip.push({
      key: key,
      letter: DAY_LETTERS[d],
      cups: bucket.cups,
      mg: bucket.mg,
      isToday: key === todayK,
      isFuture: key > todayK
    })
  }
  for (var s = 0; s < out.strip.length; s++) {
    out.strip[s].fill = peak > 0 ? out.strip[s].mg / peak : 0
  }
  out.weekPeakMg = peak

  // Daily average over days actually logged — a fairer number than dividing
  // by calendar days that predate the plugin being installed.
  var loggedDays = 0
  for (var dk in out.byDay) if (out.byDay.hasOwnProperty(dk)) loggedDays++
  out.loggedDays = loggedDays
  out.dailyAverageMg = loggedDays > 0 ? Math.round(out.all.mg / loggedDays) : 0
  out.dailyAverageCups = loggedDays > 0 ? out.all.cups / loggedDays : 0

  return out
}

// --------------------------------------------------------------- presets

function defaultPresets() {
  return [
    { id: "usual",    name: "My usual",        icon: "󰶞", strength: "black",  size: "1", style: "plain" },
    { id: "green",    name: "Green tea",       icon: "󰶞", strength: "green",  size: "1", style: "plain" },
    { id: "nightcap", name: "Herbal nightcap", icon: "󰖔", strength: "herbal", size: "1", style: "plain" }
  ]
}

function normalizePreset(raw, index) {
  var p = raw || {}
  return {
    id: String(p.id || ("preset-" + index)),
    name: String(p.name || "Untitled"),
    icon: String(p.icon || "󰶞"),
    strength: strength(p.strength).value,
    size: size(p.size).value,
    style: style(p.style).value
  }
}

function normalizeEntry(raw, index, baseMg) {
  var e = raw || {}
  var ts = Number(e.ts)
  if (!isFinite(ts)) return null
  var st = strength(e.strength).value
  var sz = size(e.size).value
  var mg = Number(e.mg)
  return {
    id: String(e.id || ("entry-" + index)),
    ts: ts,
    strength: st,
    size: sz,
    style: style(e.style).value,
    preset: e.preset ? String(e.preset) : "",
    mg: isFinite(mg) ? mg : caffeineMg(st, sz, baseMg)
  }
}

// ------------------------------------------------------- (de)serialization

function parseState(raw, baseMg) {
  var result = { entries: [], presets: defaultPresets(), error: "" }
  var text = String(raw || "").replace(/^\s+|\s+$/g, "")
  if (text.length === 0) return result

  var parsed
  try {
    parsed = JSON.parse(text)
  } catch (e) {
    result.error = String(e)
    return result
  }
  if (!parsed || typeof parsed !== "object") return result

  var entries = []
  var rawEntries = parsed.entries || []
  for (var i = 0; i < rawEntries.length; i++) {
    var entry = normalizeEntry(rawEntries[i], i, baseMg)
    if (entry) entries.push(entry)
  }
  entries.sort(function (a, b) { return a.ts - b.ts })
  result.entries = entries

  var rawPresets = parsed.presets
  if (rawPresets && rawPresets.length > 0) {
    var presets = []
    for (var p = 0; p < rawPresets.length; p++) presets.push(normalizePreset(rawPresets[p], p))
    result.presets = presets
  } else if (rawPresets && rawPresets.length === 0) {
    // An empty list is a deliberate "I deleted them all", not a first run.
    result.presets = []
  }

  return result
}

function serializeState(entries, presets) {
  return JSON.stringify({
    version: VERSION,
    entries: entries || [],
    presets: presets || []
  }, null, 2) + "\n"
}

// -------------------------------------------------------------------- CSV

function csvCell(value) {
  var s = String(value === undefined || value === null ? "" : value)
  return /[",\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s
}

function toCsv(entries, rolloverHour) {
  var rows = ["date,time,day,preset,type,size_cups,style,caffeine_mg"]
  var list = (entries || []).slice().sort(function (a, b) { return a.ts - b.ts })
  for (var i = 0; i < list.length; i++) {
    var e = list[i]
    var d = new Date(Number(e.ts))
    rows.push([
      csvCell(isoDate(d)),
      csvCell(pad2(d.getHours()) + ":" + pad2(d.getMinutes())),
      csvCell(dayKey(e.ts, rolloverHour)),
      csvCell(e.preset || ""),
      csvCell(e.strength),
      csvCell(sizeFraction(e.size)),
      csvCell(e.style),
      csvCell(e.mg)
    ].join(","))
  }
  return rows.join("\n") + "\n"
}
