# Pomodoro for the Omarchy shell

Plugin id: `jg.pomodoro`. A focus/break countdown in the bar with a control panel.

Default cycle: 25 minute focus, 5 minute short break, 15 minute long break after
every 4 focus sessions. A desktop notification is sent when a session ends.

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

## Panel keys

Space start/pause, R reset, S or N skip, Esc close, j/k or arrows move the cursor,
h/l adjust a duration field, Enter or Space activates a button or toggle.

## IPC

```
omarchy-shell jg.pomodoro toggleTimer   # start or pause
omarchy-shell jg.pomodoro start
omarchy-shell jg.pomodoro pause
omarchy-shell jg.pomodoro reset         # back to the start of the phase
omarchy-shell jg.pomodoro skip          # next phase
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

| Key | Default | Bounds |
|-----|---------|--------|
| `focusMinutes` | 25 | 1–180 |
| `shortBreakMinutes` | 5 | 1–60 |
| `longBreakMinutes` | 15 | 1–120 |
| `sessionsBeforeLongBreak` | 4 | 1–12 |
| `autoStartBreaks` | false | |
| `autoStartFocus` | false | |
| `notify` | true | |

## Development

Saving `i18n/*.json` applies at once: the catalogs are watched files. Edits to
`Panel.qml`, `Service.qml` or `Model.js` need `omarchy restart shell`. The shell
does rescan the plugin on save, but Quickshell 0.3.2 does not expose
`Qt.clearComponentCache`, so the rescan rebuilds the widget from the cached
component and the saved change does not show.

Run the logic tests with `node Model.test.js`.
