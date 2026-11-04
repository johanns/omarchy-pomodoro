# Spec 20261104-preset-durations-and-break-screen: Preset durations, break choice, and break screen

Created: 2026-11-04
Updated: 2026-11-04

Kind: feature
Work item: [work.md](../work.md)
Context: Pomodoro plugin for the Omarchy shell (`jg.pomodoro`), published at https://github.com/johanns/omarchy-pomodoro

## Agreement

- User and problem: The plugin owner wants faster, less error-prone session setup. Today the
  panel exposes free-form minute fields for focus, short break, long break, and a
  sessions-per-cycle count. The owner wants one-tap presets and two new end-of-session
  behaviors.
- Desired behavior or structural outcome:
  1. A dedicated Focus row in the panel that picks one of four focus lengths: 15, 25, 50, 90 minutes.
  2. A dedicated Break row that picks the break length: Short (5 minutes) or Long (15 minutes).
  3. A Behavior section with three toggles: Notification, Chime, Break screen.
  4. The free-form minute fields and the sessions-per-cycle field are removed from the panel.
- Scope and exclusions: Panel controls, settings keys, the chime, and a full-screen break
  view. Excluded: bar slot rendering, notification wording, the plugin id, keybinding helpers.
- Accepted constraints and invariants:
  - Omarchy plugin guide (`~/.claude/skills/omarchy/plugins.md`): plain-text sinks, bounded
    untrusted settings, no shell-string command interpolation, `Style.duration()` motion,
    strings through `Commons.Translations`.
  - Existing architecture: one timer in `Service.qml`, widgets per monitor read it; state in
    `~/.local/state/omarchy/pomodoro.json`; settings inline on the bar entry in `shell.json`.
  - Existing settings files may carry old keys (`focusMinutes` with any value,
    `shortBreakMinutes`, `longBreakMinutes`, `sessionsBeforeLongBreak`, `autoStartBreaks`,
    `autoStartFocus`); loading them must not break the plugin.
  - QML and JS edits need `omarchy restart shell` (README, Development).
- Completion condition: All acceptance criteria met, `node Model.test.js` green, the panel and
  break screen inspected on the owner's desktop, and the owner accepts the result. Pushing to
  GitHub is part of delivery, as for earlier work in this repository.

### Acceptance criteria

- [ ] AC1: The panel shows a Focus row with exactly four options, 15, 25, 50 and 90, one of
  which is always selected. Selecting an option persists `focusMinutes` to the bar entry.
- [ ] AC2: A focus preset chosen while idle at the start of a focus phase sets the countdown to
  that length at once. A preset chosen while a focus session runs or is paused does not change
  the running session; the next focus session uses it.
- [ ] AC3: The panel shows a Break row with exactly two options, Short (5 min) and Long
  (15 min), one always selected. The selection decides the length of the next break and
  persists as a setting.
- [ ] AC4: Behavior shows exactly three toggles: Notification, Chime, Break screen. Each
  persists as a boolean setting and defaults to Notification on, Chime off, Break screen off.
- [ ] AC5: With Chime on, a short sound plays when a focus session or a break ends. With Chime
  off, no sound plays. The player is invoked with an argument array, never a shell string, and a
  missing player or sound file is logged and otherwise ignored.
- [ ] AC6: With Break screen on, a full-screen view appears on every monitor while a break runs
  or is paused, showing the phase, the countdown, a progress row drawn as a Pac-Man eating a
  line of dots (V7), and three buttons: Pause, +5 min, Stop. There is no icon above the phase
  and no explanatory text; one hint line below the buttons names Esc. Esc, a click outside the
  content, or the end of the break removes it; once hidden it stays hidden for that break. It
  never appears during a focus phase or when the toggle is off.
- [ ] AC12: Break screen actions. Pause holds the break countdown and the button reads Resume;
  Resume continues from the remaining time. The panel shows the same paused state. +5 min adds
  five minutes to the time left in the break, in both the screen and the panel, and is ignored
  once the time left would exceed 180 minutes. Stop ends the break at once and leaves the next
  focus session idle at its full length. Keyboard: Space pause or resume, E extend, S stop,
  Esc hide. The Pac-Man advances with elapsed time, and Pause or +5 min move it accordingly.
