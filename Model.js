// Pure logic for the Pomodoro plugin. No QML or Quickshell imports, so the
// same file runs under node for Model.test.js.

const PHASES = ["focus", "break"]
const FOCUS_PRESETS = [15, 25, 50, 90]
const DEFAULT_FOCUS = 25
const BREAK_LENGTHS = { short: 5, long: 15 }
const DEFAULT_BREAK = "short"

const MINUTE_MS = 60000
const EXTEND_MS = 5 * MINUTE_MS
// The most time any phase may have left, also the bound on restored state.
const MAX_REMAINING_MS = 180 * MINUTE_MS
const MAX_COMPLETED = 100000

const STATE_VERSION = 2

// Any number snaps to the closest preset, a tie to the lower one (20 -> 15,
// 70 -> 50); anything else is the default.
function nearestPreset(value) {
  const n = Number(value)
  if (!Number.isFinite(n)) return DEFAULT_FOCUS
  return FOCUS_PRESETS.reduce((best, p) => Math.abs(p - n) < Math.abs(best - n) ? p : best, FOCUS_PRESETS[0])
}

const asBool = (value, fallback) => {
  if (value === true || value === false) return value
  if (value === "true") return true
  if (value === "false") return false
  return fallback
}

const clampInt = (value, min, max, fallback) => {
  const n = Number(value)
  if (!Number.isFinite(n)) return fallback
  return Math.min(max, Math.max(min, Math.round(n)))
}

const clampMs = (ms, maxMs) => {
  const n = Number(ms)
  if (!Number.isFinite(n) || n < 0) return 0
  return Math.min(maxMs, Math.round(n))
}

// Settings come from shell.json and are untrusted: every value is bounded
// and typed here before anything reads it. Keys from the first version
// (shortBreakMinutes, longBreakMinutes, sessionsBeforeLongBreak,
// autoStartBreaks, autoStartFocus) are ignored.
function normalizeSettings(raw) {
  const s = raw && typeof raw === "object" ? raw : {}
  return {
    focusMinutes: nearestPreset(s.focusMinutes),
    breakLength: Object.prototype.hasOwnProperty.call(BREAK_LENGTHS, s.breakLength) ? s.breakLength : DEFAULT_BREAK,
    notify: asBool(s.notify, true),
    chime: asBool(s.chime, false),
    breakScreen: asBool(s.breakScreen, false),
    pauseWhenLocked: asBool(s.pauseWhenLocked, true)
  }
}

const isPhase = (value) => PHASES.includes(value)
const isBreak = (phase) => phase === "break"

function phaseMinutes(phase, settings) {
  return isBreak(phase) ? BREAK_LENGTHS[settings.breakLength] : settings.focusMinutes
}

const phaseDurationMs = (phase, settings) => phaseMinutes(phase, settings) * MINUTE_MS

// The phase that follows `phase`, and the completed-focus count after it.
// Focus and break alternate; a finished focus session adds one to the count.
function advance(phase, completedFocus) {
  const done = clampInt(completedFocus, 0, MAX_COMPLETED, 0)
  if (phase === "focus") return { phase: "break", completedFocus: Math.min(MAX_COMPLETED, done + 1) }
  return { phase: "focus", completedFocus: done }
}

// Five more minutes on the current phase: remaining and duration both grow,
// so progress keeps its meaning. Null when the result would pass the cap.
function extend(remainingMs, durationMs) {
  const remaining = clampMs(remainingMs, MAX_REMAINING_MS) + EXTEND_MS
  if (remaining > MAX_REMAINING_MS) return null
  return { remainingMs: remaining, durationMs: Math.min(MAX_REMAINING_MS, clampMs(durationMs, MAX_REMAINING_MS) + EXTEND_MS) }
}

const shouldChime = (settings) => settings.chime === true

// What a periodic lock check does to the timer, with "Pause when locked" on:
// "pause" stops a running focus session while the session is locked;
// "resume" continues a focus session the lock paused or held once the
// session is unlocked; "none" otherwise. Breaks keep running while locked,
// and a focus session the owner paused is never continued here. A running
// session with no time left is about to finish, so it is not paused: a
// pause would store zero, skip the phase change, and restart focus at full
// length on unlock.
function lockCheck(state, locked, settings) {
  if (settings.pauseWhenLocked !== true || state.phase !== "focus") return "none"
  if (state.running && locked === true) return state.remainingMs > 0 ? "pause" : "none"
  if (!state.running && state.lockHeld === true && locked === false) return "resume"
  return "none"
}

// Whether a break that has just ended leaves the next focus session held
// instead of starting it.
const breakEndHolds = (locked, settings) => settings.pauseWhenLocked === true && locked === true

// Skip on a break starts the focus session that follows; Skip on focus
// leaves the break it leads to idle.
const skipStartsNext = (phase) => isBreak(phase)

// The answer of `omarchy-shell lock isLocked`: true, false, or null when it
// is neither.
function parseLockAnswer(text) {
  const answer = String(text ?? "").trim()
  if (answer === "true") return true
  if (answer === "false") return false
  return null
}

