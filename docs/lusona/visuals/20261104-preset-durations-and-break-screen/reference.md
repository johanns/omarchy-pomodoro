# Visual reference: 20261104-preset-durations-and-break-screen

- Chosen option: A, "Presets and break screen", chosen by the owner (johanns) on 2026-11-04; break-screen actions expanded on the owner's request the same day (pending re-inspection)
- Source: [option-a.html](option-a.html) (open with `#state=focus`, `#state=break`, or `#state=idle`)
- Owner: [spec](../../specs/20261104-preset-durations-and-break-screen.md)

## UI images

- [option-a-focus.png](option-a-focus.png): focus running; screens Panel
- [option-a-break.png](option-a-break.png): break running with the break screen on; screens Panel, Break screen
- [option-a-idle.png](option-a-idle.png): idle at the start of a 50 minute focus session, break screen toggle off; screens Panel

## Binding

- V1: Panel, all states: order top to bottom is hero (phase name, status, countdown; no icon), progress bar, session count, action row, Focus row, Break row, Behavior toggles.
- V2: Panel, all states: the Focus row is one segmented control with exactly the options 15, 25, 50, 90 (minutes), and exactly one is selected at all times.
- V3: Panel, all states: the Break row is one segmented control with exactly Short (5 min) and Long (15 min), and exactly one is selected at all times.
- V4: Panel, all states: Behavior contains exactly three toggles in this order: Notification, Chime, Break screen.
- V5: Break screen, break state: shows the phase name, the countdown, the progress row, and three buttons in this order: Pause (reads Resume while paused), +5 min, Stop. No icon above the phase name. A key hint line below the buttons names Esc as hide; Hide is not a button. It covers every monitor.
- V7: Break screen, break state: progress is a row of dots across the width with a Pac-Man figure at the elapsed position; dots behind it are gone. The panel keeps its plain bar.
- V6: Panel, all states: no free-form minute fields and no sessions-per-cycle field.

## Illustrative

- Colors, spacing, fonts, and glyphs: production follows the active Omarchy theme and uses Nerd Font icons.
- Caption copy under the Focus row and the break-screen meta line ("Focus resumes at ...").
- The exact form of the session count (dots plus text, or text alone).
- Key hints shown on buttons ("Space", "E", "S") and the wording of the Esc hint line.

## Fidelity

- Hand-drawn HTML approximation of the Quickshell panel. Production uses Omarchy kit components: ButtonGroup for the segmented rows, Toggle, KeyboardPanel, and a full-screen layer window for the break screen.
- The panel and break screen show no icon. The bar slot keeps its Nerd Font glyphs, which are outside this reference.
- Break-screen background dimming and the Pac-Man drawing (color, mouth angle, dot spacing) are approximate.
- The page's "Open questions" notes predate the owner's answers; the decisions in the spec govern (Q1 cycle removed, Q2 auto-start dropped, Q3 dismissable).

## Rejected options

- None. A single draft was presented for a settled request and accepted without revision.
