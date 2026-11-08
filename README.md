# Pomodoro for the Omarchy shell

Plugin id: `jg.pomodoro`. A focus/break countdown in the bar with a control panel.

Focus sessions of 15, 25, 50 or 90 minutes, breaks of 5 (short) or 15 (long)
minutes, picked with one tap in the panel. Each finished phase starts the next one.
When a session ends the plugin can send a desktop notification, play a chime, and
cover every monitor with a break screen, pausing any media that plays under it.
While the session is locked, focus time pauses.

## Install

```
omarchy plugin add https://github.com/johanns/omarchy-pomodoro.git --enable
```

Then place it: `omarchy plugin enable jg.pomodoro centerEnd` (or any of `left`,
`centerBegin`, `centerEnd`, `right`, `tray`). Update later with `omarchy plugin update jg.pomodoro`.

Requires Omarchy with the Quickshell shell (`omarchy-shell`).

## Files

| File                   | Role                                                                                                |
| ---------------------- | --------------------------------------------------------------------------------------------------- |
| `manifest.json`        | Plugin manifest (`service` + `bar-widget` kinds)                                                    |
| `Service.qml`          | The single timer. Holds phase, remaining time, completed sessions; sends notifications; saves state |
| `Panel.qml`            | Bar widget and `KeyboardPanel` with controls and settings                                           |
| `BreakScreen.qml`      | Full-screen break view, one window per monitor, driven by the service                               |
| `Model.js`             | Pure logic: settings bounds, phase order, formatting, state (de)serialization                       |
| `Model.test.js`        | `npm test` runs the logic tests                                                                     |
| `tests/lock-trials.py` | Runs the "Pause when locked" cases against the live shell through the test IPC methods              |
| `i18n/en.json`         | Strings. Add `<code>.json` per Omarchy language code                                                |
| `package.json`         | Development scripts and the Biome dev dependency; not needed to run the plugin                      |
| `biome.json`           | Biome format and lint rules for JS, JSON and HTML                                                   |
| `.qmlformat.ini`       | qmlformat settings for the QML files                                                                |

The timer lives in the service, not the widget, because the bar builds one
widget per monitor. Runtime state is saved to
`~/.local/state/omarchy/pomodoro.json` and restored on shell start, so a
running session survives `omarchy restart shell`.

## Bar widget

- Left click: open or close the panel
- Right click: start or pause
- Middle click: skip to the next phase
- Horizontal bar: glyph plus `mm:ss`. Vertical bar: glyph with minutes left under it

Reset returns to the start of the current phase at its configured length. Pressing
Reset on a focus phase that is already at its start clears the session count.

## Panel keys

Space start/pause, R reset, S or N skip, Esc close, j/k or arrows move between rows,
h/l move along a row of chips, Enter or Space activates the chip, button, or toggle.

## Break screen

With the Break screen toggle on, every monitor shows the break countdown while a
break runs or is paused: the phase, the time left, a Pac-Man progress row, and
the panel's buttons with the same keys: Pause/Resume (Space), Reset (R), Skip (S or
N), plus +5 min (E). Esc or a click on the backdrop hides it for the rest of that
break. Skip ends the break and starts the next focus session. Reset restarts the
break at its full length, stopped, which also removes the screen.

## Chime

With the Chime toggle on, the system sound
`/usr/share/sounds/freedesktop/stereo/complete.oga` plays through `pw-play` when a
session ends. A missing player or file is logged and otherwise ignored. Test it with
`omarchy-shell jg.pomodoro chime`.

## Phase changes

A finished focus session starts its break at once, and a finished break starts the
next focus session at once. Skip on a break also starts the next focus session; Skip
on a focus session leaves the break that follows ready but stopped. Pause and Reset
remain manual.

## Pause when locked

With the Pause when locked toggle on (the default), the plugin asks the shell
whether the session is locked (`omarchy-shell lock isLocked`) once a minute while a
focus session runs or is held. It does not watch mouse or keyboard activity.

