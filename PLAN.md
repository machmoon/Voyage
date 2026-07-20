# Voyage MVP Plan

*Design direction, then the engineering handoff. Treat the acceptance criteria as the contract.*

## Part I — Design review (what the product must feel like)

The idea is singular and good: **a study session you cannot quietly abandon, dressed as a flight you chose to take.** Everything in the MVP either strengthens that commitment loop or gets cut. The bar for every surface: one palette, one accent, physical interactions with real sound, zero decorative noise.

### What is right

- The commitment ritual (seat → bag → tear) is the product. The tear-to-depart moment is the emotional core; it now has print, tear, and shred physics. Protect it.
- Real routes, real block times, real weather. The honesty is the charm — never fake these.
- The window as the default study view. Calm, ambient, glanceable.

### What the MVP still needs (in priority order)

1. **Landing must pay off.** The tear is strong; the landing is weaker than the takeoff. The stamp moment needs the same physicality: thump haptic, ink-spread animation, stamp sound.
2. **A reason to come back tomorrow.** Streaks exist in the logbook but are invisible at booking. Surface "day streak" on Home; a missed day should feel like a missed flight, not a silent counter reset.
3. **Session intent that matters.** Checked bags (intentions) are written then forgotten. At landing, ask which bags "arrived" — checked-off intentions should feed the logbook entry.
4. **Live Activity / Dynamic Island.** A flight in progress belongs on the lock screen: route, phase, countdown. This is also the honest answer to "can I see my timer without opening the app."
5. **Friend-visible flying (post-MVP flag).** Gen-Z study apps live on shared accountability. A shareable "flight receipt" image (route, time, stamp) is the MVP version — no accounts, no backend.
6. **Sound polish pass 2.** PA is now filtered through the cabin-speaker chain; the remaining gap is the ambience bed (single filtered-noise source). Add a second engine-tone layer keyed to phase.

### What we cut from MVP

Accounts, cloud sync, social feeds, multiplayer lounges, non-cosmetic monetization, Android, iPad-optimized layout. All post-MVP.

## Part II — Engineering handoff

Six workstreams. Each has an owner role, scope, and acceptance criteria. No workstream ships without its tests.

### WS1 · Arrival & Logbook payoff — *Feature engineer + Motion designer*
- Stamp animation: scale-down thump with ink bleed; procedural stamp sound; haptic `.heavy`.
- Bag claim: intentions checklist at arrival, persisted into `LogbookEntry.intentionsCompleted`.
- **Accept:** stamp animates at 60fps on A15; intentions round-trip through SwiftData; unit test for entry writes.

### WS2 · Streaks on Home — *Feature engineer*
- `LogbookStats.currentStreak` surfaced as a Home chip beside tier; "flight missed" state on a broken streak.
- **Accept:** streak math unit-tested across time zones/DST using `ManualClock`; chip matches design spec.

### WS3 · Live Activity — *Platform engineer*
- ActivityKit widget: route codes, phase glyph, countdown; starts at depart, ends at land/divert.
- **Accept:** activity survives app suspension; grace-period diversion updates it within 5 s.

### WS4 · Flight receipt sharing — *Feature engineer + Designer*
- Render the landed itinerary as a shareable image (ImageRenderer): ticket-style, stamp, duration, miles.
- **Accept:** output is 3:4, <1 MB, correct in light/dark; share sheet from arrival + logbook detail.

### WS5 · Audio bed v2 — *Audio engineer*
- Second source node: phase-keyed engine tone (low sine cluster with detune) beneath the noise bed; crossfade on phase change.
- **Accept:** no clipping at max volume; CPU <3% on A15; toggling sound mid-phase never pops.

### WS6 · Quality gate — *Quality engineer*
- Screenshot tour extended to arrival + logbook; snapshot diffs reviewed on every PR.
- Device-matrix smoke (SE 3rd gen, 17 Pro Max) before tagging a release.
- **Accept:** `xcodebuild test` green on both simulators; QA/ images regenerate deterministically.

### Sequencing

WS1 → WS2 (same surfaces), WS3 ∥ WS4 ∥ WS5 independent, WS6 continuous. Target: two weeks to MVP-complete.

### Status (2026-07-20)

- **WS1 (arrival payoff)** — largely pre-existing: baggage claim persists intentions, passport stamp has thunk + haptic. Interactive tints unified on `Theme.accent`.
- **WS2 (streaks on Home)** — ✅ shipped: flame chip with day streak + miles on Home.
- **WS3 (Live Activity)** — ✅ shipped: `VoyageWidgets` extension, lock-screen card + Dynamic Island, updates on phase transitions only.
- **WS4 (flight receipt)** — open.
- **WS5 (audio bed v2)** — partial: PA now offline-rendered through a cabin-speaker filter; engine-tone layer still open.
- **WS6 (quality gate)** — screenshot tour is the visual regression net; arrival-flow coverage still open.
Also shipped from the field report: recent-bag quick-add chips, countdown affordance chevron, intentions strip scrolling, notifications-denied banner caption, graceful divert audio fade, Siri-preferring + user-selectable PA voice.
