# Product: Pomodoro

Status: draft

## Audience and problem

- Primary user: one developer (the owner) who works in long sessions across two machines, an
  Omarchy Linux desktop and a Mac, and wants a focus/break rhythm that is always one glance
  and one keystroke away, without a separate app window to manage.
- Problem and current workaround: timers in a browser tab or a phone are out of sight and
  easy to ignore; a full-featured Pomodoro app brings accounts, statistics, and configuration
  the owner does not want. Before the plugin the workaround was no timer at all.
- Evidence or assumptions: the Omarchy plugin exists and is in daily use (session counts in
  the state file, decisions revised after use on 2026-11-04). The macOS need is stated by the
  owner, not yet observed in use. Assumption: the same rhythm and the same few choices will
  be wanted on the Mac.

## Long-term vision

- Intended future experience and enduring value: on any of the owner's machines the current
  phase and time left sit in the system bar; a session starts with one tap or key; a break
  takes over every screen so it is actually taken; the next focus session starts itself. The
  value is a rhythm kept with no attention spent on the tool.
- Useful horizon, if established: two platforms, Omarchy (delivered) and macOS (next). No
  further platforms are planned.
- Principles guiding future choices:
  - One-tap choices over free-form settings. Presets, not minute fields.
  - The platform's own look and conventions. No cross-platform UI toolkit; the Mac app looks
    like a Mac app and the Omarchy plugin like an Omarchy plugin.
  - Nothing phones home. No accounts, telemetry, or sync services.
  - A break screen that can always be left with Esc. The tool never traps the session.
  - Behavior is defined once (the model) and ported with test vectors, so both platforms
    agree on what a phase, a preset, and an extension mean.
- Assumptions that could change the direction: if the owner wants history or statistics,
  storage and UI grow beyond the current "count since reset"; if two machines are used in the
  same sitting, independent timers may become a nuisance and shared state would return as a
  question (declined for now, 2026-11-04).

## Desired outcome

- What improves for the user, and how it advances the vision: the Mac gets the same rhythm
  the Omarchy desktop has, so switching machines does not mean losing the habit.
- How we will judge success: the owner runs sessions on the Mac for a week without opening
  any other timer; the break screen appears on every display when focus ends; the behaviors
  match the test vectors shared with the Omarchy plugin.

## Boundaries

- Initial scope: a macOS menu bar app with functional parity to the Omarchy plugin as of
  2026-11-05: focus presets 15/25/50/90, break Short 5/Long 15, automatic phase chaining,
  Notification, Chime, Break screen on every display with the panel's pause/reset/skip plus
  +5 min, keyboard control,
  session count with reset, state that survives relaunch and sleep.
- Deferred ambitions within the vision: none named.
- Deliberately out of scope: shared state between machines; statistics and history; task
  lists; Omarchy concepts on the Mac (plugins, shell IPC, shell.json); a Linux app outside
  Omarchy; iOS.
- Constraints: Mac App Store distribution (sandbox, notarization through review, privacy
  manifest); Swift with SwiftUI and AppKit; no network access; the behavior rules and test
  vectors in `Model.js` and `Model.test.js` are the reference for the port.

## Decisions and open questions

- Accepted decisions and brief rationale (owner, 2026-11-04):
  - Swift with SwiftUI and AppKit, prescribed in the spec, so an agent can start building.
  - Mac App Store distribution: sandboxed, no CLI or shell IPC; keyboard control through
    in-app shortcuts and one optional global shortcut.
  - Functional parity, not conceptual parity: the Mac app follows macOS conventions.
  - Independent state per machine.
- Next decision needed: minimum macOS version (the spec proposes macOS 14).
- Next action: owner reviews `docs/macos/SPEC.md` and starts the Xcode project from it.

## Capability map

| Capability                   | User outcome / contribution to vision                     | Horizon                      | Depends on                             | Delivery order / rationale                  | Definition link                                             |
| ---------------------------- | --------------------------------------------------------- | ---------------------------- | -------------------------------------- | ------------------------------------------- | ----------------------------------------------------------- |
| Omarchy bar plugin           | Rhythm in the Omarchy bar with panel, break screen, chime | now (delivered)              | none                                   | First, the owner's main machine             | [spec](specs/20261104-preset-durations-and-break-screen.md) |
| macOS menu bar app           | The same rhythm on the Mac, App Store distributed         | next                         | shared behavior rules and test vectors | Second; port the model first, then UI       | [macOS spec](../macos/SPEC.md)                              |
| Shared state across machines | One session across both machines                          | uncertain (declined for now) | both apps                              | Only if independent timers prove a nuisance | none                                                        |

## Architecture

- Boundaries, responsibilities, and data ownership: each platform has a pure, testable
  model (`Model.js` on Omarchy; a Swift package on macOS) owning phase rules, presets,
  extension, settings normalization, and state (de)serialization; a single service or
  controller owns the one running timer; views read it. Each machine owns its own state
  file and settings.
- Interfaces and constraints: the state JSON shape (`version: 2`) and the test vectors are
  shared contracts between the two ports so that behavior stays equal.
- Architecture decision records: none yet.
- Proposals or unresolved questions: none.

## Current handoff

- Authorized work: product framing and the macOS specification (owner's request,
  2026-11-04). No implementation of the macOS app authorized in this repository.
- Completed and supporting evidence: this brief; `docs/macos/SPEC.md`.
- Open decisions or blockers: minimum macOS version (proposal in the spec).
- Next action: owner reviews the spec; in a new Xcode project, `/lusona:implement` against
  `docs/macos/SPEC.md` section by section, model package first.

## References

- Omarchy plugin repository: https://github.com/johanns/omarchy-pomodoro
- Visual reference for the panel and break screen: [reference](visuals/20261104-preset-durations-and-break-screen/reference.md)