- A running focus session pauses at the first check that finds the session locked.
  Up to a minute of locked time can count against it.
- A break that ends while the session is locked leaves the next focus session at its
  full length, stopped. The break end reads the lock state at that moment, so this
  also covers a break that ran out during a suspend. Breaks keep running while locked.
- The first check after you unlock continues the paused session or starts the held
  one, up to a minute after you log in.
- Start, Pause, Skip or Reset on a paused or held session hands it back to you: it is
  no longer continued on unlock. Turning the toggle off does the same.
- If the lock state cannot be read, the plugin logs a warning and treats the session
  as unlocked.

`status` reports the toggle as `pauseWhenLocked` and a session paused or held by the
lock as `lockHeld`.

### Testing without locking the screen

Three IPC methods let you try the lock behavior in seconds:

```sh
omarchy-shell jg.pomodoro simulateLock locked    # every lock read answers "locked"
omarchy-shell jg.pomodoro simulateLock unlocked  # every lock read answers "unlocked"
omarchy-shell jg.pomodoro simulateLock off       # read the real lock state again
omarchy-shell jg.pomodoro checkLock              # run the once-a-minute check now
omarchy-shell jg.pomodoro finishPhase            # end the current phase as if it ran out
```

The simulated state is not saved; a shell restart returns to the real lock state.
`status` reports it as `simulatedLock`. `python3 tests/lock-trials.py` runs every
case through these methods and reports pass or fail; it changes the live timer and
saves the state file first. Turn Pause media off before running it, or it pauses
your media, and the locked case leaves it paused.

## Pause media

With the Pause media toggle on, every media player that is playing (any MPRIS
player: browsers, Spotify, mpv, and so on) pauses when the break screen appears.
It needs the Break screen toggle on as well; without the break screen nothing is
paused.

When the break screen goes away, the players the plugin paused resume. That covers
the break running out, Esc or a click on the backdrop, Skip, Reset, and turning the
Break screen toggle off. A player you started again yourself, or one that has quit,
is left alone. Players the plugin did not pause are never touched.

With "Pause when locked" on, a break that runs out while the session is locked
resumes nothing: the players stay paused for you to start. Unlocking does not
resume them either.

The paused players are saved with the timer state, so a shell restart during a
break still resumes them when the break screen goes away. If the break ended while
the shell was down, they stay paused. For three seconds after the shell starts,
media is left alone while the player list and settings load. A player that starts
while the break screen is already up is not paused. Players are recorded by bus
name; after a reboot during a paused break, a player that registers the same name
(for example Spotify) is resumed when that break screen goes away.

`status` reports the toggle as `pauseMedia` and the paused players' bus names as
`mediaPaused`.

## IPC

```
omarchy-shell jg.pomodoro toggleTimer   # start or pause
omarchy-shell jg.pomodoro start
omarchy-shell jg.pomodoro pause
omarchy-shell jg.pomodoro reset         # back to the start of the phase
omarchy-shell jg.pomodoro skip          # next phase; on a break, starts focus
omarchy-shell jg.pomodoro stop          # same as skip
omarchy-shell jg.pomodoro extend        # five more minutes, up to 180 left
omarchy-shell jg.pomodoro hideBreakScreen
omarchy-shell jg.pomodoro resetCount    # focus sessions done back to 0
omarchy-shell jg.pomodoro chime         # play the chime now
omarchy-shell jg.pomodoro toggle        # open or close the panel
omarchy-shell jg.pomodoro status        # JSON
omarchy-shell jg.pomodoro simulateLock locked|unlocked|off  # testing, see above
omarchy-shell jg.pomodoro checkLock     # testing: run the lock check now
omarchy-shell jg.pomodoro finishPhase   # testing: end the current phase now
```

For a Hyprland keybinding in `~/.config/hypr/bindings.lua`, use the command string
directly. The `ipc = "target.method"` form splits at the first dot and does not
work with a dotted plugin id.

