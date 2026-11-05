# Pomodoro for the Omarchy shell

Plugin id: `jg.pomodoro`. A focus/break countdown in the bar with a control panel.

Focus sessions of 15, 25, 50 or 90 minutes, breaks of 5 (short) or 15 (long)
minutes, picked with one tap in the panel. When a session ends the plugin can send
a desktop notification, play a chime, and cover every monitor with a break screen.

## Install

```
omarchy plugin add https://github.com/johanns/omarchy-pomodoro.git --enable
```

Then place it: `omarchy plugin enable jg.pomodoro centerEnd` (or any of `left`,
`centerBegin`, `centerEnd`, `right`, `tray`). Update later with `omarchy plugin update jg.pomodoro`.

Requires Omarchy with the Quickshell shell (`omarchy-shell`).

## Files

| File | Role |
|------|------|
| `manifest.json` | Plugin manifest (`service` + `bar-widget` kinds) |
| `Service.qml` | The single timer. Holds phase, remaining time, completed sessions; sends notifications; saves state |
| `Panel.qml` | Bar widget and `KeyboardPanel` with controls and settings |
| `BreakScreen.qml` | Full-screen break view, one window per monitor, driven by the service |
| `Model.js` | Pure logic: settings bounds, phase order, formatting, state (de)serialization |
| `Model.test.js` | `node Model.test.js` runs the logic tests |
| `i18n/en.json` | Strings. Add `<code>.json` per Omarchy language code |

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
break. Skip ends the break and leaves the next focus session ready. Reset restarts
the break at its full length, stopped, which also removes the screen.

## Chime

With the Chime toggle on, the system sound
`/usr/share/sounds/freedesktop/stereo/complete.oga` plays through `pw-play` when a
session ends. A missing player or file is logged and otherwise ignored. Test it with
`omarchy-shell jg.pomodoro chime`.

## Phase changes

A finished focus session starts its break at once, and a finished break starts the
next focus session at once. Pause, Skip and Reset remain manual.

## IPC

```
omarchy-shell jg.pomodoro toggleTimer   # start or pause
omarchy-shell jg.pomodoro start
omarchy-shell jg.pomodoro pause
omarchy-shell jg.pomodoro reset         # back to the start of the phase
omarchy-shell jg.pomodoro skip          # next phase
omarchy-shell jg.pomodoro stop          # same as skip; ends a break
omarchy-shell jg.pomodoro extend        # five more minutes, up to 180 left
omarchy-shell jg.pomodoro hideBreakScreen
omarchy-shell jg.pomodoro resetCount    # focus sessions done back to 0
omarchy-shell jg.pomodoro chime         # play the chime now
omarchy-shell jg.pomodoro toggle        # open or close the panel
omarchy-shell jg.pomodoro status        # JSON
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

| Key | Default | Values |
|-----|---------|--------|
| `focusMinutes` | 25 | 15, 25, 50, 90 (other numbers snap to the nearest) |
| `breakLength` | `short` | `short` (5 min), `long` (15 min) |
| `notify` | true | |
| `chime` | false | |
| `breakScreen` | false | |

Keys from version 1.0 (`shortBreakMinutes`, `longBreakMinutes`,
`sessionsBeforeLongBreak`, `autoStartBreaks`, `autoStartFocus`) are ignored. A
version 1.0 state file is migrated on the first start.

## Development

Saving `i18n/*.json` applies at once: the catalogs are watched files. Edits to
`Panel.qml`, `Service.qml` or `Model.js` need `omarchy restart shell`. The shell
does rescan the plugin on save, but Quickshell 0.3.2 does not expose
`Qt.clearComponentCache`, so the rescan rebuilds the widget from the cached
component and the saved change does not show.

Run the logic tests with `node Model.test.js`.
