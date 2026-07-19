# Voyage issue scope — 2026-07-19

## Owners

| Track | Owner seat | Files |
|-------|------------|-------|
| A | Head of Engineering | Crash + boarding-pass rip |
| B | Director of Product Design | Seat selection redesign |
| C | Director of Design (motion/visual) | Window runway + clouds realism |
| D | VP of Software Quality | Final design review + extensive testing |

---

## A. Crash + ticket rip (P0)

### Rip bug (confirmed root cause)
In [`BoardingPassView.swift`](../Voyage/Views/Boarding/BoardingPassView.swift), `passCard` wraps `passBody + perforation + stub` in **one** shared `.background(RoundedRectangle…systemBackground)`. The tear gesture only `.offset`s the stub’s *content* (seat text, barcode). The white paper stays glued to the parent — matches user report: “text rips, white stub doesn’t.”

**Fix direction:** Split into two paper pieces with their own backgrounds; tear only the stub piece (offset + rotation + shadow). Leave body + ragged edge after tear. Prefer vertical tear along perforation (or keep horizontal but make paper move with content). Add accessibility “Tear & board” action.

### Crash after rip (investigate + harden)
Flow: rip → `onBoarded` → FlightMode → `session.departFirstLeg()` → audio + PA + `InFlightView` + 30fps Canvas.

Suspects: AVAudioEngine start races with `playRip`/`stopAmbience`; Announcer; force-unwraps (`connection!` in InFlightView); WeatherKit Task; TimelineView/Canvas under transition.

**Fix direction:** Capture crash logs from simulator; serialize audio one-shots vs ambience start; remove force unwraps; delay heavy Canvas start one frame after transition; guard short-leg phase math.

---

## B. Seat selection (P1 design)

Current: system grouped list, `carseat.left.fill`, 38pt seats, cyan dots for windows — reads as Settings, not a cabin.

**Redesign direction:** Dark cabin fuselage map, seat glyphs as rounded cushions (not SF car seats), clear window/aisle legend, 44pt targets, destination accent, window seats visually privileged (glow / “WINDOW VIEW” chip). Feels like airline seat map (Delta/United app), not a form.

---

## C. Window scene runway + clouds (P1 visual)

Current: flat green ground + sparse dots + dashed centerline; clouds = 3 blurred ellipses × 5 — toy-like.

### Research summary (approach)
Stay on SwiftUI `TimelineView` + `Canvas` (already in use). Upgrade drawing quality, not engine:
1. **Runway:** true vanishing-point perspective (trapezoid asphalt, edge lights as glowing ellipses with bloom, centerline dashes foreshortened, approach lights/PAPI optional, motion from `time` scrolling depth).
2. **Ground:** gradient grass/tarmac near horizon, not flat fill; night = dark with light bloom.
3. **Clouds:** multi-lobe soft volumes (5–8 ellipses per cloud), layered parallax, less heavy blur, density by altitude; climb = vertical scroll through deck; cruise = distant thin layers below.
4. **Battery:** 15fps cruise / 30fps takeoff-landing; pause when inactive; Reduce Motion → static frame.
5. Escalation later: SpriteKit only if Canvas still insufficient.

---

## D. Final QA
After A–C land: build, unit + UI tests through rip → in-flight, screenshot tour (seats, rip mid-drag, runway takeoff, climb clouds), crash log check, design smoke against this scope.