// Run with: node Model.test.js
// Loads Model.js the way QML does (plain top-level declarations) and checks
// the pure logic the service and panel depend on.
"use strict"
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const source = fs.readFileSync(path.join(__dirname, "Model.js"), "utf8")
const names = [
  "FOCUS_PRESETS", "BREAK_LENGTHS", "EXTEND_MS", "MAX_REMAINING_MS",
  "nearestPreset", "normalizeSettings", "phaseMinutes", "phaseDurationMs", "isBreak", "advance",
  "extend", "shouldChime", "shouldShowBreakScreen",
  "remainingSeconds", "formatClock", "formatShort", "fraction",
  "initialState", "serializeState", "parseState", "plainText",
  "lockCheck", "breakEndHolds", "skipStartsNext", "parseLockAnswer"
]
const M = {}
vm.runInNewContext(source + "\n;this.__exports = { " + names.map((n) => `${n}: typeof ${n} === "undefined" ? undefined : ${n}`).join(", ") + " }", M)
const Model = M.__exports

// Objects built inside the vm context have a different Object prototype, so
// compare by value through JSON.
function same(actual, expected) {
  assert.equal(JSON.stringify(actual), JSON.stringify(expected))
}

let passed = 0
function test(name, fn) {
  fn()
  passed += 1
  console.log("ok - " + name)
}

const MIN = 60000

test("focus presets: any value maps to the nearest of 15, 25, 50, 90", () => {
  same(Model.FOCUS_PRESETS, [15, 25, 50, 90])
  assert.equal(Model.nearestPreset(25), 25)
  assert.equal(Model.nearestPreset(30), 25)
  assert.equal(Model.nearestPreset(40), 50)
  assert.equal(Model.nearestPreset(200), 90)
  assert.equal(Model.nearestPreset(1), 15)
  assert.equal(Model.nearestPreset("50"), 50)
  assert.equal(Model.nearestPreset("abc"), 25)
  assert.equal(Model.nearestPreset(undefined), 25)
  // ties go to the lower preset
  assert.equal(Model.nearestPreset(20), 15)
  assert.equal(Model.nearestPreset(37.5), 25)
  assert.equal(Model.nearestPreset(70), 50)
})

test("settings: new keys with defaults, obsolete keys ignored", () => {
  const s = Model.normalizeSettings({
    focusMinutes: 45, breakLength: "long", notify: "false", chime: true, breakScreen: "true",
    shortBreakMinutes: 7, longBreakMinutes: 40, sessionsBeforeLongBreak: 2,
    autoStartBreaks: true, autoStartFocus: true
  })
  same(s, { focusMinutes: 50, breakLength: "long", notify: false, chime: true, breakScreen: true, pauseWhenLocked: true })
  same(Model.normalizeSettings(null), { focusMinutes: 25, breakLength: "short", notify: true, chime: false, breakScreen: false, pauseWhenLocked: true })
  same(Model.normalizeSettings({ breakLength: "<b>x</b>" }).breakLength, "short")
  assert.equal(Model.normalizeSettings("<img src=x>").focusMinutes, 25)
})

test("phase lengths follow the settings", () => {
  const s = Model.normalizeSettings({ focusMinutes: 90, breakLength: "long" })
  assert.equal(Model.phaseMinutes("focus", s), 90)
  assert.equal(Model.phaseMinutes("break", s), 15)
  assert.equal(Model.phaseDurationMs("break", Model.normalizeSettings({ breakLength: "short" })), 5 * MIN)
  assert.equal(Model.isBreak("break"), true)
  assert.equal(Model.isBreak("focus"), false)
})

test("phase order: focus then break, with no long-break cycle", () => {
  same(Model.advance("focus", 0), { phase: "break", completedFocus: 1 })
  same(Model.advance("break", 1), { phase: "focus", completedFocus: 1 })
  same(Model.advance("focus", 7), { phase: "break", completedFocus: 8 })
  same(Model.advance("break", "x"), { phase: "focus", completedFocus: 0 })
})

test("extend adds five minutes to remaining and duration, capped at 180 minutes left", () => {
  assert.equal(Model.EXTEND_MS, 5 * MIN)
  same(Model.extend(4 * MIN, 5 * MIN), { remainingMs: 9 * MIN, durationMs: 10 * MIN })
  same(Model.extend(0, 5 * MIN), { remainingMs: 5 * MIN, durationMs: 10 * MIN })
  assert.equal(Model.extend(176 * MIN, 180 * MIN), null)
  assert.equal(Model.extend(175 * MIN, 180 * MIN).remainingMs, 180 * MIN)
  same(Model.extend(100 * MIN, 180 * MIN), { remainingMs: 105 * MIN, durationMs: 180 * MIN })
})

