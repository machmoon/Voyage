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

### Status (2026-09-08)

Reconciled against source, not against the previous status block. Items marked shipped
were confirmed by reading the call sites cited. The tree builds clean and all 163 unit
tests pass on iPhone 17.

- **WS1 (arrival payoff)**: ✅ shipped, in the uncommitted tree. `PassportStamp.swift` retired; `StampView` now at `ArrivalFlowView.swift:308` with `Haptics.stamp()` at `:407`. Bag claim writes `entry.intentionsCompleted` at `:298`, round-tripped in `LogbookMigrationTests.swift:79,102`. New this cycle: a passport spread with an ICAO 9303 TD3 machine-readable zone. Two gaps: the check-digit arithmetic is `private` inside a view file and therefore unreachable from `VoyageTests`, and the destination backdrop at `ArrivalFlowView.swift:1715-1762` draws Apple satellite imagery with no Apple attribution. Fix the attribution before submitting.
- **WS2 (streaks on Home)**: ❌ **not shipped.** The previous status block was wrong. `LogbookStats.streakDays` exists at `LogbookEntry.swift:208`, but its only consumer in the app is `LogbookView.swift:111`. There is no Home chip and no missed-flight state, at HEAD or in the working tree. The acceptance criterion is also blocked: `streakDays` reads `Date.now` directly at `LogbookEntry.swift:211`, so DST and rollover cannot be tested. Give it an injected `now` before building the chip.
- **WS3 (Live Activity)**: ✅ shipped, one criterion unmet. `VoyageWidgets` extension, lock-screen card and Dynamic Island, wired at `FlightSession.swift:427,547,662,679,749`. "Diversion updates it within 5s" fails: `divert()` does end the activity by way of `stopEverything()` (`FlightSession.swift:749`), but neither the 0.5s `Timer` (`:482`) nor the grace `DispatchWorkItem` (`:707-716`) fires while the app is suspended, so the divert and the activity end are both deferred until the traveler reopens the app. The lock screen keeps counting down in the meantime. Fix by passing a real `staleDate` into `ActivityContent` instead of `nil`, and delete the stale "ambience keeps the process alive" comment, which stopped being true when the `audio` background mode was removed.
- **WS4 (flight receipt)**: ✅ shipped. The previous status block was wrong. `FlightReceiptView.swift` + `ReceiptShareItem.swift`, rendered by `FlightReceiptRenderer` at `:217-231`. Four share entry points, not the two the workstream asked for: `ArrivalFlowView.swift:454`, `LogbookView.swift:260`, `FlightReplayView.swift:238`, `FlightPostView.swift:243`. The 3:4, sub-1 MB and light/dark criteria are unasserted; no test references `FlightReceipt`.
- **WS5 (audio bed v2)**: ✅ shipped, in the uncommitted tree. Two crossfading player nodes with per-node ramp generations, cached loop buffers keyed by fundamental, off-main-thread generation, and the old baked-in 43/86 Hz hum removed from the noise bed (`CabinAudioEngine.swift:642-649`). CPU and clipping criteria are unmeasured. One leak to tidy: at `:498-503` the outgoing player is ramped to zero but never stopped and `liveTonePlayer` is not cleared, so a silent loop keeps rendering.
- **WS6 (quality gate)**: ❌ open, and further behind than previously recorded. `ScreenshotTourUITests.swift:12-88` ends at the window/map toggle and never reaches arrival, the stamp, the passport, or the logbook, which is exactly the surface WS1 just rebuilt. `:94` writes to a hardcoded absolute path, so the tour runs on one machine only. There is no `.github/` directory and no CI of any kind, so "snapshot diffs reviewed on every PR" has never been true.

Also shipped from the field report: recent-bag quick-add chips, countdown affordance chevron, intentions strip scrolling, notifications-denied banner caption, graceful divert audio fade, Siri-preferring + user-selectable PA voice. From the current cycle: three-letter carrier codes, WeatherKit removal with Open-Meteo CC BY 4.0 credit in Settings, `UIBackgroundModes: audio` removal, shared `GlobeRoute` rendering across Home and Onboarding, the Boom Overture, and a Reduce Motion pass.

### Submission blockers (2026-09-08)

Not workstreams, but nothing ships until they are closed. Full detail in the launch readiness audit.

1. No `PrivacyInfo.xcprivacy`. Upload fails with ITMS-91053. Needs one `NSPrivacyAccessedAPICategoryUserDefaults` / `CA92.1` entry.
2. Apple satellite imagery with no attribution at `ArrivalFlowView.swift:1715-1762`, on the branch that exists because of a 5.2.5 attribution rejection.
3. `SFOAirportWorldData.swift:16` holds an OpenStreetMap ODbL attribution string that no view renders.
4. `VoyageAPIBaseURL` (`Info.plist:23-24`) advertises a backend `VoyageAPIClient` never calls. Delete both or wire it up.
5. **Closed 2026-09-08.** All six prose em-dashes were fixed in `FlightNotifications.swift`, `FlightScheduler.swift`, `FocusIntegration.swift`, `FlightActivityController.swift` and `CheckBagView.swift`. The empty-value glyphs (`FlightSession.swift:43`, `PassportView.swift`, `FlightReplayView.swift`, `BoardingPassView.swift`, `SeatSelectionView.swift`) were correctly left alone: that is airline typography, not a copy violation. Verified by grep.
6. `-VoyageDemoFlight` never leaves climb. A 60s `demoLegDuration` enters the short-flights branch of `FlightPhaseSchedule.make` (`FlightVisualEngine.swift:31-47`) and yields `climbEnd` 135 against a leg that ends at 60. Any reel or screenshot cut from `DemoReelUITests` is a minute of climb.
