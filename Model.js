// Pure logic for the Pomodoro plugin. No QML or Quickshell imports, so the
// same file runs under node for Model.test.js.

const PHASES = ["focus", "shortBreak", "longBreak"]

const LIMITS = {
  focusMinutes: { min: 1, max: 180, fallback: 25 },
  shortBreakMinutes: { min: 1, max: 60, fallback: 5 },
  longBreakMinutes: { min: 1, max: 120, fallback: 15 },
  sessionsBeforeLongBreak: { min: 1, max: 12, fallback: 4 }
}

// The most any phase can last, used to bound a restored remaining time
// before the real settings arrive from the bar entry.
const MAX_PHASE_MS = LIMITS.focusMinutes.max * 60000

const clampInt = (value, min, max, fallback) => {
  const n = Number(value)
  if (!Number.isFinite(n)) return fallback
  return Math.min(max, Math.max(min, Math.round(n)))
}

const asBool = (value, fallback) => {
  if (value === true || value === false) return value
  if (value === "true") return true
  if (value === "false") return false
  return fallback
}

// Settings come from shell.json and are untrusted: every value is bounded
// and typed here before anything reads it.
function normalizeSettings(raw) {
  const s = raw && typeof raw === "object" ? raw : {}
  const out = {}
  for (const [key, limit] of Object.entries(LIMITS))
    out[key] = clampInt(s[key], limit.min, limit.max, limit.fallback)
  out.autoStartBreaks = asBool(s.autoStartBreaks, false)
  out.autoStartFocus = asBool(s.autoStartFocus, false)
  out.notify = asBool(s.notify, true)
  return out
}

const isPhase = (value) => PHASES.includes(value)

function phaseMinutes(phase, settings) {
  if (phase === "shortBreak") return settings.shortBreakMinutes
  if (phase === "longBreak") return settings.longBreakMinutes
  return settings.focusMinutes
}

const phaseDurationMs = (phase, settings) => phaseMinutes(phase, settings) * 60000

const isBreak = (phase) => phase === "shortBreak" || phase === "longBreak"

// The phase that follows `phase`, and the completed-focus count after it.
// Completed focus sessions count within the current cycle and wrap to zero
// once the long break begins, so the dots in the panel always show
// progress toward the next long break.
function advance(phase, completedFocus, settings) {
  let done = clampInt(completedFocus, 0, settings.sessionsBeforeLongBreak, 0)
  if (phase === "focus") {
    done += 1
    if (done >= settings.sessionsBeforeLongBreak) return { phase: "longBreak", completedFocus: done }
    return { phase: "shortBreak", completedFocus: done }
  }
  if (phase === "longBreak") return { phase: "focus", completedFocus: 0 }
  return { phase: "focus", completedFocus: done }
}

// Whether the next phase should begin counting down on its own.
const autoStarts = (nextPhase, settings) =>
  isBreak(nextPhase) ? settings.autoStartBreaks : settings.autoStartFocus

const clampMs = (ms, maxMs) => {
  const n = Number(ms)
  if (!Number.isFinite(n) || n < 0) return 0
  return Math.min(maxMs, Math.round(n))
}

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
  remainingMs: phaseDurationMs("focus", settings),
  completedFocus: 0
})

function serializeState(state, now) {
  return JSON.stringify({
    version: 1,
    phase: state.phase,
    running: state.running === true,
    endsAt: state.running ? Math.round(state.endsAt) : 0,
    remainingMs: Math.round(state.remainingMs),
    completedFocus: state.completedFocus,
    savedAt: Math.round(now)
  })
}

// Restore a saved state, bounding every field. A running timer keeps its
// absolute end time, so time spent with the shell down still counts; a
// timer whose end has already passed comes back with zero remaining, and
// the service completes it on its first tick. The remaining time is bounded
// by the longest allowed phase rather than the current settings, because the
// service restores before the widget has pushed them; onCfgChanged applies
// the per-phase bound once they arrive.
function parseState(raw, settings, now) {
  const fresh = initialState(settings)
  let data
  try {
    data = JSON.parse(String(raw ?? ""))
  } catch (e) {
    return fresh
  }
  if (!data || typeof data !== "object" || data.version !== 1) return fresh
  if (!isPhase(data.phase)) return fresh
  const state = {
    phase: data.phase,
    running: data.running === true,
    endsAt: 0,
    remainingMs: clampMs(data.remainingMs, MAX_PHASE_MS),
    completedFocus: clampInt(data.completedFocus, 0, settings.sessionsBeforeLongBreak, 0)
  }
  if (state.running) {
    const endsAt = Number(data.endsAt)
    if (!Number.isFinite(endsAt) || endsAt <= 0) return fresh
    state.endsAt = endsAt
    state.remainingMs = clampMs(endsAt - now, MAX_PHASE_MS)
  }
  return state
}

// Strip anything markup-shaped from text headed for a sink whose text
// format the plugin cannot set, such as the bar tooltip or a notification.
const plainText = (value) => String(value ?? "").replace(/[<>&]/g, " ")
