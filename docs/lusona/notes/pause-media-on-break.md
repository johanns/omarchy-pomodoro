# Notes: pause-media-on-break

Context: owner question (`/lusona:investigate`, 2026-11-07): "can we send a stop media when
the break starts?" Read as: pause media playback (MPRIS) when a focus session ends and the
break begins. No spec or queue item yet.

## 2026-11-07 — Can the plugin pause media at break start?

### Finding

Feasible. Two routes exist; both were checked read-only. No pause call was sent, because the
only player on the machine was the owner's Brave tab playing video.

### Evidence

- `omarchy-shell media status` → `{"hasPlayer":true,"playing":true,"identity":"Brave",...,
  "canTogglePlaying":true}`; `omarchy-shell media ping` → `ok`. `busctl --user list` shows one
  MPRIS name, `org.mpris.MediaPlayer2.brave.instance3997782`.
- The shell's media service (`~/.local/share/omarchy/shell/plugins/services/media/Service.qml`)
  exposes IPC target `media` with `pause`, `play`, `playPause`, `status`. `pause` acts on one
  player: the oldest playing one (`playerForAction`), calls `player.pause()` or
  `togglePlaying()`, returns `ok` or `unhandled`, and always shows the media OSD
  (`runAction(..., true)`).
- A standalone Quickshell probe (`qs -p`, file removed after the run) importing
  `Quickshell.Services.Mpris` listed `Brave | playing=true canPause=true canTogglePlaying=true`.
  The player list arrives asynchronously: reading `Mpris.players.values` once, 5 s after
  start, with no earlier binding, returned 0 players; a `readonly property` bound at load
  received 1 player within 4 s.
- `playerctl` is not installed.

### Routes

| Route                                                                                      | Players paused       | OSD          | Notes                                                                                                |
| ------------------------------------------------------------------------------------------ | -------------------- | ------------ | ---------------------------------------------------------------------------------------------------- |
| A. `Quickshell.execDetached(["omarchy-shell", "media", "pause"])`                          | One (oldest playing) | Always shown | Omarchy's own media keys call the same IPC target (`default/hypr/bindings/media.lua`)                |
| B. `import Quickshell.Services.Mpris` in `Service.qml`, pause each player with `isPlaying` | All playing          | None         | Same calls the shell's media service makes; needs a property bound to `Mpris.players.values` at load |

Recommendation: route B, pending the live import check below. It pauses every playing source
(browser plus music app) and shows no OSD. Route A is the fallback; its known limits are one
player only and an OSD on every break.

MPRIS also has `Stop()`, which some players treat as "clear the track and position". These
notes read "stop media" as pause; the owner has not confirmed that.

### Unconfirmed

- Inference, not run: `player.pause()` from this plugin's service pauses Brave. Basis: the
  plugin runs in the same Quickshell process as the shell's media service, which uses the same
  call for the keyboard media keys.
- Inference, not run: the Mpris import loads inside this third-party plugin. Basis: the shell's
  own media plugin imports it, and this plugin already imports `Quickshell.Io`. The qmlscanner
  log line seen earlier (module path outside the config folder) did not stop `Quickshell.Io`.
  Check: temporary import plus one `console.log` of the player count in `Service.qml`, let the
  plugin reload, read the shell log, revert. This reloads the owner's live shell.

### Player identity for saving (2026-11-07)

- Read-only `qs -p` probe: Brave reports `dbusName=org.mpris.MediaPlayer2.brave.instance3997782
  uniqueId=1 identity=Brave desktopEntry=` (empty). `uniqueId` is a per-process counter, so
  `dbusName` is the key to save. The shell's media service keys players the same way
  (`MediaModel.playerKey`: `dbusName || desktopEntry || identity`).
- Resume only players whose `dbusName` is in the saved list and that are not playing. A player
  that exited is skipped.

### Live import check (2026-11-07)

- Added `import Quickshell.Services.Mpris` and a logging property to `Service.qml`, then
  restored the original file (byte-identical, `git diff` empty).
- The shell logged `Local plugin changed, reloading: jg.pomodoro`, but its load log has no
  new read of `Service.qml` and no diagnostic line. The running service was not recreated by
  the file change; the timer kept running (29:09 left after restore). The check needs
  `omarchy restart shell` and was not completed.
- `grep` of `/usr/share/omarchy/shell` for import allow or block lists found none. Two
  first-party plugins import `Quickshell.Services.Mpris` (media service, audio panel).

### Owner

Accepted scope, criteria and TDD moved to
[specs/20261107-pause-media-under-break-screen.md](../specs/20261107-pause-media-under-break-screen.md),
which owns them from 2026-11-07. This file keeps the feasibility evidence.