test("chime and break screen gating", () => {
  const on = Model.normalizeSettings({ chime: true, breakScreen: true })
  const off = Model.normalizeSettings({})
  assert.equal(Model.shouldChime(on), true)
  assert.equal(Model.shouldChime(off), false)
  assert.equal(Model.shouldShowBreakScreen("break", true, on, false), true)
  assert.equal(Model.shouldShowBreakScreen("break", true, on, true), false)
  assert.equal(Model.shouldShowBreakScreen("break", false, on, false), false)
  assert.equal(Model.shouldShowBreakScreen("focus", true, on, false), false)
  assert.equal(Model.shouldShowBreakScreen("break", true, off, false), false)
})

test("clock formatting rounds up and handles hours", () => {
  assert.equal(Model.formatClock(25 * MIN), "25:00")
  assert.equal(Model.formatClock(24 * MIN + 59001), "25:00")
  assert.equal(Model.formatClock(24 * MIN + 59000), "24:59")
  assert.equal(Model.formatClock(0), "00:00")
  assert.equal(Model.formatClock(-5), "00:00")
  assert.equal(Model.formatClock(3600000 + 61000), "1:01:01")
  assert.equal(Model.formatShort(24 * MIN + 1), "25")
  assert.equal(Model.formatShort(59000), "59")
  assert.equal(Model.formatShort(MIN), "1")
})

test("progress fraction is bounded", () => {
  assert.equal(Model.fraction(MIN, MIN), 0)
  assert.equal(Model.fraction(0, MIN), 1)
  assert.equal(Model.fraction(30000, MIN), 0.5)
  assert.equal(Model.fraction(90000, MIN), 0)
  assert.equal(Model.fraction(10, 0), 0)
})

test("state v2 round-trips, keeps the duration, and a running timer keeps its end time", () => {
  const s = Model.normalizeSettings({})
  const now = 1_700_000_000_000
  const raw = Model.serializeState({ phase: "break", running: true, endsAt: now + 90000, durationMs: 10 * MIN, remainingMs: 90000, completedFocus: 2 }, now)
  assert.equal(JSON.parse(raw).version, 2)
  const back = Model.parseState(raw, s, now + 30000)
  same(back, { phase: "break", running: true, endsAt: now + 90000, durationMs: 10 * MIN, remainingMs: 60000, completedFocus: 2, lockHeld: false })
  const expired = Model.parseState(raw, s, now + 500000)
  assert.equal(expired.running, true)
  assert.equal(expired.remainingMs, 0)
})

test("state v1 migrates: break phases merge, duration comes from settings", () => {
  const s = Model.normalizeSettings({ breakLength: "long" })
  const v1 = JSON.stringify({ version: 1, phase: "shortBreak", running: false, endsAt: 0, remainingMs: 2 * MIN, completedFocus: 3, savedAt: 0 })
  same(Model.parseState(v1, s, 0), { phase: "break", running: false, endsAt: 0, durationMs: 15 * MIN, remainingMs: 2 * MIN, completedFocus: 3, lockHeld: false })
  const v1focus = JSON.stringify({ version: 1, phase: "focus", running: false, endsAt: 0, remainingMs: 25 * MIN, completedFocus: 1 })
  assert.equal(Model.parseState(v1focus, s, 0).durationMs, 25 * MIN)
  assert.equal(Model.parseState(v1focus, s, 0).phase, "focus")
})

test("restored remaining time never exceeds the duration, so paused and progress hold", () => {
  const defaults = Model.normalizeSettings({})
  const now = 1_700_000_000_000
  // v1 paused focus with more left than the default preset
  const pausedV1 = JSON.stringify({ version: 1, phase: "focus", running: false, endsAt: 0, remainingMs: 40 * MIN, completedFocus: 0 })
  const p = Model.parseState(pausedV1, defaults, now)
  assert.equal(p.remainingMs, 40 * MIN)
  assert.equal(p.durationMs, 40 * MIN)
  // v1 running long break with ten minutes left keeps its end time
  const runningV1 = JSON.stringify({ version: 1, phase: "longBreak", running: true, endsAt: now + 10 * MIN, remainingMs: 0, completedFocus: 2 })
  const r = Model.parseState(runningV1, defaults, now)
  assert.equal(r.phase, "break")
  assert.equal(r.running, true)
  assert.equal(r.endsAt, now + 10 * MIN)
  assert.equal(r.remainingMs, 10 * MIN)
  assert.ok(r.durationMs >= r.remainingMs)
  // v2 with inconsistent fields is repaired the same way
  const v2 = JSON.stringify({ version: 2, phase: "focus", running: false, endsAt: 0, durationMs: 15 * MIN, remainingMs: 20 * MIN, completedFocus: 0 })
  assert.equal(Model.parseState(v2, defaults, now).durationMs, 20 * MIN)
})

