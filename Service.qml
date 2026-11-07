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
  // The current focus phase is paused or held because the session is
  // locked; a lock check that finds the session unlocked continues it. Any
  // manual Start, Pause, Skip or Reset clears it.
  property bool lockHeld: false
  // Bumped by every saved state change. A lock read remembers the value it
  // was started under, and its answer is ignored once the state has moved on.
  property int stateEpoch: 0
  // Testing only, set through the `simulateLock` IPC method and never saved:
  // true or false replaces every lock read with that answer; null reads the
  // real lock state.
  property var lockOverride: null

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
    lockHeld = false
    persist()
  }

  // Pause on a session the lock holds hands it back to the owner: it stays
  // stopped, and unlocking no longer continues it.
  function pause() {
    if (!running) {
      if (lockHeld) {
        lockHeld = false
        persist()
      }
      return
    }
    remainingMs = Math.max(0, Math.round(endsAt - Date.now()))
    running = false
    endsAt = 0
    lockHeld = false
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
    lockHeld = false
    persist()
  }

  function resetCount() {
    completedFocus = 0
    persist()
  }

  // Straight to the next phase without finishing this one. A skipped focus
  // session does not count. Skip on a break starts the next focus session;
  // Skip on focus leaves the break idle.
  function skip() {
    const skipped = phase
    const next = Model.advance(phase, completedFocus)
    enterPhase(next.phase, skipped === "focus" ? completedFocus : next.completedFocus)
    if (Model.skipStartsNext(skipped)) start()
  }

  // Kept for the `stop` IPC method that earlier versions documented; the
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
    lockHeld = false
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

  // A finished phase hands straight over: the break begins as the focus
  // session ends, and the next focus session as the break ends. With "Pause
  // when locked" on, the end of a break reads the lock state first: the
  // last periodic check may be up to a minute old, and after a resume from
  // suspend no check has run yet. The focus session is marked held while
  // the read is out, so a shell restart in between keeps the hold.
  function complete() {
    const finished = phase
    const next = Model.advance(phase, completedFocus)
    if (cfg.notify) notifyCompleted(finished, next.phase)
    if (Model.shouldChime(cfg)) chime()
    enterPhase(next.phase, next.completedFocus)
    if (Model.isBreak(finished) && cfg.pauseWhenLocked) {
      lockHeld = true
      persist()
      breakEndRead.read(stateEpoch)
    } else {
      start()
    }
  }

  // An unreadable answer counts as unlocked, so the timer behaves as it does
  // with the toggle off.
  function lockAnswer(text, exitCode) {
    const locked = exitCode === 0 ? Model.parseLockAnswer(text) : null
    if (locked === null) {
      console.warn("jg.pomodoro: lock state unreadable (omarchy-shell lock isLocked, exit " + exitCode + ": " + String(text).trim() + "); treating the session as unlocked")
      return false
    }
    return locked
  }

  function handleBreakEndRead(epoch, locked) {
    if (epoch !== stateEpoch) return
    if (Model.breakEndHolds(locked, cfg)) return
    start()
  }

  function handleLockCheck(epoch, locked) {
    if (epoch !== stateEpoch) return
    const left = running ? Math.round(endsAt - Date.now()) : remainingMs
    const action = Model.lockCheck({ phase: phase, running: running, lockHeld: lockHeld, remainingMs: left }, locked, cfg)
    if (action === "pause") {
      pause()
      lockHeld = true
      persist()
    } else if (action === "resume") {
      start()
    }
  }

  // Test hooks behind the IPC methods simulateLock, checkLock and
  // finishPhase, so the lock behavior can be tried without locking the
  // screen or waiting out a phase.
  function simulateLock(value) {
    lockOverride = Model.parseLockOverride(value)
    console.log("jg.pomodoro: simulated lock state " + (lockOverride === null ? "off" : (lockOverride ? "locked" : "unlocked")))
  }

  function checkLock() { periodicRead.read(stateEpoch) }

  // The current phase ends now, as if its countdown had reached zero.
  function finishPhase() {
    remainingMs = 0
    complete()
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
      breakScreenShown: breakScreenShown,
      pauseWhenLocked: cfg.pauseWhenLocked,
      lockHeld: lockHeld,
      simulatedLock: lockOverride === null ? "off" : (lockOverride ? "locked" : "unlocked")
    })
  }

  // Every state change a lock read could be stale against goes through here.
  function persist() {
    stateEpoch += 1
    if (!restored) return
    stateFile.setText(Model.serializeState({
      phase: phase,
      running: running,
      endsAt: endsAt,
      durationMs: durationMs,
      remainingMs: running ? Math.max(0, Math.round(endsAt - Date.now())) : remainingMs,
      completedFocus: completedFocus,
      lockHeld: lockHeld
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
    lockHeld = state.lockHeld
    restored = true
    if (running) tick()
    // A hold carried over a restart waits for the first periodic check, a
    // minute in: during shell startup the lock service may not answer yet,
    // or may not have recovered a lock that outlived the old shell, and an
    // early "false" would start focus on the lock screen.
  }

  // A length chosen while the phase sits untouched at its start takes effect
  // at once; a session under way or paused keeps its time. Turning "Pause
  // when locked" off leaves a held session stopped for the owner to start.
  onCfgChanged: {
    if (!cfg.pauseWhenLocked && lockHeld) {
      lockHeld = false
      persist()
    }
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

  // The lock check for "Pause when locked": once a minute while a focus
  // session runs or the lock holds one. Breaks are not checked; their end
  // reads the lock state itself.
  Timer {
    interval: 60000
    running: root.restored && root.cfg.pauseWhenLocked && root.phase === "focus" && (root.running || root.lockHeld)
    repeat: true
    onTriggered: periodicRead.read(root.stateEpoch)
  }

  // One read of `omarchy-shell lock isLocked`. The shell does not publish
  // its lock service to plugins, so its IPC answer is the lock state.
  // `answered` carries the epoch of the latest request and the parsed state;
  // a read that cannot start, fails, or prints anything but true or false
  // answers unlocked. A request while a read is out joins that read: its
  // answer is at most a moment older than a new one would be.
  component LockRead: Process {
    property int epoch: 0
    // Counts reads, so a late "stopped running" from one read cannot end
    // the next.
    property int generation: 0
    property bool done: true
    signal answered(int epoch, bool locked)

    function read(forEpoch) {
      if (root.lockOverride !== null) {
        const simulated = root.lockOverride
        Qt.callLater(() => answered(forEpoch, simulated))
        return
      }
      epoch = forEpoch
      if (!done) return
      generation += 1
      done = false
      running = true
    }

    function finish(forGeneration, exitCode) {
      if (done || forGeneration !== generation) return
      done = true
      answered(epoch, root.lockAnswer(out.text, exitCode))
    }

    command: ["omarchy-shell", "lock", "isLocked"]
    stdout: StdioCollector { id: out; waitForEnd: true }
    onExited: (exitCode) => finish(generation, exitCode)
    // A command that never starts emits no exit; it only stops running.
    onRunningChanged: {
      if (running) return
      const g = generation
      Qt.callLater(() => finish(g, -1))
    }
  }

  LockRead {
    id: periodicRead
    onAnswered: (epoch, locked) => root.handleLockCheck(epoch, locked)
  }

  LockRead {
    id: breakEndRead
    onAnswered: (epoch, locked) => root.handleBreakEndRead(epoch, locked)
  }

  // The chime is a fixed system sound through pw-play. A missing player or
  // file ends with a nonzero exit, which is logged with its stderr and
  // otherwise ignored.
  Process {
    id: chimeProc
    command: ["pw-play", root.chimePath]
    stderr: StdioCollector { id: chimeErr; waitForEnd: true }
    onStarted: console.log("jg.pomodoro: chime started")
    onExited: (exitCode) => {
      if (exitCode !== 0) console.warn("jg.pomodoro: chime failed, pw-play exit " + exitCode + ": " + chimeErr.text.trim())
      else console.log("jg.pomodoro: chime played")
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