// A lock hold only applies to a focus phase that is not running.
const validLockHeld = (phase, running, lockHeld) => lockHeld === true && phase === "focus" && running !== true

// The break screen shows while a break is running or paused, the toggle is
// on, and the user has not hidden it for this break.
const shouldShowBreakScreen = (phase, engaged, settings, hiddenForBreak) =>
  isBreak(phase) && engaged === true && settings.breakScreen === true && hiddenForBreak !== true

// Seconds still to go, rounded up so the display never shows 00:00 while
// time remains.
const remainingSeconds = (ms) => Math.max(0, Math.ceil(clampMs(ms, 1e12) / 1000))

const pad2 = (n) => String(n).padStart(2, "0")

// "mm:ss", or "h:mm:ss" past an hour. Digits are plain ASCII; the caller
// localizes them.
function formatClock(ms) {
  const total = remainingSeconds(ms)
  const hours = Math.floor(total / 3600)
  const minutes = Math.floor((total % 3600) / 60)
  const seconds = total % 60
  if (hours > 0) return `${hours}:${pad2(minutes)}:${pad2(seconds)}`
  return `${pad2(minutes)}:${pad2(seconds)}`
}

// The short label for a vertical bar slot: whole minutes left while there
// is at least one, and bare seconds below that.
function formatShort(ms) {
  const total = remainingSeconds(ms)
  return String(total >= 60 ? Math.ceil(total / 60) : total)
}

function fraction(remainingMs, durationMs) {
  if (!(durationMs > 0)) return 0
  const f = 1 - clampMs(remainingMs, durationMs) / durationMs
  return Math.max(0, Math.min(1, f))
}

// A fresh, idle state at the start of a focus session.
const initialState = (settings) => ({
  phase: "focus",
  running: false,
  endsAt: 0,
  durationMs: phaseDurationMs("focus", settings),
  remainingMs: phaseDurationMs("focus", settings),
  completedFocus: 0,
  lockHeld: false
})

function serializeState(state, now) {
  return JSON.stringify({
    version: STATE_VERSION,
    phase: state.phase,
    running: state.running === true,
    endsAt: state.running ? Math.round(state.endsAt) : 0,
    durationMs: Math.round(state.durationMs),
    remainingMs: Math.round(state.remainingMs),
    completedFocus: state.completedFocus,
    lockHeld: validLockHeld(state.phase, state.running, state.lockHeld),
    savedAt: Math.round(now)
  })
}

// A version 1 file (one break phase per length, no stored duration) maps onto
// the version 2 shape; the duration comes from the current settings.
function migrateV1(data, settings) {
  const phase = data.phase === "shortBreak" || data.phase === "longBreak" ? "break" : data.phase
  return Object.assign({}, data, { version: STATE_VERSION, phase: phase, durationMs: isPhase(phase) ? phaseDurationMs(phase, settings) : 0 })
}

// Restore a saved state, bounding every field. A running timer keeps its
// absolute end time, so time spent with the shell down still counts; a
// timer whose end has already passed comes back with zero remaining, and
// the service completes it on its first tick. Remaining time is bounded by
// the longest allowed phase rather than the current settings, because the
// service restores before the widget has pushed them.
function parseState(raw, settings, now) {
  const fresh = initialState(settings)
  let data
  try {
    data = JSON.parse(String(raw ?? ""))
  } catch (e) {
    return fresh
  }
  if (!data || typeof data !== "object") return fresh
  if (data.version === 1) data = migrateV1(data, settings)
  if (data.version !== STATE_VERSION) return fresh
  if (!isPhase(data.phase)) return fresh
  const durationMs = clampMs(data.durationMs, MAX_REMAINING_MS)
  const state = {
    phase: data.phase,
    running: data.running === true,
    endsAt: 0,
    durationMs: durationMs > 0 ? durationMs : phaseDurationMs(data.phase, settings),
    remainingMs: clampMs(data.remainingMs, MAX_REMAINING_MS),
    completedFocus: clampInt(data.completedFocus, 0, MAX_COMPLETED, 0),
    // Files from 1.1.0 have no lockHeld field and read as not held.
    lockHeld: validLockHeld(data.phase, data.running === true, data.lockHeld)
  }
  if (state.running) {
    const endsAt = Number(data.endsAt)
    if (!Number.isFinite(endsAt) || endsAt <= 0 || endsAt - now > MAX_REMAINING_MS) return fresh
    state.endsAt = endsAt
    state.remainingMs = clampMs(endsAt - now, MAX_REMAINING_MS)
  }
  // A phase never has more left than it lasts: a version 1 file, or one
  // saved under a longer preset, keeps its remaining time and grows the
  // duration to match, so paused and progress stay meaningful.
  state.durationMs = Math.max(state.durationMs, state.remainingMs)
  return state
}

// Strip anything markup-shaped from text headed for a sink whose text
// format the plugin cannot set, such as the bar tooltip or a notification.
const plainText = (value) => String(value ?? "").replace(/[<>&]/g, " ")
