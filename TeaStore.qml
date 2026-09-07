import QtQuick
import Quickshell
import Quickshell.Io
import "TeaLogic.js" as Logic

// Owns the tea log on disk and hands the widget a ready-made `stats`
// object. One store exists per bar surface (i.e. per monitor), so the file is
// the shared source of truth: every write is atomic, and `watchChanges` pulls
// a write made on one monitor — or from bin/omarchy-tea in a terminal —
// into all the others without a shell restart.
Item {
  id: store

  visible: false
  width: 0
  height: 0

  property int rolloverHour: Logic.DEFAULT_ROLLOVER_HOUR
  property int baseMg: Logic.DEFAULT_BASE_MG

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/omarchy"
  readonly property string logPath: stateDir + "/tea.json"

  property var entries: []
  property var presets: Logic.defaultPresets()
  property bool loaded: false
  property string lastError: ""
  property string lastExportPath: ""

  // Ticks every minute so "today" rolls over on its own — a panel left open
  // past the rollover hour must not keep showing yesterday's total.
  property real now: 0

  readonly property var stats: Logic.aggregate(entries, rolloverHour, now)

  signal exported(string path)

  // The text we last wrote ourselves. `watchChanges` fires on our own writes
  // too; comparing against this skips the pointless re-parse (and the array
  // identity churn that would re-run every binding downstream of `entries`).
  property string _lastWritten: ""

  function _uid(prefix) {
    return prefix + "-" + Math.round(store.now) + "-" + Math.round(Math.random() * 100000)
  }

  function _persist() {
    var text = Logic.serializeState(store.entries, store.presets)
    store._lastWritten = text
    logFile.setText(text)
  }

  // --------------------------------------------------------------- logging

  function logDrink(strengthValue, sizeValue, styleValue, presetName, timestamp) {
    var ts = Number(timestamp)
    if (!isFinite(ts) || ts <= 0) ts = Date.now()

    var entry = {
      id: _uid("cup"),
      ts: ts,
      strength: Logic.strength(strengthValue).value,
      size: Logic.size(sizeValue).value,
      style: Logic.style(styleValue).value,
      preset: presetName ? String(presetName) : "",
      mg: Logic.caffeineMg(strengthValue, sizeValue, store.baseMg)
    }

    var next = store.entries.slice()
    next.push(entry)
    next.sort(function (a, b) { return a.ts - b.ts })
    store.entries = next
    _persist()
    return entry
  }

  function logPreset(preset, timestamp) {
    if (!preset) return null
    return logDrink(preset.strength, preset.size, preset.style, preset.name, timestamp)
  }

  function removeEntry(id) {
    var target = String(id)
    var next = []
    for (var i = 0; i < store.entries.length; i++) {
      if (String(store.entries[i].id) !== target) next.push(store.entries[i])
    }
    if (next.length === store.entries.length) return false
    store.entries = next
    _persist()
    return true
  }

  function undoLast() {
    if (store.entries.length === 0) return false
    return removeEntry(store.entries[store.entries.length - 1].id)
  }

  // --------------------------------------------------------------- presets

  function savePreset(preset) {
    if (!preset) return
    var incoming = Logic.normalizePreset(preset, store.presets.length)
    if (!preset.id) incoming.id = _uid("preset")

    var next = []
    var replaced = false
    for (var i = 0; i < store.presets.length; i++) {
      if (store.presets[i].id === incoming.id) {
        next.push(incoming)
        replaced = true
      } else {
        next.push(store.presets[i])
      }
    }
    if (!replaced) next.push(incoming)
    store.presets = next
    _persist()
    return incoming
  }

  function deletePreset(id) {
    var target = String(id)
    var next = []
    for (var i = 0; i < store.presets.length; i++) {
      if (store.presets[i].id !== target) next.push(store.presets[i])
    }
    store.presets = next
    _persist()
  }

  function presetAt(index) {
    return (index >= 0 && index < store.presets.length) ? store.presets[index] : null
  }

  // ---------------------------------------------------------------- export

  function exportCsv() {
    csvFile.path = store.home + "/tea-history.csv"
    csvFile.setText(Logic.toCsv(store.entries, store.rolloverHour))
    store.lastExportPath = csvFile.path
    store.exported(csvFile.path)
    return csvFile.path
  }

  // ------------------------------------------------------------ persistence

  function _load(raw) {
    var parsed = Logic.parseState(raw, store.baseMg)
    store.lastError = parsed.error
    if (parsed.error) console.warn("michael.tea: log parse failed:", parsed.error)
    store.entries = parsed.entries
    store.presets = parsed.presets
    store.loaded = true
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: store.now = date.getTime()
  }

  Process {
    id: ensureDirProc
    command: ["mkdir", "-p", store.stateDir]
    running: false
  }

  FileView {
    id: logFile
    path: store.logPath
    watchChanges: true
    atomicWrites: true
    printErrors: false

    onFileChanged: reload()
    onLoaded: {
      var raw = text()
      // Our own write coming back around; the in-memory state already matches.
      if (store.loaded && raw === store._lastWritten) return
      store._load(raw)
    }
    // First run: no file yet. Without this the store would never flip to
    // `loaded` and the first logged cup would have nothing to merge into.
    onLoadFailed: if (!store.loaded) store._load("")
  }

  FileView {
    id: csvFile
    atomicWrites: true
    printErrors: false
  }

  Component.onCompleted: {
    store.now = Date.now()
    ensureDirProc.running = true
    Qt.callLater(function () { logFile.reload() })
  }
}