```lua
o.bind("SUPER ALT, P", "omarchy-shell jg.pomodoro toggleTimer", "Pomodoro start/pause")
```

## Settings

Stored inline on the bar entry in `~/.config/omarchy/shell.json`, written by the
panel. Values outside the bounds are clamped.

| Key               | Default | Values                                             |
| ----------------- | ------- | -------------------------------------------------- |
| `focusMinutes`    | 25      | 15, 25, 50, 90 (other numbers snap to the nearest) |
| `breakLength`     | `short` | `short` (5 min), `long` (15 min)                   |
| `notify`          | true    |                                                    |
| `chime`           | false   |                                                    |
| `breakScreen`     | false   |                                                    |
| `pauseWhenLocked` | true    |                                                    |
| `pauseMedia`      | false   |                                                    |

Keys from version 1.0 (`shortBreakMinutes`, `longBreakMinutes`,
`sessionsBeforeLongBreak`, `autoStartBreaks`, `autoStartFocus`) are ignored. A
version 1.0 state file is migrated on the first start.

## Development

Tools: Node.js and npm for the scripts below (`npm install` installs Biome 2.6.6),
and the Qt 6 QML tools from `qt6-declarative`, which Omarchy already installs. The
`qmlformat` and `qmllint` on `PATH` may be the Qt 5 versions from
`qt5-declarative`; the scripts call the Qt 6 ones in `/usr/lib/qt6/bin`.

| Command              | What it does                                                                  |
| -------------------- | ----------------------------------------------------------------------------- |
| `npm test`           | Runs the logic tests in `Model.test.js` under node                            |
| `npm run format:js`  | Formats JS, JSON and HTML with Biome                                          |
| `npm run lint:js`    | Lints JS, JSON and HTML with Biome and applies its safe fixes                 |
| `npm run format:qml` | Formats the QML files in place with qmlformat                                 |
| `npm run lint:qml`   | Lints the QML files with qmllint against the shell's `qs.Commons` and `qs.Ui` |

Before a commit, `npx biome check .` reports no errors and `npm test` passes.

Code standards:

- JS, JSON and HTML: Biome's recommended rules, tab indentation, double quotes,
  semicolons. Every `if`, `else` and loop body has braces (`useBlockStatements` is
  an error). Biome formats `docs/` but does not lint it.
- `Model.js` runs in Qt's QML JavaScript engine as well as node. Use only language
  features that Qt 6's engine supports, and check new ones under `qml6`; for
  example, `Object.hasOwn` is undefined in Qt 6.12. For this file Biome's
  `noUnusedVariables` is off (QML reads its top-level declarations through the
  import) and `noPrototypeBuiltins` is off (its fix uses `Object.hasOwn`).
- QML: qmlformat with `.qmlformat.ini`: 2-space indentation as in Omarchy's shell,
  semicolons, no column limit. qmlformat does not add braces, so write `if` bodies
  with braces by hand.
- qmllint needs the shell's modules under a `qs` directory; `lint:qml` links
  `.qml-imports/qs` to `/usr/share/omarchy/shell` (ignored by git). It exits 0 with
  warnings. The current `missing-property` warnings on `QObject` and the
  `uncreatable-type` warning on `PanelWindow` come from the shell's and
  Quickshell's type information. The `unqualified` warnings are references from
  nested components to outer ids, fixed by `pragma ComponentBehavior: Bound` and
  required properties.

Saving `i18n/*.json` applies at once: the catalogs are watched files. Edits to
`Panel.qml`, `Service.qml` or `Model.js` need `omarchy restart shell`. The shell
does rescan the plugin on save, but Quickshell 0.3.2 does not expose
`Qt.clearComponentCache`, so the rescan rebuilds the widget from the cached
component and the saved change does not show.

After `omarchy restart shell`, `python3 tests/lock-trials.py` checks the lock
behavior in the live shell; it changes the timer, saves the state file first, and
prints the command to restore it.
