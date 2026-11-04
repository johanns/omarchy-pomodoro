// Run with: node Model.test.js
// Loads Model.js the way QML does (plain top-level functions) and checks
// the pure logic the service and panel depend on.
"use strict"
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const source = fs.readFileSync(path.join(__dirname, "Model.js"), "utf8")
const M = {}
vm.runInNewContext(source + "\n;this.__exports = { normalizeSettings, phaseMinutes, phaseDurationMs, isBreak, advance, autoStarts, remainingSeconds, formatClock, formatShort, fraction, initialState, serializeState, parseState, plainText, LIMITS }", M)
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

test("settings fall back and clamp", () => {
  const s = Model.normalizeSettings({ focusMinutes: "abc", shortBreakMinutes: 0, longBreakMinutes: 999, sessionsBeforeLongBreak: 2.6, notify: "false" })
  assert.equal(s.focusMinutes, 25)
  assert.equal(s.shortBreakMinutes, 1)
  assert.equal(s.longBreakMinutes, 120)
  assert.equal(s.sessionsBeforeLongBreak, 3)
  assert.equal(s.notify, false)
  assert.equal(s.autoStartBreaks, false)
  same(Model.normalizeSettings(null).focusMinutes, 25)
  same(Model.normalizeSettings("<img src=x>").focusMinutes, 25)
})

test("phase cycle: focus, short breaks, long break after N sessions", () => {
  const s = Model.normalizeSettings({ sessionsBeforeLongBreak: 2 })
  let st = Model.advance("focus", 0, s)
  same(st, { phase: "shortBreak", completedFocus: 1 })
  st = Model.advance("shortBreak", 1, s)
  same(st, { phase: "focus", completedFocus: 1 })
  st = Model.advance("focus", 1, s)
  same(st, { phase: "longBreak", completedFocus: 2 })
  st = Model.advance("longBreak", 2, s)
  same(st, { phase: "focus", completedFocus: 0 })
})

test("auto-start follows the kind of the next phase", () => {
  const s = Model.normalizeSettings({ autoStartBreaks: true, autoStartFocus: false })
  assert.equal(Model.autoStarts("shortBreak", s), true)
  assert.equal(Model.autoStarts("longBreak", s), true)
  assert.equal(Model.autoStarts("focus", s), false)
})

test("clock formatting rounds up and handles hours", () => {
  assert.equal(Model.formatClock(25 * 60000), "25:00")
  assert.equal(Model.formatClock(24 * 60000 + 59001), "25:00")
  assert.equal(Model.formatClock(24 * 60000 + 59000), "24:59")
  assert.equal(Model.formatClock(0), "00:00")
  assert.equal(Model.formatClock(-5), "00:00")
  assert.equal(Model.formatClock(3600000 + 61000), "1:01:01")
  assert.equal(Model.formatShort(24 * 60000 + 1), "25")
  assert.equal(Model.formatShort(59000), "59")
  assert.equal(Model.formatShort(60000), "1")
})

test("progress fraction is bounded", () => {
  assert.equal(Model.fraction(60000, 60000), 0)
  assert.equal(Model.fraction(0, 60000), 1)
  assert.equal(Model.fraction(30000, 60000), 0.5)
  assert.equal(Model.fraction(90000, 60000), 0)
  assert.equal(Model.fraction(10, 0), 0)
})

test("state round-trips and a running timer keeps its end time", () => {
  const s = Model.normalizeSettings({})
  const now = 1_700_000_000_000
  const raw = Model.serializeState({ phase: "shortBreak", running: true, endsAt: now + 90000, remainingMs: 90000, completedFocus: 2 }, now)
  const back = Model.parseState(raw, s, now + 30000)
  assert.equal(back.phase, "shortBreak")
  assert.equal(back.running, true)
  assert.equal(back.remainingMs, 60000)
  assert.equal(back.completedFocus, 2)
  const expired = Model.parseState(raw, s, now + 500000)
  assert.equal(expired.running, true)
  assert.equal(expired.remainingMs, 0)
})

test("state parsing rejects garbage and bounds values", () => {
  const s = Model.normalizeSettings({})
  const fresh = Model.initialState(s)
  same(Model.parseState("not json", s, 0), fresh)
  same(Model.parseState('{"version":1,"phase":"<b>x</b>"}', s, 0), fresh)
  same(Model.parseState('{"version":2,"phase":"focus"}', s, 0), fresh)
  const big = Model.parseState('{"version":1,"phase":"focus","running":false,"remainingMs":9e15,"completedFocus":99}', s, 0)
  assert.equal(big.remainingMs, 180 * 60000)
  assert.equal(big.completedFocus, 4)
  const bad = Model.parseState('{"version":1,"phase":"focus","running":true,"endsAt":"soon"}', s, 0)
  same(bad, fresh)
})

test("a paused session longer than the default survives restore before settings arrive", () => {
  const defaults = Model.normalizeSettings({})
  const raw = Model.serializeState({ phase: "focus", running: false, endsAt: 0, remainingMs: 45 * 60000, completedFocus: 1 }, 0)
  const back = Model.parseState(raw, defaults, 0)
  assert.equal(back.running, false)
  assert.equal(back.remainingMs, 45 * 60000)
})

test("plainText neutralizes markup headed for shared sinks", () => {
  assert.equal(Model.plainText('<img src="https://example.invalid/t">'), ' img src="https://example.invalid/t" ')
  assert.equal(Model.plainText("a & b"), "a   b")
  assert.equal(Model.plainText(null), "")
  assert.equal(Model.plainText(undefined), "")
})

console.log("\n" + passed + " tests passed")
