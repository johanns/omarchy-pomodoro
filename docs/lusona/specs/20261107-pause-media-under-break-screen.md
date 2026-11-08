# Spec 20261107-pause-media-under-break-screen: Pause media while the break screen is up

Created: 2026-11-07
Updated: 2026-11-07

Kind: feature
Work item: [work.md](../work.md)
Context: Pomodoro plugin for the Omarchy shell (`jg.pomodoro`). Feasibility and the decision
history are in [notes/pause-media-on-break.md](../notes/pause-media-on-break.md). Builds on the
break screen from [20261104-preset-durations-and-break-screen](20261104-preset-durations-and-break-screen.md)
and the lock behavior from [20261106-hold-focus-until-return](20261106-hold-focus-until-return.md).

## Agreement

- User and problem: When the break screen covers the monitors while a video plays, the video
  keeps running underneath and cannot be seen.
- Desired behavior: A new Behavior toggle, off by default. With it on, every playing media
  player is paused when the break screen appears, and the players the plugin paused resume
  when the break screen goes away. A break that ends while the session is locked does not
  resume them; the owner does.
- Scope and exclusions: MPRIS players seen by Quickshell, the break screen's appearance and
  removal, the new setting and panel toggle, and the saved state. Excluded: media during focus;
  MPRIS Stop; volume; the macOS app.
- Accepted constraints and invariants:
  - Constraints from the previous specs still apply (one timer in `Service.qml`, state in
    `~/.local/state/omarchy/pomodoro.json`, settings on the bar entry in `shell.json`,
    strings through `Commons.Translations`, rules in `Model.js` with tests in `Model.test.js`).
  - Players are reached through `import Quickshell.Services.Mpris` in the service. A player is
    identified by its `dbusName`, which is stable while the player process runs.
  - A state file written by 1.2.0 (no media field) loads without error, and 1.2.0 ignores the
    new field. The state version stays 2.
- Completion condition: All acceptance criteria met, `npm test` green, `omarchy plugin
  validate` passes, a live pause and resume observed on the owner's desktop, independent
  review done, the owner accepts the result. Pushing needs separate authorization.

### Acceptance criteria

- [ ] AC1: The panel's Behavior section shows a fifth toggle, "Pause media", after "Pause when
  locked". It persists as the boolean setting `pauseMedia`, defaults to off, and is reachable
  by the panel's keyboard navigation. A 1.2.0 `shell.json` entry without the key reads as off.
- [x] AC2: With the toggle on, when the break screen appears, every MPRIS player that is
  playing and can pause is paused, and the plugin records each one's `dbusName`. With the
  toggle off, nothing is paused. With the Break screen setting off, the break screen never
  appears, so nothing is paused.
- [ ] AC3: When the break screen goes away (the break runs out, Esc or Hide, Skip, Reset, or
  the Break screen setting turned off), each recorded player that still exists and is not
  playing is resumed, and the record is cleared. Players the plugin did not pause are not
  touched. Resume happens even if the toggle was turned off during the break.
- [x] AC4: With "Pause when locked" on, a break that runs out while the session is locked
  clears the record without resuming any player. Unlocking later does not resume them. A break
  that runs out while unlocked resumes them as in AC3.
- [x] AC5: The record is saved in `pomodoro.json`. After a shell restart during a break, the
  restored record is resumed under AC3 when the break screen next goes away. If the break has
  already ended when the shell starts, the record is cleared without resuming.
- [x] AC6: A saved record that is not a list of MPRIS bus names is read as empty. A 1.2.0 state
  file reads with an empty record.
- [x] AC7: `omarchy-shell jg.pomodoro status` reports the toggle as `pauseMedia` and the
  recorded players as `mediaPaused`.
- [x] AC8: `npm test` passes, with cases for the setting default, which players are paused,
  which are resumed, the break-screen decision (pause, resume, wait for the lock read), and
  the saved record. `omarchy plugin validate` passes.
