# Spec 20261106-hold-focus-until-return: Pause focus while the session is locked; Skip on a break starts focus

Created: 2026-11-06
Updated: 2026-11-06

Kind: feature
Work item: [work.md](../work.md)
Context: Pomodoro plugin for the Omarchy shell (`jg.pomodoro`). Builds on
[20261104-preset-durations-and-break-screen](20261104-preset-durations-and-break-screen.md),
whose AC4 (Behavior toggles), AC13 (automatic phase chaining) and AC12/Q5 (Skip/Stop on a break
leaves focus idle) this change amends. Product context: [product.md](../product.md).

## Agreement

- User and problem: The owner walks away, the session locks and the displays turn off, and
  focus time runs down with nobody at the desk: either a focus session already running, or the
  one that starts by itself when a break ends. The same happens after a suspend: on resume an
  overdue break finishes on the first tick and focus starts while the lock screen is still up.
  Separately, Skip on a break leaves the next focus session idle, so the owner has to press
  Start as a second step.
- Desired behavior or structural outcome:
  1. A new Behavior toggle, on by default, pauses focus while the session is locked. The
     plugin checks the lock state every 60 seconds. A running focus session pauses when a
     check finds the session locked; a break that ends while the session is locked leaves the
     next focus session held at its start. A later check that finds the session unlocked
     continues the session the lock paused or held.
  2. Skip on a break starts the next focus session at once.
- Scope and exclusions: Focus timing while locked, the break-to-focus handover, Skip/Stop
  during a break, the new setting and its panel toggle, and the saved timer state. Excluded:
  breaks (they keep running while locked); mouse or keyboard activity detection (owner,
  2026-11-06: rely on lock state only); Skip during focus (the break it leads to stays idle, as
  now); Reset; notification and chime wording or timing; the macOS app (see Decisions).
- Accepted constraints and invariants:
  - Constraints listed in the previous spec still apply: Omarchy plugin guide, one timer in
    `Service.qml`, state in `~/.local/state/omarchy/pomodoro.json`, settings on the bar entry
    in `shell.json`, argv-array processes, strings through `Commons.Translations`,
    `omarchy restart shell` after QML/JS edits.
  - The shell does not publish its lock service to plugins (`/usr/share/omarchy/shell/shell.qml:964`);
    lock state is available through `omarchy-shell lock isLocked` (verified 2026-11-05, returns
    `false` while unlocked). On this shell the displays turn off only while locked
    (`plugins/lock/Service.qml:764`) or suspended; the shell locks before suspend.
  - Product principle: behavior rules live in `Model.js` with test vectors in
    `Model.test.js`, so the macOS port can reuse them.
  - A state file and a `shell.json` entry written by version 1.1.0 load without error.
- Completion condition: All acceptance criteria met, `node Model.test.js` green,
  `omarchy plugin validate` passes, the lock and suspend cases tried on the owner's desktop,
  the owner accepts the result, and the change is pushed to GitHub.

### Acceptance criteria

- [ ] AC1: The panel's Behavior section shows a fourth toggle, "Pause when locked", after
  Notification, Chime and Break screen. It persists as a boolean setting, defaults to on, and
  is reachable by the panel's keyboard navigation. A 1.1.0 `shell.json` entry without the key
  reads as on.
- [ ] AC2: With the toggle on, the plugin checks the lock state at least once every 60
  seconds. It checks mouse and keyboard activity never.
- [ ] AC3: With the toggle on, a running focus session pauses at the first check that finds
  the session locked, keeping its remaining time. Up to 60 seconds of locked time may count
  against it (the check interval).
- [ ] AC4: With the toggle on, a break that ends while the session is locked leaves the
  plugin in the focus phase at its full configured length, not running. The bar and panel
  show it as an idle focus phase; no new marker. The notification and chime for the finished
  break behave as today. Breaks themselves keep running while locked.
- [ ] AC5: After a suspend during which a running break passed its end, resuming the machine
  behaves as AC4: focus does not start while the lock screen is up.
- [ ] AC6: With the toggle on, the first check that finds the session unlocked continues a
  focus session paused by AC3 from its remaining time, or starts one held by AC4 at its full
  length. A focus session the owner paused is never continued by a check.
- [ ] AC7: While focus is paused or held by the lock, Start, Pause, Skip and Reset (panel,
  bar, keyboard, IPC) act as they do on a paused or idle focus phase, and the lock no longer
  owns the session: a later unlock check does not start it.