- [ ] AC7: Free-form minute fields and the sessions-per-cycle field are no longer in the panel.
- [ ] AC8: A `shell.json` entry written by the current version loads without error: an unknown
  `focusMinutes` value maps to the nearest preset, the obsolete keys (`shortBreakMinutes`,
  `longBreakMinutes`, `sessionsBeforeLongBreak`, `autoStartBreaks`, `autoStartFocus`) are
  ignored, and the saved timer state file from the current version restores as before.
- [ ] AC13: When a phase's countdown reaches zero, the next phase starts running at once
  (break after focus, focus after break), after the notification and chime for the finished
  phase. Reaching zero through Stop, Skip or Reset does not count as finishing.
- [ ] AC14: `omarchy-shell jg.pomodoro chime` plays the chime regardless of the toggle, for
  testing.
- [ ] AC11: The panel shows a count of focus sessions completed; the long-break cycle and its
  per-cycle dots are gone.
- [ ] AC9: Keyboard navigation in the panel reaches the new rows and toggles: Up/Down (j/k)
  moves between rows, Left/Right (h/l) moves within a segmented row, Enter or Space selects.
- [ ] AC10: `omarchy plugin validate` passes and `node Model.test.js` passes, including new
  cases for preset mapping, break-length selection, settings migration, and break extension.

### Decisions and uncertainty

- Accepted decisions and source (owner, 2026-11-04, via the question dialog after inspecting
  mockup A):
  - Visual reference: mockup A accepted. See
    [reference](../visuals/20261104-preset-durations-and-break-screen/reference.md); its
    binding items V1 to V6 are acceptance input.
  - Q1: The "long break every N sessions" cycle is removed. Every break uses the selected
    length. The session dots become a plain count of focus sessions done since the state was
    last reset.
  - Q2 (superseded by Q6): `autoStartBreaks` and `autoStartFocus` are dropped as settings: no
    panel control, keys ignored if present.
  - Q6 (owner, 2026-11-04, after using the plugin): phases chain automatically. A finished
    focus session starts its break at once, so the break screen appears without a click; a
    finished break starts the next focus session at once. Pause, Stop, Skip and Reset stay
    manual. This resolves review finding 3.
  - Q3: The break screen is dismissable: Esc, the Hide action, or a click outside its content
    hides it for the rest of that break. The end of the break removes it.
  - Q5 (owner, 2026-11-04): the break screen gains Pause, +5 min, and Stop. Stop replaces the
    earlier Skip action on the screen, since both end the break; the panel keeps its Skip
    button.
- Assumptions and unresolved questions:
  - Q5 detail (assumption): "Stop" means end the break now and leave the next focus session
    idle, the same outcome as the panel's Skip during a break. If Stop should instead hold the
    break at its start (pause plus reset), say so before implementation.
  - Q4 (assumption, owner may override): the chime is the system sound
    `/usr/share/sounds/freedesktop/stereo/complete.oga` played with `pw-play`; both exist on
    this machine. No sound file is bundled.
  - Technical: whether the break screen is an `overlay` entry point in the manifest or a
    window owned by the service. Routine; decided during implementation unless it changes
    observable behavior.

### TDD policy

- Level: targeted
- Selected by user: owner, 2026-11-04, question dialog in this session.
- Test-first behaviors (in `Model.test.js`): mapping any `focusMinutes` value to the nearest
  preset of 15/25/50/90; break-length selection from the `breakLength` setting; settings
  migration that ignores the obsolete keys; the pure gating predicates for chime and break
  screen (phase, toggle, running); extending a break by five minutes with the 180 minute cap.
  QML rendering is verified manually with captures.
- Required regression coverage: existing Model tests stay green; state restore cases unchanged.

## Execution

- Approach: keep the service/widget split. `Model.js` gains the preset and break-length
  model, settings migration, break extension, and the gating predicates, all test-first.
  `Service.qml` stores the phase duration in the state (needed for +5 min), drops the cycle
  and auto-start, adds `extend()` and `stop()`, plays the chime, and owns one full-screen
  break window per monitor (`BreakScreen.qml`, instantiated per `Quickshell.screens`).
  `Panel.qml` rebuilds its lower half with two `ButtonGroup` rows and three `Toggle`s.
  State file moves to `version: 2`; a version 1 file is migrated on read.