- [x] AC9: README describes the toggle, when media pauses and resumes, the lock case, and the
  settings table entry.

### Decisions and uncertainty

- Accepted decisions and source (owner, chat, 2026-11-07):
  - Pause, not MPRIS Stop; pause every playing player; toggle off by default.
  - "if the overlay is up, pause; when overlay is cleared (due to timer or esc, then resume)".
  - "don't resume media when focus is resumed after unlock; let the user handle resume at that
    point". Owner confirmed: a break that ends while locked resumes nothing.
  - Save the record ("Sure, record").
  - After a shell restart with the break already over, clear without resuming (proposed in
    chat, owner said "yes, confirmed").
- Assumptions:
  - A1: a break ending with "Pause when locked" on waits for the existing break-end lock read
    before deciding resume or clear. The read normally answers in well under a second.
  - A2: a player that is playing when the break screen reappears after a shell restart is
    paused and added to the record.
  - A3: if the Break screen setting is turned off in `shell.json` while the shell is down and
    the break is still running or paused at startup, the restored record is resumed when media
    becomes ready (3 s after startup, once settings are in), since no break screen is up.
  - A4: media does not react for 3 s after a shell start, until the settings are pushed. A
    break screen up at that point pauses what plays then.
  - A5 (limitation, accepted from review): a record that outlives a reboot during a paused
    break is resumed by bus name, so a new process with a fixed name (Spotify) can be played.
    Documented in README.

### TDD policy

- Level: targeted
- Selected by user: owner, 2026-11-07, chat. The owner replied "yes, confirmed — go ahead and
  implement it" to the proposal "write the tests first for the plain logic in `Model.js`".
- Test-first behaviors (in `Model.test.js`): `pauseMedia` default and parsing; which players
  are paused; which recorded players are resumed; the break-screen decision; the saved record
  round trip, bounds, and a 1.2.0 file.
- Required regression coverage: existing `Model.test.js` cases stay green.

## Execution

- Approach:
  - `Model.js`: `normalizeSettings` gains `pauseMedia`. Pure functions `playersToPause`,
    `playersToResume`, `mediaOnBreakScreen`, `validMediaPaused`. `serializeState` and
    `parseState` carry `mediaPaused`.
  - `Service.qml`: binds `Mpris.players.values` at load; reacts to `breakScreenShown`
    changes; a break end with "Pause when locked" on defers the media decision to the
    break-end lock read; restore clears the record when the break is over.
  - `Panel.qml`, `i18n/en.json`, `manifest.json` (default, schema, version 1.3.0), `README.md`.
- Verification: `npm test` red then green; `omarchy plugin validate`; `omarchy restart shell`
  and `status`; a live trial with a playing player and `finishPhase`, Esc, Skip.

## Evidence

