# Notes: break-screen-mirrors-panel-actions

Context: follow-up to the delivered
[preset durations and break screen spec](../specs/20261104-preset-durations-and-break-screen.md).
That spec's AC6 and AC12 ("three buttons: Pause, +5 min, Stop"; key S = Stop) are superseded
by the decision below for the break screen's action row.

## 2026-11-05 — Skip button on the break screen

### Agreement and decisions

- Request (owner, `/lusona:implement`, 2026-11-05): "add skip button to the break screen".
- Decision (owner, question dialog, 2026-11-05): the break screen mirrors the panel's action
  row, with the same labels, icons, keys, and behavior, and keeps +5 min. Row: Pause/Resume ·
  Space, Reset · R, Skip · S, +5 min · E. N also skips, as in the panel.
  - Skip behaves exactly as the panel's Skip: the break ends and the next focus session waits,
    not running.
  - Stop is removed from the screen; it did the same as Skip. IPC `stop` is kept as an alias
    of `skip` so existing scripts keep working.
  - Reset during a break restarts the break at full length, stopped. A stopped break at its
    start is not engaged, so the break screen closes (existing gating in
    `Model.shouldShowBreakScreen`).
- Rejected in the same dialog: a Skip that starts the next phase running, and a Stop that
  returns to a ready focus session from any phase. The owner chose to mirror the panel instead.
- TDD: `none`, selected by the owner in the question dialog, 2026-11-05. The change is in QML
  with no automated test harness; `Model.js` is unchanged.

### Evidence

- 2026-11-05, this machine, two monitors (DP-1 3440x1440, DP-3 1920x1080):
  - `node Model.test.js` → 15 tests passed. `omarchy plugin validate .` → exit 0.
  - After `omarchy restart shell`, IPC `skip` then `start` → break running, 05:00,
    `breakScreenShown` true, 2 `jg-pomodoro-break` layers.
  - Screenshot of DP-3 (1920 wide): the row reads Pause · Space, Reset · R, Skip · S,
    +5 min · E, with the panel's icons, centered, no overflow.
  - Keys sent with `wtype` to the break screen: E → 09:49 running; Space → paused; Space →
    running; R → break 05:00 stopped, screen gone (0 layers); after `start`, S → focus 25:00
    stopped, 0 layers, count unchanged at 12; after `skip`/`start`, N → same as S.
  - Shell log since the restart: no warnings or errors from the plugin's QML. The only
    plugin-related line is the existing qmlscanner note that the module path is outside the
    config folder.
  - The owner's timer state file was backed up before the checks and restored after them
    (focus paused at 24:56, 12 sessions done).
- Not exercised: mouse clicks on the new buttons (they call the same service functions as
  the keys).

## Current handoff

- Authorized work: add Skip to the break screen by mirroring the panel's actions; local
  commit included. Push not authorized.
- Next action: owner tries the break screen and accepts, or asks for changes; push on request.