- [ ] AC8: Turning the toggle off stops the checks. A focus session paused or held by the
  lock at that moment stays paused or idle until the owner starts it.
- [ ] AC9: A pause or hold caused by the lock survives a shell restart
  (`omarchy restart shell`) and continues under AC6.
- [ ] AC10: If the lock state cannot be read (`omarchy-shell` missing or failing), the plugin
  logs it and treats the session as unlocked: focus runs and hands over as today.
- [ ] AC11: Skip or Stop during a break, running or paused (panel, bar middle click, break
  screen, keyboard, IPC `skip`/`stop`), starts the next focus session at once at its full
  length, whatever the toggle. The skipped break does not change the completed-focus count.
  Skip during focus is unchanged: the break it leads to stays idle.
- [ ] AC12: `omarchy-shell jg.pomodoro status` reports the toggle and whether focus is paused
  or held by the lock.
- [ ] AC13: With the toggle off, focus and the break-to-focus handover behave as in 1.1.0.
- [ ] AC14: `omarchy plugin validate` passes. `node Model.test.js` passes, with cases for the
  new setting, the lock-check decisions, the break-end handover, Skip on a break, and the
  saved lock state, including a 1.1.0 state file.
- [ ] AC15: README describes the toggle, the 60-second check and its effect on timing, and
  the new Skip behavior on a break.

### Decisions and uncertainty

- Accepted decisions and source:
  - Owner, 2026-11-05: hold focus at the end of a break while the screens are asleep; start
    it once the owner has logged back in.
  - Owner, 2026-11-06 (question dialog): decide from lock state only, checked every 60
    seconds; no mouse or keyboard activity checks. A toggle in the UI controls the mode,
    default on. It applies to a running focus session as well as to the break-to-focus
    handover. On unlock the session continues automatically. While held, the bar and panel
    show an idle focus phase with no marker.
  - Owner, 2026-11-06: Skip on a break starts the next focus session automatically. This
    reverses the previous spec's Q5 detail ("Stop ... leave the next focus session idle")
    and the README text "Skip ends the break and leaves the next focus session ready".
  - TDD: targeted (owner, 2026-11-06, question dialog).
- Assumptions and unresolved questions:
  - A1 (accepted by the owner, 2026-11-06): at the moment a break ends, the plugin reads the
    lock state then rather than relying on the last 60-second check. Without it, a break that ends
    within 60 seconds of the session locking, or the first tick after a resume (AC5), would
    start focus while locked. This is still a lock-state check, not an activity check.
  - A2 (assumption): unlock is noticed at the next check, so a paused or held focus session
    continues up to 60 seconds after the owner logs in.
  - A3 (assumption): the chime and notification for the finished break fire at the end of the
    break, while the owner may be away, as today. Nothing extra plays when a check continues
    focus.
  - A4 (assumption): the toggle's panel label is "Pause when locked"; the setting key is
    named during implementation.
  - Q4 (follow-up, not in scope): the macOS spec (`docs/macos/SPEC.md`, not yet committed)
    lists "automatic phase chaining" as parity. It will need the same rule, with "locked"
    meaning the screen is locked on macOS. Record there once this is accepted.

### TDD policy

- Level: targeted
- Selected by user: owner, 2026-11-06, question dialog in this session.
- Test-first behaviors (in `Model.test.js`): normalizing the new setting (missing or invalid
  value reads as on); the lock-check decision (running focus and locked gives paused by lock;
  paused or held by lock and unlocked gives running; owner-paused and unlocked stays paused;
  toggle off gives no change); the break-end handover (locked gives held focus, unlocked gives
  running focus); Skip on a break gives a running focus phase with the count unchanged;
  serialize/parse round trip of the lock state, and a 1.1.0 state file parsing without it.
- Required regression coverage: existing `Model.test.js` cases stay green; previous-spec AC13
  behavior for focus-to-break and for break-to-focus while unlocked.

## Execution

- Approach (provisional):
  - `Model.js`: `normalizeSettings` gains `pauseWhenLocked` (boolean, default true). The saved
    state gains an optional `lockHeld` flag (focus phase, not running, paused or held by the
    lock); state version stays 2, so a 1.1.0 file reads with `lockHeld` false and 1.1.0 ignores
    the extra field. Pure decisions: the periodic lock check (pause, resume, or nothing), the
    break-end handover (start focus or hold), and whether Skip starts the next phase.
  - `Service.qml`: one `Process` running `omarchy-shell lock isLocked`; a 60 s `Timer` that
    runs only while the toggle is on and focus is running or lock-held; a fresh read when a
    break ends (A1). A read whose answer arrives after the state it was taken for has changed
    is ignored. A failed or unreadable read counts as unlocked (AC10). Manual Start, Pause,
    Skip and Reset clear `lockHeld`; turning the toggle off clears it too.
  - `Panel.qml`, `i18n/en.json`, `manifest.json` (defaults, schema, version 1.2.0), `README.md`.