- Checks and outcomes (2026-11-07, this machine):
  - Targeted TDD red: with the new tests and before the `Model.js` change, a per-test runner
    reported 11 failures: the six new cases (`pauseMedia` default; `playersToPause`,
    `playersToResume`, `mediaOnBreakScreen`, `validMediaPaused` "is not a function"; media
    record round trip) and five existing exact-shape cases whose expected objects gained
    `pauseMedia: false` or `mediaPaused: []`. Green after the change: `npm test` → 29 tests
    passed. After review: `mediaOnBreakEnd` and `keepMediaRecord` red ("is not a function"),
    then green; four added assertions (toggle-only resume, pause while a lock read is out,
    full-record merge, bare prefix) passed on the existing code. `npm test` → 31 passed.
  - `npx biome lint .` clean; every QML file unchanged by `qmlformat`; `npm run lint:qml` → 147
    warnings before and after the change (all pre-existing).
  - `omarchy plugin validate` on the working tree fails on `node_modules/.bin/biome` (a
    symlink from the dev install, not part of the plugin). On a copy of the tracked and new
    files without `node_modules`: exit 0.
  - Live trial, Brave playing a Paramount+ video, `pauseMedia` and `breakScreen` on, trial
    script driving IPC (`finishPhase`, `hideBreakScreen`, `skip`, `simulateLock`), checks
    against `status` and `omarchy-shell media status`. Each step passed in a run:
    pause when the break screen appears (AC2); resume on Esc and on Skip (AC3); record
    survives `omarchy restart shell` with the break screen up, then resume on Esc (AC5);
    locked break end leaves Brave paused and clears the record (AC4); unlocked break end
    (real lock read) resumes Brave and starts focus (AC4); an expired break with a saved
    record, loaded by a shell restart, clears the record and leaves Brave paused (AC5).
    Sampling: Brave reported paused within 0.3 s of the break starting and playing 1 s
    after the screen was hidden.
  - Three defects found by the trial and fixed before the passing runs: `Mpris.players.values`
    is a Qt sequence that fails `Array.isArray`, so nothing was paused (now copied with
    `Array.prototype.slice.call`); `breakScreenShown` flips true/false/true inside one
    `enterPhase()`+`start()` call, which cleared the record mid-transition (media now acts
    once on the settled value via `Qt.callLater`); after a shell start, player properties
    (`CanPlay`, `PlaybackStatus`) load after the service, so a resume then found nothing
    resumable and dropped the record (media now waits 3 s after restore).
  - Owner environment restored after the trial: `pauseMedia` removed from `shell.json`, the
    original timer state file copied back (focus running, count 2), Brave playing.
- Review (independent reviewer subagent, 2026-11-07, read-only, against this spec and the
  working-tree diff; it ran `npm test` and validation, no live runs):
  - R1 (should-fix, fixed): a shell restart in the last ~3 s of a break, unlocked, resumed
    before player properties loaded and dropped the record (AC5). `resumeMedia` now waits for
    `mediaReady`; the record resumes when media becomes ready. Live case F passed.
  - R2 (should-fix, partly fixed): the 3 s startup delay could precede the settings push.
    Media now also waits for the first settings push. The player-loading half rests on a
    misreading: "within 4 s" in the notes was the probe's wait, and the shell log shows
    Brave's properties loading in the second the service started.
  - R3 (minor, fixed): a pending break-end lock read could act on a record taken over by a
    new break screen. A break screen appearing now cancels the wait.
  - R4 (minor, fixed): after a restart with a restored record, a newly playing player was not
    paused (A2). The first sync now pauses and merges.
  - R5 (minor, fixed): A3 text updated to the code's behavior.
  - R6 (minor, fixed): `validMediaPaused` stops at the 16-name cap.
  - R7 (minor, fixed): players past the cap were paused but never recorded; only names that
    fit are paused now.
  - R8 (minor, documented): a record that outlives a reboot resumes by bus name (A5, README).
  - R9 (minor, documented): README tells the owner to turn Pause media off before
    `tests/lock-trials.py`.
  - R10 (minor, fixed in part): Model tests added for the gaps; the restore rule and the
    break-end media decision moved to `Model.js` (`keepMediaRecord`, `mediaOnBreakEnd`).
  - After the fixes, the live trial reran: 12 of 12 passed (A–E plus F, the R1 scenario),
    and the expired-break restart case passed again. Owner environment restored again
    (timer state file and `shell.json` byte-identical to the pre-trial backups, Brave playing).
- Remaining verification and limitations:
  - Not observed: the panel toggle's look and keyboard reach (AC1); Reset and the Break screen
    toggle as resume triggers (same code path as Esc, not run live).
  - For 3 s after a shell start, media does not react; a break screen appearing in that
    window pauses media when the window ends.
  - A player that starts playing while the break screen is already up is not paused.

## Current handoff

- Next: owner acceptance. Turn on "Pause media" in the panel and let a break start with
  media playing. Pushing needs separate authorization.
