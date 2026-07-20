# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Voyage is a SwiftUI iOS app (iOS 17+, no third-party dependencies) that themes study/focus sessions as airline flights: book a route on a globe, board, study through an airplane-window view, land, collect logbook stamps.

## Project generation (XcodeGen)

`Voyage.xcodeproj` is **generated** from `project.yml`. Never hand-edit the pbxproj. After editing `project.yml` or adding/removing source files outside Xcode:

```bash
xcodegen generate
```

(New Swift files inside existing `Voyage/`, `VoyageTests/`, `VoyageUITests/` directories still require regeneration — targets use directory-based sources, so regenerate to pick them up.)

## Build & test

Use any available iPhone simulator as the destination (check `xcrun simctl list devices booted` first):

```bash
# Build
xcodebuild -project Voyage.xcodeproj -scheme Voyage \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# All tests (unit + UI)
xcodebuild -project Voyage.xcodeproj -scheme Voyage \
  -destination 'platform=iOS Simulator,name=iPhone 17' test

# Unit tests only
xcodebuild ... test -only-testing:VoyageTests

# Single test
xcodebuild ... test -only-testing:VoyageTests/FlightSessionTests/testPhasesProgressWithElapsedTime
```

Run in the simulator with compressed flight phases for QA (takeoff ~3s, climb done by ~8s elapsed instead of ~90s):

```bash
xcrun simctl launch booted com.patliu.voyage -VoyageShortFlights
```

## Architecture

**`FlightSession` (`Voyage/Flight/FlightSession.swift`) is the heart of the app** — a `@MainActor @Observable` state machine that owns all session timing, phase transitions, audio/PA cues, strict-mode (diversion) enforcement, and writes the `LogbookEntry` at the end. Two layered states:

- `Stage`: `preflight → inFlight → (layover →) arrived`, with failure exits `diverted` (backgrounded past the 30s grace period) and `missedConnection` (layover boarding window expired).
- `LegPhase` (`takeoffRoll → climb → cruise → descent → landing`): derived purely from elapsed time within the current leg, not stored.

**`RootView` (`Voyage/App/RootView.swift`)** is the top-level router: shows `HomeView` (globe + booking) until a `FlightSession` exists, then switches the full-screen view off `session.stage`. `HomeView` constructs the session and hands it up via callback. It also forwards `scenePhase` changes to the session — that's how backgrounding triggers diversion.

**Time is injected, never read directly.** `FlightSession` takes a `VoyageClock` (`Voyage/Support/VoyageClock.swift`); production uses `SystemClock`, unit tests use `ManualClock` + explicit `session.tick()` calls to step through phases without real waiting. Preserve this pattern when adding time-dependent behavior.

**Routes are real-world data.** `Voyage/Models/RouteCatalog.swift` hardcodes every directed airport pair: actual block times (directional — eastbound rides the jet stream and is shorter), operating carrier + flight numbers, nonstop vs. the popular connection (`via`), and typical daily departure times that feed the departure-board `ScheduleSheet`. `RoutePlanner.itinerary(from:to:flightNumberOverride:)` resolves everything through the catalog; the override stamps a booked departure's flight number onto the first leg. Seat labels are letter-first ("C10").

**Timing knobs:**
- Route durations: `minutes` in `RouteCatalog`'s pair specs; lounge length: `RoutePlanner.layoverDuration`.
- Phase durations (takeoff roll, climb, descent, landing, grace period, final-call window): `nonisolated` statics on `FlightSession`. The `-VoyageShortFlights` launch argument compresses takeoff/climb via `FlightSession.shortFlightsEnabled` (and the in-flight departure curtain).

**Persistence:** SwiftData with a single model, `LogbookEntry`. The container is created in `VoyageApp` with an explicit Application Support URL and falls back to in-memory rather than crashing. Tiers (`FlyerTier`) computed from the logbook drive cosmetic unlocks only (premium cabin, sunset/aurora scenes, premium chime).

**Support layer (`Voyage/Support/`):** `SettingsStore` (singleton; unit tests mute `ambienceEnabled`/`announcementsEnabled` in `setUp` to keep tests quiet), `FlightScheduler` (scheduled flights + notifications), `LocationManager` (nearest home airport), `WeatherService` — tries WeatherKit (needs paid entitlement), then falls back to Open-Meteo (free, no API key), then `.clear`; a `XCTestConfigurationFilePath` guard keeps unit tests offline. Keep that fallback chain intact. `Shaders.metal` holds the window's atmospheric-haze `colorEffect` (returns **premultiplied** alpha — required, or the scene washes out; building `.metal` needs the Metal toolchain: `xcodebuild -downloadComponent MetalToolchain`).

**In-flight views (`Voyage/Views/Flight/`):** `InFlightView` hosts two switchable study views — the side-facing `WindowSceneView` (Canvas; per-phase kinematics from a `phaseStart` reset on phase change; wing drawn only for over-wing seats via `session.hasWingView`) and `FlightMapView` (MapKit; plane positioned by `GreatCircle` slerp at `session.legProgress`, Route/Follow cameras, Terrain/Satellite styles). A black "cabin lights dimmed" curtain covers the boarding→in-flight stage swap.

**Audio (`Voyage/Audio/`):** everything is procedurally generated (no bundled audio assets) — `CabinAudioEngine` for ambience/chimes, `Announcer` for spoken PA via speech synthesis, `Haptics`.

## QA screenshots

`VoyageUITests/ScreenshotTourUITests.swift` runs a full boarding → rip → in-flight tour with `-VoyageShortFlights` and saves PNGs to the repo's `QA/` directory (absolute path is hardcoded in the test). `QA/*.png` is committed; logs (`QA/*.log`, `QA/*.txt`, `QA/uitest/`) are gitignored.