test("a running state whose end lies more than 180 minutes ahead is discarded", () => {
  const defaults = Model.normalizeSettings({})
  const now = 1_700_000_000_000
  const far = JSON.stringify({ version: 2, phase: "focus", running: true, endsAt: now + 181 * MIN, durationMs: 25 * MIN, remainingMs: 0, completedFocus: 0 })
  same(Model.parseState(far, defaults, now), Model.initialState(defaults))
  const near = JSON.stringify({ version: 2, phase: "focus", running: true, endsAt: now + 179 * MIN, durationMs: 25 * MIN, remainingMs: 0, completedFocus: 0 })
  assert.equal(Model.parseState(near, defaults, now).remainingMs, 179 * MIN)
})

test("state parsing rejects garbage and bounds values", () => {
  const s = Model.normalizeSettings({})
  const fresh = Model.initialState(s)
  same(fresh, { phase: "focus", running: false, endsAt: 0, durationMs: 25 * MIN, remainingMs: 25 * MIN, completedFocus: 0, lockHeld: false })
  same(Model.parseState("not json", s, 0), fresh)
  same(Model.parseState('{"version":2,"phase":"<b>x</b>"}', s, 0), fresh)
  same(Model.parseState('{"version":3,"phase":"focus"}', s, 0), fresh)
  const big = Model.parseState('{"version":2,"phase":"focus","running":false,"durationMs":9e15,"remainingMs":9e15,"completedFocus":1e9}', s, 0)
  assert.equal(big.remainingMs, 180 * MIN)
  assert.equal(big.durationMs, 180 * MIN)
  assert.equal(big.completedFocus, 100000)
  const bad = Model.parseState('{"version":2,"phase":"focus","running":true,"endsAt":"soon"}', s, 0)
  same(bad, fresh)
})

test("a paused session longer than the default survives restore before settings arrive", () => {
  const defaults = Model.normalizeSettings({})
  const raw = Model.serializeState({ phase: "focus", running: false, endsAt: 0, durationMs: 90 * MIN, remainingMs: 45 * MIN, completedFocus: 1 }, 0)
  const back = Model.parseState(raw, defaults, 0)
  assert.equal(back.running, false)
  assert.equal(back.remainingMs, 45 * MIN)
  assert.equal(back.durationMs, 90 * MIN)
})

test("settings: pauseWhenLocked defaults to on; only false turns it off", () => {
  assert.equal(Model.normalizeSettings({}).pauseWhenLocked, true)
  assert.equal(Model.normalizeSettings(null).pauseWhenLocked, true)
  assert.equal(Model.normalizeSettings({ pauseWhenLocked: "x" }).pauseWhenLocked, true)
  assert.equal(Model.normalizeSettings({ pauseWhenLocked: false }).pauseWhenLocked, false)
  assert.equal(Model.normalizeSettings({ pauseWhenLocked: "false" }).pauseWhenLocked, false)
  assert.equal(Model.normalizeSettings({ pauseWhenLocked: true }).pauseWhenLocked, true)
})

test("lock check: a locked session pauses running focus; unlock continues only what the lock paused", () => {
  const on = Model.normalizeSettings({})
  const off = Model.normalizeSettings({ pauseWhenLocked: false })
  const runningFocus = { phase: "focus", running: true, lockHeld: false, remainingMs: 60000 }
  const lockPaused = { phase: "focus", running: false, lockHeld: true }
  const ownerPaused = { phase: "focus", running: false, lockHeld: false }
  const runningBreak = { phase: "break", running: true, lockHeld: false }
  assert.equal(Model.lockCheck(runningFocus, true, on), "pause")
  assert.equal(Model.lockCheck(runningFocus, false, on), "none")
  assert.equal(Model.lockCheck(lockPaused, false, on), "resume")
  assert.equal(Model.lockCheck(lockPaused, true, on), "none")
  assert.equal(Model.lockCheck(ownerPaused, false, on), "none")
  assert.equal(Model.lockCheck(ownerPaused, true, on), "none")
  // breaks keep running while locked
  assert.equal(Model.lockCheck(runningBreak, true, on), "none")
  // toggle off: no change either way
  assert.equal(Model.lockCheck(runningFocus, true, off), "none")
  assert.equal(Model.lockCheck(lockPaused, false, off), "none")
})