- Open technical question: whether a `PanelWindow` created from a service with no visual
  parent maps correctly on every monitor. Checked at the first restart; fallback is an
  `overlay` entry point.
- Verification: `node Model.test.js` → all pass; `omarchy plugin validate .` → exit 0;
  `omarchy restart shell` then `omarchy-shell jg.pomodoro status` → JSON with the new fields;
  IPC `extend`, `stop`, `pause` on a running break → status reflects each; captures of the
  panel (focus, break, idle) and of the break screen on both monitors compared against
  V1 to V7; `journalctl --user` shows no QML errors for the plugin.
- Independent review: required (persistent state migration). A fresh reviewer agent gets the
  diff, the agreement, and the evidence after verification.

### T1: Model behaviors, test-first

- Acceptance criteria: AC1 (preset set), AC3 (break length), AC8 (migration), AC12 (extend cap), AC10.
- Verification: new tests fail before the Model change (red), pass after (green).
- [x] Complete — evidence: Evidence, "Checks and outcomes", red/green.

### T2: Service, panel, break screen, strings, manifest, README

- Acceptance criteria: AC1–AC9, AC11, AC12; V1–V7.
- Dependencies: T1.
- Verification: as listed above after `omarchy restart shell`.
- [x] Complete — evidence: Evidence, "Checks and outcomes", desktop checks.

## Evidence

- Checks and outcomes (2026-11-04, this machine, Quickshell 0.3.2, two monitors DP-1 3440x1440 and DP-3 1920x1080):
  - Red: `node Model.test.js` with the new tests against the old model failed at the first
    new case (`FOCUS_PRESETS` undefined). Green: after the Model change, 13 tests pass.
  - `omarchy plugin validate .` → exit 0.
  - Migration (AC8): the state file before the restart was `version: 1`
    (`{"version":1,"phase":"focus",...,"completedFocus":2}`); after `omarchy restart shell`
    `status` reported the same phase and count, and the next state change wrote
    `version: 2` with `durationMs`. The `shell.json` entry carried no obsolete keys at the
    time; obsolete-key handling is covered by the settings test.
  - IPC on a running break (AC12): `extend` → remaining 05:00 → 09:59, duration 600000;
    `pause` → paused true, remaining held; `stop` → phase focus, idle, 25:00, break window
    gone. `hideBreakScreen` → layer count 0 while the break kept running.
  - Break screen (AC6): with `breakScreen` true, `hyprctl layers` listed one
    `jg-pomodoro-break` surface per monitor (3440x1440 and 1920x1080) during a running break
    and none in focus or after stop. Screenshots of both monitors show phase, countdown,
    Pac-Man dot row, three buttons, and the Esc hint (V5, V7).
  - Panel (AC1, AC3, AC4, AC7, AC11; V1–V4, V6): screenshots in idle, focus running, and
    break running show hero without icon, progress bar, session count, actions, Focus chips
    15/25/50/90 with 25 selected, Break chips Short/Long, and the three toggles; no minute
    fields.
  - Keyboard (AC9), driven with `wtype` while the panel held focus: `j j l Enter` set
    `focusMinutes` to 50; `j l Enter` set `breakLength` to long; `j j Space` set `chime`
    true; Esc closed the panel. Settings were then restored to defaults.
  - Chime (AC5): `pw-play /usr/share/sounds/freedesktop/stereo/complete.oga` exits 0 on this
    machine; the end-of-session path is gated by `Model.shouldChime` (tested) and runs through
    a `Process` with an argv array. Not heard end to end in this session.
  - Shell log for the current shell process after the final restart: no errors or warnings
    for the plugin. An earlier iteration logged "Cannot specify ... centerIn anchors for items
    inside Column" from BreakScreen.qml; fixed by wrapping the content column in an Item.
