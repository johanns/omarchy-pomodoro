import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import "Model.js" as Model

// The single timer behind every copy of the bar widget. The bar builds one
// widget per monitor, so the countdown, the phase changes, the chime, the
// notification and the break screen live here, once; the widgets only read
// and call in.
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

  // Plain initial values: restore() and onCfgChanged assign these; they are
  // not bindings on cfg.
  property string phase: "focus"
  property bool running: false
  property double endsAt: 0
  property int durationMs: 25 * 60000
  property int remainingMs: 25 * 60000
  property int completedFocus: 0
  property bool restored: false
  // Esc or Hide on the break screen keeps it away for the rest of the break.
  property bool breakScreenHidden: false

  readonly property bool paused: !running && remainingMs < durationMs
  readonly property bool engaged: running || paused
  readonly property real progress: Model.fraction(remainingMs, durationMs)
  readonly property bool breakScreenShown: Model.shouldShowBreakScreen(phase, engaged, cfg, breakScreenHidden)

  readonly property string chimePath: "/usr/share/sounds/freedesktop/stereo/complete.oga"

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

  // Back to the start of the current phase at its configured length, stopped.
  // Reset on a focus phase that is already at its start has nothing else to
  // undo, so it clears the session count.
  function reset() {
    const atStart = !engaged && phase === "focus"
    running = false
    endsAt = 0
    durationMs = Model.phaseDurationMs(phase, cfg)
    remainingMs = durationMs
    if (atStart) completedFocus = 0
    persist()
  }

  function resetCount() {
    completedFocus = 0
    persist()
  }

  // Straight to the next phase without finishing this one. A skipped focus
  // session does not count.
  function skip() {
    const next = Model.advance(phase, completedFocus)
    enterPhase(next.phase, phase === "focus" ? completedFocus : next.completedFocus)
  }

  // Stop on the break screen: end the break now. In a focus phase it is the
  // same as skip.
  function stop() { skip() }

  // Five more minutes on the current phase, bounded by the model.
  function extend() {
    const current = running ? Math.max(0, Math.round(endsAt - Date.now())) : remainingMs
    const next = Model.extend(current, durationMs)
    if (!next) return
    durationMs = next.durationMs
    remainingMs = next.remainingMs
    if (running) endsAt = Date.now() + next.remainingMs
    persist()
  }

  function hideBreakScreen() { breakScreenHidden = true }

  function enterPhase(nextPhase, nextCompleted) {
    phase = nextPhase
    completedFocus = nextCompleted
    endsAt = 0
    running = false
    breakScreenHidden = false
    durationMs = Model.phaseDurationMs(nextPhase, cfg)
    remainingMs = durationMs
    persist()
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
    const next = Model.advance(phase, completedFocus)
    if (cfg.notify) notifyCompleted(finished, next.phase)
    if (Model.shouldChime(cfg)) chime()
    enterPhase(next.phase, next.completedFocus)
  }

  function notifyCompleted(finished, nextPhase) {
    const minutes = Commons.I18n.formatNumber(Model.phaseMinutes(nextPhase, cfg))
    const focusDone = finished === "focus"
    const title = strings.t(focusDone ? "notify.focusDone.title" : "notify.breakDone.title")
    const body = strings.t(focusDone ? "notify.focusDone.body" : "notify.breakDone.body").arg(minutes)
    // Arguments go as an argv array, never through a shell string.
    Quickshell.execDetached([
      "omarchy-notification-send",
      "--app-name", "Pomodoro",
      "-u", "normal",
      "-g", focusDone ? "" : "",
      Model.plainText(title),
      Model.plainText(body)
    ])
  }

  function chime() {
    if (chimeProc.running) return
    chimeProc.running = true
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
      focusMinutes: cfg.focusMinutes,
      breakLength: cfg.breakLength,
      breakScreenShown: breakScreenShown
    })
  }

  function persist() {
    if (!restored) return
    stateFile.setText(Model.serializeState({
      phase: phase,
      running: running,
      endsAt: endsAt,
      durationMs: durationMs,
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
    durationMs = state.durationMs
    remainingMs = state.remainingMs
    restored = true
    if (running) tick()
  }

  // A length chosen while the phase sits untouched at its start takes effect
  // at once; a session under way or paused keeps its time.
  onCfgChanged: {
    if (engaged) return
    durationMs = Model.phaseDurationMs(phase, cfg)
    remainingMs = durationMs
  }

  Timer {
    interval: 1000
    running: root.running
    repeat: true
    onTriggered: root.tick()
  }

  // The chime is a fixed system sound through pw-play. A missing player or
  // file ends with a nonzero exit, which is logged and otherwise ignored.
  Process {
    id: chimeProc
    command: ["pw-play", root.chimePath]
    onExited: (exitCode) => {
      if (exitCode !== 0) console.warn("jg.pomodoro: chime failed, pw-play exit " + exitCode)
    }
  }

  FileView {
    id: stateFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/pomodoro.json"
    blockLoading: true
    atomicWrites: true
    printErrors: false
  }

  // One full-screen break window per monitor; each shows and hides from the
  // shared state here.
  Variants {
    model: Quickshell.screens
    BreakScreen { service: root }
  }

  Component.onCompleted: {
    let raw = ""
    try { raw = stateFile.text() } catch (e) { raw = "" }
    restore(raw)
  }
}
