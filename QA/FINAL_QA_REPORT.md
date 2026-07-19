# Voyage Final QA Report — 2026-07-19

**Owner:** VP of Software Quality (Track D)  
**Base commits reviewed:** `be15f0d` (seats) · `9e8ebef` (runway/clouds) · `2c78f27` (rip + crash harden)  
**Device:** iPhone 17 Simulator (iOS 26.5), booted  
**Verdict:** **SHIP** — all design-smoke checks pass; no P0 remaining.

---

## 1. Integration / clean tree

| Check | Result |
|-------|--------|
| Three fix tracks on `main` | Yes |
| `xcodegen generate` | Regenerated cleanly |
| Build (`Voyage` → iPhone 17) | **BUILD SUCCEEDED** |
| Leftover parallel-agent debris | Integrated (ScreenshotTour UITest + QA artifacts); no merge conflicts |

---

## 2. Automated tests

| Suite | Result |
|-------|--------|
| `VoyageTests` | **26/26 green** |
| `VoyageSmokeUITests` (through boarding pass) | **PASS** — tear copy `"Tear & board"` / hint `"Pull the stub down to tear & board"`; a11y label `"Tear and board"` |
| `ScreenshotTourUITests` (full rip → Ready → in-flight) | **PASS** with `-VoyageShortFlights` |

### QA launch argument (added this pass)

`-VoyageShortFlights` compresses takeoff (~3s) and climb (~8s total elapsed) so runway/cloud screenshots don’t wait ~90s. Documented in `README.md`.

---

## 3. Screenshot tour

| Artifact | Path | Notes |
|----------|------|-------|
| Home | `QA/qa-01-home.png` | Globe + destination strip |
| Destination selected | `QA/qa-02-selected.png` | Route summary + Depart now |
| Seat map | `QA/qa-03-seats.png` | Dark fuselage cabin map |
| Boarding pass (pre-tear) | `QA/qa-04-boarding-pass-pre-tear.png` | Body + stub + perforation |
| Post-rip / Flight Mode | `QA/qa-05-flight-mode-post-rip.png` | Captured during stub fly-off → Flight Mode |
| Takeoff runway | `QA/qa-06-inflight-runway.png` | Perspective asphalt + bloom edge lights |
| Climb clouds | `QA/qa-07-inflight-climb-clouds.png` | Multi-lobe volumes; “Climbing through the cloud deck” |

---

## 4. Crash log watch (rip → Ready → in-flight)

Streamed `simctl log stream` during UI tour. No Voyage `EXC_*`, Swift fatalError, or process termination attributed to `com.patliu.voyage` during rip → Flight Mode → in-flight. Tour completed to climb phase without crash.

---

## 5. Design review smoke (vs ISSUE_SCOPE)

| Criterion | Verdict | Evidence |
|-----------|---------|----------|
| Stub paper tears as separate piece | **PASS** | Code: `bodyPiece` / `stubPiece` each have own `systemBackground`. `qa-05` catches white stub translating/rotating off while Flight Mode enters (paper, not text-only). Pre-tear `qa-04` shows distinct stub under perforation. |
| No crash after rip into in-flight | **PASS** | UI tour: Tear → Ready for departure → runway → climb; unit suite green; no crash signals. |
| Seat map feels cabin not Settings | **PASS** | `qa-03`: dark fuselage, FORWARD, aisle, cushion seats, WINDOW legend/glow — not a grouped list. |
| Runway has perspective asphalt + bloom lights | **PASS** | `qa-06`: vanishing trapezoid asphalt, foreshortened dashes, warm bloom edge lights (not flat green dots). Status “Cleared for takeoff”, ALT 0 ft. |
| Clouds are multi-lobe volumes | **PASS** | `qa-07`: overlapping multi-lobe soft volumes; status “Climbing through the cloud deck”; ALT ~29k ft under short-flight timing. |

---

## 6. Remaining issues

### P0
*None.*

### P1
*None blocking ship.*

### P2 (polish)

1. **Mid-drag tear screenshot** — accessibility “Tear and board” commits immediately; no stable mid-drag frame in automation. Manual drag still works; optional: UITest drag on stub with `accessibilityIdentifier`.
2. **`qa-05` transition frame** — useful as paper-motion proof, but messy for marketing; re-capture a settled Flight Mode frame if needed for store/docs.
3. **Horizontal destination strip hit-testing** — off-screen cards (`destination-LAX`) fail XCUITest hit points until scrolled; tests now prefer on-screen cards / swipe. Consider always-visible short-haul when home is SFO, or `scrollTo`.
4. **Short-flight altitude pacing** — under `-VoyageShortFlights`, climb reaches high altitude by ~8s (expected); keep flag QA-only (already launch-arg gated).

---

## 7. Fixes landed in this QA pass

- `-VoyageShortFlights` phase compression + README note
- Destination / Depart accessibility identifiers for stable UI tests
- Smoke + screenshot tour hardened (origin-pin false positive, Tear a11y label, hittable cards)
- This report + QA screenshot set