test("lock check: a running focus session whose time has run out is left to finish, not paused", () => {
  const on = Model.normalizeSettings({})
  const ranOut = { phase: "focus", running: true, lockHeld: false, remainingMs: 0 }
  const lastSecond = { phase: "focus", running: true, lockHeld: false, remainingMs: 1000 }
  assert.equal(Model.lockCheck(ranOut, true, on), "none")
  assert.equal(Model.lockCheck(lastSecond, true, on), "pause")
})

test("break end: focus is held while locked and starts at once otherwise", () => {
  const on = Model.normalizeSettings({})
  const off = Model.normalizeSettings({ pauseWhenLocked: false })
  assert.equal(Model.breakEndHolds(true, on), true)
  assert.equal(Model.breakEndHolds(false, on), false)
  assert.equal(Model.breakEndHolds(true, off), false)
  assert.equal(Model.breakEndHolds(false, off), false)
})

test("skip: from a break the next focus session starts; from focus the break stays idle", () => {
  assert.equal(Model.skipStartsNext("break"), true)
  assert.equal(Model.skipStartsNext("focus"), false)
  // the skipped break leaves the count unchanged
  same(Model.advance("break", 3), { phase: "focus", completedFocus: 3 })
})

test("lock answer: true and false parse; anything else is unreadable", () => {
  assert.equal(Model.parseLockAnswer("true\n"), true)
  assert.equal(Model.parseLockAnswer(" false "), false)
  assert.equal(Model.parseLockAnswer(""), null)
  assert.equal(Model.parseLockAnswer("error: no target"), null)
  assert.equal(Model.parseLockAnswer(undefined), null)
})

test("state: a lock hold round-trips; a 1.1.0 file and invalid holds read as not held", () => {
  const s = Model.normalizeSettings({})
  const now = 1_700_000_000_000
  const held = Model.serializeState({ phase: "focus", running: false, endsAt: 0, durationMs: 25 * MIN, remainingMs: 12 * MIN, completedFocus: 2, lockHeld: true }, now)
  assert.equal(JSON.parse(held).version, 2)
  same(Model.parseState(held, s, now), { phase: "focus", running: false, endsAt: 0, durationMs: 25 * MIN, remainingMs: 12 * MIN, completedFocus: 2, lockHeld: true })
  // written by 1.1.0: no lockHeld field
  const old = JSON.stringify({ version: 2, phase: "focus", running: false, endsAt: 0, durationMs: 25 * MIN, remainingMs: 25 * MIN, completedFocus: 4, savedAt: now })
  same(Model.parseState(old, s, now), { phase: "focus", running: false, endsAt: 0, durationMs: 25 * MIN, remainingMs: 25 * MIN, completedFocus: 4, lockHeld: false })
  // a hold only means something on a focus phase that is not running
  const onBreak = JSON.stringify({ version: 2, phase: "break", running: false, endsAt: 0, durationMs: 5 * MIN, remainingMs: 5 * MIN, completedFocus: 0, lockHeld: true })
  assert.equal(Model.parseState(onBreak, s, now).lockHeld, false)
  const whileRunning = JSON.stringify({ version: 2, phase: "focus", running: true, endsAt: now + MIN, durationMs: 25 * MIN, remainingMs: MIN, completedFocus: 0, lockHeld: true })
  assert.equal(Model.parseState(whileRunning, s, now).lockHeld, false)
  assert.equal(JSON.parse(Model.serializeState({ phase: "break", running: false, endsAt: 0, durationMs: 5 * MIN, remainingMs: 5 * MIN, completedFocus: 0, lockHeld: true }, now)).lockHeld, false)
  assert.equal(Model.parseState('{"version":2,"phase":"focus","running":false,"durationMs":60000,"remainingMs":60000,"completedFocus":0,"lockHeld":"yes"}', s, now).lockHeld, false)
})

test("plainText neutralizes markup headed for shared sinks", () => {
  assert.equal(Model.plainText('<img src="https://example.invalid/t">'), ' img src="https://example.invalid/t" ')
  assert.equal(Model.plainText("a & b"), "a   b")
  assert.equal(Model.plainText(null), "")
  assert.equal(Model.plainText(undefined), "")
})

console.log("\n" + passed + " tests passed")
