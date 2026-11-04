import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import "Model.js" as Model

// The single timer behind every copy of the bar widget. The bar builds one
// widget per monitor, so the countdown, the phase changes and the
// notification live here, once, and the widgets only read and call in.
//
// Runtime state is saved to ~/.local/state/omarchy/pomodoro.json, never
// under the plugin directory: a write there would reload the plugin.
Item {
  id: root

  property var shell: null

  // Raw per-widget settings from the bar entry in shell.json, pushed in by
  // the widget. Everything reads the bounded copy in `cfg`.
  property var settings: ({})
  readonly property var cfg: Model.normalizeSettings(settings)

  property string phase: "focus"
  property bool running: false
  property double endsAt: 0
  property int remainingMs: Model.phaseDurationMs("focus", cfg)
  property int completedFocus: 0
  property bool restored: false

  readonly property int durationMs: Model.phaseDurationMs(phase, cfg)
  readonly property bool paused: !running && remainingMs < durationMs
  readonly property bool onBreak: Model.isBreak(phase)
  readonly property real progress: Model.fraction(remainingMs, durationMs)

  signal phaseCompleted(string finishedPhase, string nextPhase)

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function start() {
    if (running) return
    if (remainingMs <= 0) remainingMs = durationMs
    endsAt = Date.now() + remainingMs
    running = true
    persist()
  }

  function pause() {
    if (!running) return
    remainingMs = Math.max(0, Math.round(endsAt - Date.now()))
    running = false
    endsAt = 0
    persist()
  }

  function toggle() {
    if (running) pause()
    else start()
  }

  // Back to the start of the current phase, stopped.
  function reset() {
    running = false
    endsAt = 0
    remainingMs = durationMs
    persist()
  }

  // Straight to the next phase without finishing this one. A skipped focus
  // session does not count toward the long break.
  function skip() {
    const next = Model.advance(phase, completedFocus, cfg)
    if (phase === "focus") next.completedFocus = completedFocus
    enterPhase(next.phase, next.completedFocus, false)
  }

  function enterPhase(nextPhase, nextCompleted, autoStart) {
    phase = nextPhase
    completedFocus = nextCompleted
    endsAt = 0
    running = false
    remainingMs = Model.phaseDurationMs(nextPhase, cfg)
    if (autoStart) start()
    else persist()
  }

  function tick() {
    if (!running) return
    const left = Math.round(endsAt - Date.now())
    if (left > 0) {
      remainingMs = left
      return
    }
    remainingMs = 0
    complete()
  }

  function complete() {
    const finished = phase
    const next = Model.advance(phase, completedFocus, cfg)
    if (cfg.notify) notifyCompleted(finished, next.phase)
    phaseCompleted(finished, next.phase)
    enterPhase(next.phase, next.completedFocus, Model.autoStarts(next.phase, cfg))
  }

  function notifyCompleted(finished, nextPhase) {
    const minutes = Commons.I18n.formatNumber(Model.phaseMinutes(nextPhase, cfg))
    let title, body, glyph
    if (finished === "focus") {
      title = strings.t("notify.focusDone.title")
      body = strings.t(nextPhase === "longBreak" ? "notify.focusDone.longBreak" : "notify.focusDone.shortBreak").arg(minutes)
      glyph = ""
    } else {
      title = strings.t("notify.breakDone.title")
      body = strings.t("notify.breakDone.body").arg(minutes)
      glyph = ""
    }
    // Arguments go as an argv array, never through a shell string.
    Quickshell.execDetached([
      "omarchy-notification-send",
      "--app-name", "Pomodoro",
      "-u", "normal",
      "-g", glyph,
      Model.plainText(title),
      Model.plainText(body)
    ])
  }

  function statusText() {
    return JSON.stringify({
      phase: phase,
      running: running,
      paused: paused,
      remainingMs: remainingMs,
      remaining: Model.formatClock(remainingMs),
      durationMs: durationMs,
      completedFocus: completedFocus,
      sessionsBeforeLongBreak: cfg.sessionsBeforeLongBreak
    })
  }

  function persist() {
    if (!restored) return
    stateFile.setText(Model.serializeState({
      phase: phase,
      running: running,
      endsAt: endsAt,
      remainingMs: running ? Math.max(0, Math.round(endsAt - Date.now())) : remainingMs,
      completedFocus: completedFocus
    }, Date.now()) + "\n")
  }

  function restore(raw) {
    const state = Model.parseState(raw, cfg, Date.now())
    phase = state.phase
    completedFocus = state.completedFocus
    running = state.running
    endsAt = state.endsAt
    remainingMs = state.remainingMs
    restored = true
    if (running) tick()
  }

  // A duration edited while the phase sits untouched at its start takes
  // effect at once; a session already under way keeps its end time.
  onCfgChanged: {
    if (!running && !paused) remainingMs = durationMs
    else if (!running) remainingMs = Math.min(remainingMs, durationMs)
  }

  Timer {
    interval: 1000
    running: root.running
    repeat: true
    onTriggered: root.tick()
  }

  FileView {
    id: stateFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/pomodoro.json"
    blockLoading: true
    atomicWrites: true
    printErrors: false
  }

  Component.onCompleted: {
    let raw = ""
    try { raw = stateFile.text() } catch (e) { raw = "" }
    restore(raw)
  }
}