- Verification: `node Model.test.js` (red then green for the targeted behaviors);
  `omarchy plugin validate`; `omarchy restart shell` then `omarchy-shell jg.pomodoro status`;
  manual lock and suspend trials on the owner's desktop (owner).

## Evidence

- Checks and outcomes (2026-11-06):
  - Targeted TDD, red before the `Model.js` change: `pauseWhenLocked` default (expected
    `true`, got `undefined`); `lockCheck`, `breakEndHolds`, `skipStartsNext`, `parseLockAnswer`
    ("is not a function"); state round trip (serialized state had no `lockHeld`). Green after
    the change. Review fix D1: new case "a running focus session whose time has run out is left
    to finish" red (`actual 'pause', expected 'none'`), then green.
  - `node Model.test.js`: 22 tests passed.
  - `omarchy plugin validate /home/jg/.config/omarchy/plugins/jg.pomodoro`: exit 0.
  - `omarchy restart shell`, then `omarchy-shell jg.pomodoro status`: the running focus session
    restored (16 done) and `pauseWhenLocked: true`, `lockHeld: false` appear. No plugin errors in
    the journal.
  - Live, unlocked: a break ended at 12:39:54; the break-end lock read answered and focus
    started at once (status: focus running, 17 done). Covers AC3/AC13 for the unlocked path.
  - Scratch Quickshell instance with the `LockRead` pattern: `omarchy-shell lock isLocked`
    answers `false` with exit 0; `exited` is handled before the deferred never-started fallback;
    a missing command answers through the fallback (exit -1, unlocked).
- Review (independent reviewer, 2026-11-06, read-only, against this spec and the diff):
  - D1 (should-fix): a lock check landing after a running focus session's end time and before
    its final tick paused it at 00:00; unlock then restarted focus at full length and the
    finished session was never counted. Fixed: `lockCheck` returns "none" when no time is left;
    the service passes the live remaining time. Test added.
  - D2 (minor, not fixed): the service restores before the panel pushes settings, so with the
    toggle off, a break that ran out while the shell was down leaves focus idle after the
    restart instead of starting it. Cost: one Start press after a shell start.
  - Gap acted on: a hold restored at shell startup was read at once, when the lock service may
    not yet answer or may not yet have recovered a surviving lock; an early "false" would start
    focus on the lock screen. Changed: the restored hold waits for the first 60 s check.
- Remaining verification and limitations:
  - Not run on this machine: AC3–AC6 against a real lock, AC5 against a real suspend, AC8 and
    AC9 trials, AC11 Skip on a break in the live shell, the panel toggle's look and keyboard
    reach (AC1). The Model tests cover the decisions; nothing tests the QML wiring.
  - Suspend during a running focus session (not a break): the shell locks just before suspend
    and no check runs in between, so the suspended time counts against focus. No criterion
    covers this; open question for the owner.
- Changes: `Model.js`, `Model.test.js`, `Service.qml`, `Panel.qml`, `i18n/en.json`,
  `manifest.json` (1.2.0), `README.md`.

## Current handoff

- Authorized work: implementation of AC1–AC15 (owner, 2026-11-06), local commits. Push needs
  separate authority.
- Completed and remaining work: implementation, tests, validate and independent review done;
  D1 fixed, D2 accepted as a limitation pending the owner. Remaining: owner trials and
  acceptance, the suspend-during-focus question, push.
- Try it:
  - Panel: Behavior shows "Pause when locked", on.
  - Start focus, lock with `omarchy system lock`, wait over a minute,
    unlock: the session was paused while locked and continues within a minute of unlocking.
  - Let a break end while locked: after unlock, focus starts within a minute at full length.
  - Skip on a running break: focus starts at once.
  - `journalctl --user -f | grep pomodoro` should show no "lock state unreadable" warning.
- Human acceptance and delivery: not given.
- Next action: owner runs the trials above, answers the suspend-during-focus question, and
  accepts or reports defects; push after acceptance with authority.