- Review (independent reviewer agent, fresh context, given the spec, the reference, and the
  diff; 10 findings):
  1. Confirmed: v1 migration could leave `remainingMs > durationMs`, so a paused session read
     as idle and was reset by the first settings push. Fixed: `parseState` sets
     `durationMs = max(durationMs, remainingMs)`; tests added (v1 paused focus 40 min, v1
     running long break, inconsistent v2).
  2. Plausible: break-screen keyboard focus tied to `visible`. Fixed: constant
     `WlrKeyboardFocus.OnDemand`. Verified with `wtype`: Esc hid both windows; E, Space, S
     acted on the break (extend to 09:59, paused with the screen still up, stop to focus).
  3. Design: with auto-start dropped, the break screen appears only after Start. Matches AC6
     as written; raised to the owner as a decision (see handoff).
  4. Plausible: no way to reset the session count. Fixed: IPC `resetCount`; Reset on a focus
     phase already at its start clears the count. README updated.
  5. Confirmed: Space with an unplaced cursor did nothing. Fixed: acts on the first control
     (start/pause). Verified with `wtype`.
  6. Confirmed: a far-future `endsAt` could overflow the int remaining. Fixed: a running state
     ending more than 180 minutes ahead is discarded; test added.
  7. Confirmed: Pac-Man canvas did not repaint on theme change. Fixed: fill read through a
     property with `onFillChanged: requestPaint()`.
  8. Confirmed: two translated phrases glued with " · ". Fixed: three `Text` items in a Row.
  9. Confirmed: dead members and obsolete keys copied forward. Fixed: removed `onBreak` and
     `phaseCompleted`; break options from `Model.BREAK_LENGTHS`; settings writes keep only
     known keys; plain initial values with a comment.
  10. Confirmed: test gaps. Fixed: preset ties, extend with duration at the cap, migration and
     far-future cases; 15 tests pass.
  Re-verified after the fixes and a shell restart: 15 tests, validate exit 0, IPC start, pause,
  extend, stop, resetCount, break windows on both monitors, clean shell log.
- Auto-start (AC13, 2026-11-04 14:03): a state file with a focus session ending 15 s ahead was
  loaded by a shell restart; when it reached zero the service entered the break running
  (`05:00`, `completedFocus` 1, `breakScreenShown` true) and both break windows mapped. The
  chime process logged "started" and "played" (exit 0) at that completion and again on
  `omarchy-shell jg.pomodoro chime` (AC14). The owner reported hearing no chime at 13:59 with
  the toggle on; the notification history shows that completion fired. Whether the sound is
  audible is for the owner to confirm; the process path is verified.
- Unexplained observation: once, after the key sequence E, Space, S on the break screen, the
  focus phase came back at 15:00 instead of 25:00. Four replays of that and related sequences,
  and the IPC equivalent, all returned 25:00. Not reproduced; noted for the owner's acceptance
  run.
- Remaining verification and limitations: break-screen key handling (Space, E, S, Esc) and
  the audible chime are not exercised by automation; the owner's acceptance covers them.
  Horizontal-bar rendering untested (the owner's bar is vertical).
- Changes: `Model.js`, `Model.test.js`, `Service.qml`, `Panel.qml`, new `BreakScreen.qml`,
  `i18n/en.json`, `manifest.json` (1.1.0), `README.md`, plus this record and the queue.

## Current handoff

- Authorized work: implementation of this spec, owner's `/lusona:implement` on 2026-11-04.
  Commits of verified increments included. Push not separately authorized yet.
- Completed and remaining work: T1 and T2 implemented, reviewed, fixed, and re-verified on the
  desktop; committed. Remaining: owner acceptance; owner decision on review finding 3; push
  (needs authority).
- Human acceptance and delivery: pushed to https://github.com/johanns/omarchy-pomodoro as
  `9061f23` on the owner's instruction ("commit and push it", 2026-11-04). Explicit acceptance
  of the behavior and the decision on review finding 3 are still open.
- Resume context: repository `~/.config/omarchy/plugins/jg.pomodoro`, branch `main` at
  `df42b41`; spec and visuals uncommitted.
- Try it: open the panel from the bar; pick 50 under Focus and Long under Break; turn on
  Break screen; click Skip then Start; every monitor shows the break view; press E (10:00),
  Space (paused), S (back to Focus, ready).
- Next action: owner confirms the chime is audible (it played twice at 14:03) and accepts;
  push needs authority.
