# Pomodoro for macOS: specification

Version 1.1, 2026-11-05. Owner: Johanns Gregorian.

Target: a native macOS menu bar app with functional parity to the Omarchy shell plugin
`jg.pomodoro` as of commit `958728f` (https://github.com/johanns/omarchy-pomodoro), distributed through
the Mac App Store. This document is complete enough to build the app from; it does not
assume knowledge of Omarchy. Where it says "the reference", it means the Omarchy plugin's
`Model.js` and `Model.test.js`, whose rules and test vectors are reproduced in sections 4 and 12.

Product context: `docs/lusona/product.md`.

## 1. Summary

- A menu bar item shows the current phase and the time left. Clicking it opens a panel.
- Two phases alternate: focus and break. A finished phase starts the next one by itself.
- Focus length is one of 15, 25, 50, 90 minutes. Break length is Short (5) or Long (15).
- When a phase ends the app can post a notification, play a chime, and, for breaks, cover
  every display with a break screen that has the panel's Pause/Resume, Reset, and Skip,
  plus +5 min.
- State survives relaunch and sleep. No network, no account, no sync, no analytics.

## 2. Decisions and constraints

| Topic           | Decision                                                                                                                                     | Source                  |
| --------------- | -------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------- |
| Language and UI | Swift 5.10+, SwiftUI for panel and break-screen content, AppKit where SwiftUI lacks control (status item, windows per display, key handling) | owner, 2026-11-04       |
| Distribution    | Mac App Store: App Sandbox on, hardened runtime, privacy manifest, no network entitlement                                                    | owner                   |
| Minimum macOS   | 14.0 (Sonoma). Proposal; allows `MenuBarExtra` window style, `SMAppService`, String Catalogs                                                 | spec author, to confirm |
| Architecture    | Universal binary (arm64 + x86_64)                                                                                                            | spec author             |
| Parity          | Functional parity with the plugin. No Omarchy concepts (no plugin manifest, no shell IPC, no `shell.json`)                                   | owner                   |
| Shared state    | None. Each machine has its own timer and settings                                                                                            | owner                   |
| Behavior rules  | Section 4 is normative; the test vectors in section 12 must pass                                                                             | reference               |

## 3. Glossary

- Phase: `focus` or `break`.
- Preset: one of the four focus lengths.
- Break length: `short` (5 min) or `long` (15 min).
- Duration: how long the current phase lasts, in milliseconds. Grows with +5 min.
- Remaining: milliseconds left in the current phase.
- Running: the countdown is ticking. Paused: not running and remaining < duration.
  Engaged: running or paused. Idle: not running and remaining == duration.
- Session count: focus sessions completed since the last count reset.

## 4. Behavior rules (normative)

All times are milliseconds. `MINUTE = 60_000`.

### 4.1 Settings

| Key            | Type   | Default | Values                                                                                                                                    |
| -------------- | ------ | ------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `focusMinutes` | Int    | 25      | 15, 25, 50, 90. Any other number snaps to the nearest preset; a tie goes to the lower one (20 → 15, 37.5 → 25, 70 → 50). Non-numbers → 25 |
| `breakLength`  | String | `short` | `short` (5), `long` (15). Anything else → `short`                                                                                         |
| `notify`       | Bool   | true    |                                                                                                                                           |
| `chime`        | Bool   | false   |                                                                                                                                           |
| `breakScreen`  | Bool   | false   |                                                                                                                                           |

Settings are read through a normalizer that applies these bounds before any use. Unknown
keys are ignored.

### 4.2 Phase lengths and order

- Phase length: focus → `focusMinutes * MINUTE`; break → 5 or 15 minutes by `breakLength`.
- `advance(phase, count)`: focus → break with `count + 1`; break → focus with `count`
  unchanged. Count is bounded to [0, 100000].
- Completion (countdown reaches zero while running): post notification if `notify`, play
  the chime if `chime`, enter the next phase, then start it at once. Both directions chain
  automatically.
- Skip: enter the next phase idle (not running). A skipped focus session does not add to
  the count.
- Reset: back to the start of the current phase at its configured length, not running. If
  the phase is focus and already idle at its start, Reset also sets the session count to 0.
- Reset count: sets the session count to 0 (separate action, see 6.2).

### 4.3 Start, pause, extend

- Start: if remaining ≤ 0, remaining = duration. `endsAt = now + remaining`, running = true.
- Pause: remaining = `endsAt − now` (≥ 0), running = false, endsAt = 0.
- Tick: every second while running, remaining = `endsAt − now`; when ≤ 0, complete. The
  countdown is always recomputed from `endsAt`, never decremented, so sleep and clock
  changes are handled by the next tick.
- Extend (+5 min): if `remaining + 5 min > 180 min`, do nothing. Otherwise
  remaining += 5 min and duration = min(180 min, duration + 5 min). If running,
  `endsAt = now + remaining`. Allowed in any phase; the UI exposes it on the break screen.
- Progress fraction = `1 − min(remaining, duration) / duration`, in [0, 1]; 0 when duration
  is 0.

### 4.4 Settings changes while a phase is on

- Changing a length while the current phase is idle at its start applies at once: duration
  and remaining become the new length.
- Changing a length while running or paused does not change the current phase; the next
  phase of that kind uses it.

### 4.5 Break screen visibility

`shown = phase == break && engaged && settings.breakScreen && !hiddenForThisBreak`.

- `hiddenForThisBreak` is set by Esc, the backdrop click, or an explicit hide, and cleared
  whenever a new phase is entered. So a hidden screen stays hidden for the rest of that
  break and returns for the next one.
- Never shown during focus, never when the toggle is off, never while idle.

### 4.6 Persistence

State file (JSON), written on every state change except ticks:

```json
{
	"version": 2,
	"phase": "focus",
	"running": false,
	"endsAt": 0,
	"durationMs": 1500000,
	"remainingMs": 1500000,
	"completedFocus": 2,
	"savedAt": 1793827798441
}
```

- `endsAt` is a Unix epoch in milliseconds, 0 when not running. `savedAt` is informational.
- On launch: parse with bounds. Unknown or malformed → fresh state (focus, idle, count 0).
  `phase` must be `focus` or `break`; `version` must be 2. `durationMs` and `remainingMs`
  clamp to [0, 180 min]; `completedFocus` to [0, 100000]. If running: `endsAt` must be a
  finite number > 0 and at most 180 min ahead, else fresh state; remaining =
  `clamp(endsAt − now)`. After that, `durationMs = max(durationMs, remainingMs)`. A
  running state whose end has passed restores with remaining 0 and completes on the
  first tick (with notification and chime, then the next phase starts).
- Location: the app's sandbox container, `Application Support/<bundle id>/state.json`,
  written atomically. Settings live in `UserDefaults` under the keys in 4.1.

### 4.7 Text formatting

- Clock: `mm:ss`, or `h:mm:ss` past one hour, from seconds rounded up (`24:59.001` shows
  `25:00`; 0 or negative shows `00:00`). Digits are localized by the system formatter.
- Short label (menu bar when space is tight): whole minutes rounded up while ≥ 60 s, else
  bare seconds.
- Any text that reaches a system sink (notification, menu bar, accessibility label) is plain
  text; the app never renders markup.

## 5. Menu bar item

- Implemented with `NSStatusItem` (AppKit) hosting a SwiftUI view, or `MenuBarExtra` with
  `.window` style if it can meet every point below; the status item is the safer choice for
  click handling and width control.
- Content: an SF Symbol for the phase, `hourglass` for focus and `cup.and.saucer` for
  break, plus the clock text when engaged (running or paused). Idle: symbol only. Paused:
  the content at reduced opacity (0.6). The width must not jitter as digits change: use a
  monospaced-digit font.
- Click: toggles the panel (5.1). Right-click or Control-click: a context menu with
  Start/Pause, Reset, Skip, a Settings submenu is not needed, and Quit.
- Tooltip (accessibility label too): "Pomodoro: Focus ready", "Pomodoro: Focus, 24:59 left",
  "Pomodoro: Break paused, 04:12 left".
- The app has no Dock icon and no main window (`LSUIElement` true). Quit from the context
  menu or ⌘Q while the panel has focus.

### 5.1 Panel

A popover anchored to the status item, about 360 pt wide, content-sized in height, following
the system appearance (light/dark, accent color, reduce transparency). Order top to bottom
(binding; see the visual reference in the plugin repository,
`docs/lusona/visuals/20261104-preset-durations-and-break-screen/`):

1. Hero: phase name ("Focus" / "Break") in title weight, a small uppercase status line
   under it ("READY", "RUNNING", "PAUSED"), and the clock in large bold monospaced digits
   on the right. No icon.
2. Progress bar: thin track, filled by the progress fraction; at 50% opacity while paused.
3. Session count text: "2 focus sessions done" (pluralized).
4. Action row, three equal-width buttons: Start/Pause/Resume (icon play or pause), Reset,
   Skip. Start reads "Resume" while paused.
5. Key hint line, caption color: "Space start/pause · R reset · S skip".
6. Section "Focus": a segmented control with 15, 25, 50, 90, equal widths, one selected.
   Caption under it: "Minutes per focus session. A running session keeps its end time."
7. Section "Break": a segmented control with "Short · 5 min" and "Long · 15 min".
8. Section "Behavior": three toggles in this order, each with a title and a one-line
   description: Notification ("Send a notification when a session ends."), Chime ("Play a
   short sound when a session ends."), Break screen ("Cover every display during breaks with
   the countdown.").

Interaction:

- Every control is a native SwiftUI control (Button, Picker with segmented style, Toggle),
  so VoiceOver, keyboard focus, and Full Keyboard Access work without custom code.
- Keyboard while the panel is open: Space or Return on the focused control activates it;
  with no control focused, Space toggles start/pause. R resets, S or N skips, Esc closes the
  panel. Arrow keys and Tab move focus per system behavior.
- Selecting a preset or break length persists immediately and applies per 4.4.
- The panel closes on click outside or Esc. It does not need to stay open while running.

## 6. Actions, shortcuts, and the count

### 6.1 In-app

| Action                 | Where                                                   | Rule |
| ---------------------- | ------------------------------------------------------- | ---- |
| Start / Pause / Resume | panel button, break screen button, Space, context menu  | 4.3  |
| Reset                  | panel button, break screen button, R, context menu      | 4.2  |
| Skip                   | panel button, break screen button, S or N, context menu | 4.2  |
| Extend +5 min          | break screen button, E on the break screen              | 4.3  |

The same action has the same name and key on the panel and the break screen.
| Hide break screen | Esc, backdrop click | 4.5 |

### 6.2 Reset count

Reset while focus is idle at its start sets the count to 0 (4.2). Also offer "Reset session
count" in the context menu so the user is not dependent on the double-Reset.

### 6.3 Global shortcut (functional equivalent of the plugin's keybinding hook)

One optional global keyboard shortcut toggles start/pause from any app. Default: none (off).
Configurable from the context menu via a standard shortcut recorder. Implement with
`RegisterEventHotKey` (Carbon), which works under the App Sandbox without Accessibility
permission. If the chosen combination is already taken by the system, show the failure in
the recorder; never fail silently.

## 7. Notifications

- Framework: `UserNotifications`. Request authorization (alert, sound off since the chime is
  separate) the first time the Notification toggle is turned on, not at launch. If denied,
  the toggle shows a footnote "Notifications are off in System Settings" with a button that
  opens the Notifications pane.
- On focus end: title "Focus session done", body "Time for a 5 minute break." (with the
  configured break length). On break end: title "Break over", body "Ready for a 25 minute
  focus session." (with the configured focus length).
- Delivered even when the app is frontmost (`willPresent` returns `.banner`). No actions,
  no attachments, thread identifier "pomodoro" so banners replace each other.

## 8. Chime

- With the Chime toggle on, play a short system sound at phase end: `NSSound(named: "Glass")`
  or a bundled 1 s file (CAF, ≤ 100 KB) if a system sound name is unreliable across versions.
  Use the bundled file if in doubt; the Omarchy plugin plays the freedesktop "complete"
  sound and the two need not be identical.
- Respect the system output volume; no in-app volume control.
- A "Test chime" item in the context menu plays it regardless of the toggle (parity with the
  plugin's test command).

## 9. Break screen

### 9.1 Windows

- One borderless `NSWindow` per `NSScreen`, frame = screen frame, level `.screenSaver`,
  `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`,
  `ignoresMouseEvents = false`, no title bar, not movable, not resizable, excluded from
  Mission Control and window cycling. Rebuild the set on
  `NSApplication.didChangeScreenParametersNotification`.
- Shown and hidden by the single rule in 4.5. Showing uses `orderFrontRegardless()` and
  makes the window on the display with the mouse pointer key for keyboard input. Hiding
  orders all of them out.
- Content: a SwiftUI view with the system background color at 0.94 opacity over the
  display, and a centered column:
  1. "BREAK" in small caps, secondary color.
  2. Clock in very large bold monospaced digits (≈ 72 pt).
  3. Progress row (9.2).
  4. Meta line: "Focus resumes at 1:23 PM · 3 focus sessions done" while running; "Paused ·
     3 focus sessions done" while paused. Time in the user's locale and clock format.
  5. Four buttons in a row, the panel's three in the panel's order, then the break-only
     one: "Pause · Space" (reads "Resume · Space" while paused), "Reset · R",
     "Skip · S", "+5 min · E". Reset and Skip use the panel's icons.
  6. Caption: "Esc hides this screen until the break ends".
- Clicking the backdrop (outside the column) hides; clicks inside the column do not.
- Keys while a break window is key: Esc hide, Space pause/resume, R reset, S or N skip,
  E extend. Reset leaves the break idle at its start, so the screen closes (4.5). Keys are
  handled once even though several windows exist (route through one controller).

### 9.2 Progress row (Pac-Man)

- A row of 16 small dots spans ≈ 384 pt. A Pac-Man (filled circle with a wedge mouth facing
  right, drawn with `Path`, filled with the accent color) sits at `progress × (rowWidth −
  pacSize)`. Dots whose center is behind the Pac-Man's front edge are hidden.
- While running, the mouth opens and closes (0.05–0.35 of a half turn, 220 ms each way,
  ease in-out). Static at 0.35 while paused or when Reduce Motion is on.
- Progress advances with elapsed time; Pause holds it; +5 min moves it back in proportion
  (duration grows).

### 9.3 Must not happen

- The break screen never appears during focus, when the toggle is off, or while idle.
- Esc always hides it. It never captures the screen in a way that blocks ⌘Q, ⌘Tab, or
  Force Quit, and it never changes `NSApplication.presentationOptions`.
- It never appears over the login window or a locked screen; windows are ordered out on
  `NSWorkspace.sessionDidResignActiveNotification` and `screensDidSleepNotification` and
  re-evaluated on the matching wake/active notifications.

## 10. Lifecycle, sleep, and launch at login

- Launch: restore state (4.6); if running, tick immediately; start the 1 s timer only while
  running (no timer while idle or paused; use `Timer` on the main run loop with 0.1 s
  tolerance, or `DispatchSourceTimer`).
- Sleep and wake: on `NSWorkspace.didWakeNotification` tick at once. Because remaining is
  recomputed from `endsAt`, a phase that ended during sleep completes on that tick and the
  next phase starts.
- Launch at login: a toggle in the context menu using `SMAppService.mainApp` (register /
  unregister); reflect the actual status from the service, including "requires approval".
- Quit: persist state first. Relaunch resumes a running countdown where it is.
- Single instance: default macOS behavior is enough; no extra locking.

## 11. Accessibility, localization, appearance

- All text through String Catalogs (`Localizable.xcstrings`), with plural variants for the
  session count. Ship English; keys mirror the plugin's `i18n/en.json` names where
  sensible so translations can be shared later.
- VoiceOver: status item label equals the tooltip; segmented controls announce their
  selection; the break screen's clock is a live region updated once per minute, not per
  second.
- Reduce Motion stops the mouth animation; Increase Contrast and Reduce Transparency are
  honored by using system materials and colors only.
- Appearance: system colors (`Color.primary`, `.secondary`, `Color.accentColor`, window and
  control backgrounds). No custom palette. Dynamic Type is not applicable on macOS; respect
  the user's text size setting in System Settings where SwiftUI does so automatically.

## 12. Model port and test vectors

Put the rules of section 4 in a Swift package `PomodoroCore` with no UI or Foundation-UI
imports, value types, and pure functions, so it is tested without the app. The following
vectors are taken from the reference tests and must pass as XCTest cases.

Presets:

| Input `focusMinutes` | Result     |
| -------------------- | ---------- |
| 25                   | 25         |
| 30                   | 25         |
| 40                   | 50         |
| 200                  | 90         |
| 1                    | 15         |
| "50" (string)        | 50         |
| "abc", nil           | 25         |
| 20, 37.5, 70 (ties)  | 15, 25, 50 |

Settings normalization: `{focusMinutes: 45, breakLength: "long", notify: "false", chime: true,
breakScreen: "true", shortBreakMinutes: 7, autoStartBreaks: true}` →
`{50, long, notify false, chime true, breakScreen true}`; `nil` → `{25, short, true, false,
false}`; `breakLength: "<b>x</b>"` → `short`.

Phase order: `advance(focus, 0)` → `(break, 1)`; `advance(break, 1)` → `(focus, 1)`;
`advance(focus, 7)` → `(break, 8)`; `advance(break, "x")` → `(focus, 0)`.

Extend (remaining, duration → result): `(4 min, 5 min)` → `(9, 10)`; `(0, 5)` → `(5, 10)`;
`(176, 180)` → nil; `(175, 180)` → remaining 180; `(100, 180)` → `(105, 180)`.

Gating: `shouldShowBreakScreen(break, engaged: true, breakScreen: true, hidden: false)` →
true; hidden true → false; engaged false → false; phase focus → false; toggle off → false.

Clock: `25 min` → `25:00`; `24 min 59.001 s` → `25:00`; `24 min 59 s` → `24:59`; `0` and
`−5` → `00:00`; `1 h 1 min 1 s` → `1:01:01`. Short: `24 min + 1 ms` → `25`; `59 s` → `59`;
`60 s` → `1`.

Fraction: `(60 s, 60 s)` → 0; `(0, 60 s)` → 1; `(30 s, 60 s)` → 0.5; `(90 s, 60 s)` → 0;
`(10, 0)` → 0.

State: serialize `(break, running, endsAt now+90 s, duration 10 min, remaining 90 s, count 2)`
and parse at `now + 30 s` → remaining 60 s, duration 10 min, count 2, endsAt kept. Parse at
`now + 500 s` → running true, remaining 0. `"not json"`, `{"version":2,"phase":"<b>x</b>"}`,
`{"version":3,...}` → fresh. `remainingMs 9e15, durationMs 9e15, completedFocus 1e9` →
180 min, 180 min, 100000. Running with `endsAt: "soon"` → fresh. Paused focus with
remaining 45 min and duration 90 min under default settings → unchanged (45, 90). Inconsistent
`duration 15 min, remaining 20 min` → duration 20 min. Running with `endsAt now + 181 min`
→ fresh; `now + 179 min` → remaining 179 min.

A `version: 1` file is not expected on macOS; parsing it as fresh state is acceptable.

## 13. Project structure

```
Pomodoro.xcodeproj
  Packages/PomodoroCore        # rules of section 4, XCTest with section 12 vectors
  Pomodoro/                    # app target
    App.swift                  # @main, LSUIElement, status item setup
    Timer/SessionController    # one instance: state, ticking, persistence, notifications, chime
    MenuBar/                   # status item view, context menu
    Panel/                     # popover content (section 5.1)
    BreakScreen/               # window controller per display, content view, Pac-Man view
    Settings/                  # UserDefaults-backed settings, global shortcut recorder
    Resources/                 # Localizable.xcstrings, chime.caf, PrivacyInfo.xcprivacy
```

- `SessionController` is the only writer of state; views observe it (`@Observable`).
- No third-party dependencies are required. A shortcut-recorder package is acceptable if
  it is sandbox-safe and MIT/BSD licensed.

## 14. App Store requirements

- Entitlements: `com.apple.security.app-sandbox` only. No network, no file access beyond
  the container, no Accessibility.
- Privacy manifest: no tracking, no required-reason APIs beyond `UserDefaults`
  (`CA92.1`) if the toolchain asks for it. No data collected.
- Category: Productivity. Age rating: 4+. Review notes: explain that the break screen covers
  all displays by design and is dismissed with Esc.
- Notarization and signing through Xcode's App Store distribution; hardened runtime on.
- Launch at login uses `SMAppService`, which is App Store permitted and shows in System
  Settings > General > Login Items.

## 15. Acceptance criteria

- [ ] AC1: Menu bar item shows phase symbol only when idle, symbol plus `mm:ss` when
  running, and the same at reduced opacity when paused; width does not jitter.
- [ ] AC2: The panel matches the order and controls in 5.1; no free-form minute fields.
- [ ] AC3: Focus presets are exactly 15, 25, 50, 90; one is always selected; choosing one
  while idle changes the countdown at once and while engaged leaves it unchanged.
- [ ] AC4: Break length is exactly Short 5 / Long 15 and decides the next break.
- [ ] AC5: Behavior toggles are exactly Notification, Chime, Break screen with defaults
  on, off, off, persisted across relaunch.
- [ ] AC6: A finished focus session starts its break at once; a finished break starts the
  next focus session at once. Skip and Reset never auto-start.
- [ ] AC7: Notifications post with the texts in section 7 when the toggle is on and
  permission is granted; a denied permission is surfaced in the panel.
- [ ] AC8: The chime plays at phase end when on, never when off; "Test chime" plays it.
- [ ] AC9: With Break screen on, every connected display is covered while a break runs or
  is paused; Esc or a backdrop click hides it for that break; Skip ends the break; it never
  appears during focus or when off; plugging a display in or out during a break updates the
  set of windows.
- [ ] AC10: Break screen buttons and keys behave per 6.1; +5 min is ignored past 180 min.
- [ ] AC11: Quit and relaunch resume a running countdown from `endsAt`; a phase that ended
  while quit or asleep completes on the first tick and chains.
- [ ] AC12: `PomodoroCore` tests implement every vector in section 12 and pass.
- [ ] AC13: Reduce Motion stops the Pac-Man animation; VoiceOver reads the status item,
  controls, and break screen clock.
- [ ] AC14: Archive validates for the Mac App Store with the sandbox entitlement only.
- [ ] AC15: Session count increments only on completed focus sessions and resets per 6.2.

## 16. Out of scope

- Shared state between machines, statistics, history, task lists, cloud or iCloud.
- A Dock icon, main window, or Settings window beyond the panel and context menu.
- Custom themes or sounds, a volume control, Focus-mode integration, widgets, Shortcuts
  actions (candidates for later, not promised).

## 17. Open decisions

- Minimum macOS version: 14.0 proposed. Lowering to 13 removes `@Observable`.
- Chime source: system sound "Glass" versus a bundled file. The spec allows either; pick
  the bundled file if "Glass" is missing on any supported version.
- Whether the global shortcut (6.3) ships in version 1 or is deferred. It is the only item
  without a direct counterpart in the panel.
