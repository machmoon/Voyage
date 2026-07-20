# Voyage ✈️

**Every study session is a flight.** Book a real route on a 3D globe, pick a seat, tear your boarding pass, and focus through a live airplane-window view until you land. Leave mid-flight and the plane diverts — your streak feels it.

<p>
  <img src="QA/qa-01-home.png" width="180" alt="Globe home">
  <img src="QA/qa-03-seats.png" width="180" alt="Seat map">
  <img src="QA/qa-04-boarding-pass-pre-tear.png" width="180" alt="Boarding pass">
  <img src="QA/qa-07-inflight-climb-clouds.png" width="180" alt="Window view">
</p>

## Features

- **Real routes, real timings** — block times from actual airline schedules (eastbound is shorter; thank the jet stream). Routes without a mainstream nonstop connect with a lounge break between legs.
- **Two study views** — a procedurally drawn airplane window (weather, day/night, wing seats get the wing) or a live flight-tracker map with the plane at its true great-circle position.
- **Real weather** — WeatherKit when entitled, free Open-Meteo fallback otherwise; the window shows conditions at both ends of the leg.
- **All-procedural sound** — engine ambience, cabin chimes, gear thunks, printer, tear, and spoken PA announcements. No audio assets.
- **Logbook** — SwiftData passport stamps, great-circle miles, and tiers that unlock cosmetics (premium cabin, sunset/aurora scenes).
- **No dependencies** — pure SwiftUI, iOS 17+.

## Quick start

```bash
git clone https://github.com/machmoon/Voyage.git
cd Voyage
open Voyage.xcodeproj
```

Select the **Voyage** scheme, pick any iPhone simulator, hit **⌘R**. That's it.

> The `.xcodeproj` is generated from `project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen). If you add/remove files outside Xcode, run `xcodegen generate`.

### Running on a device

Set your team under target → *Signing & Capabilities* (a free Apple ID works), then trust the certificate on-device under Settings → General → VPN & Device Management.

## Development

```bash
# Build
xcodebuild -project Voyage.xcodeproj -scheme Voyage \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# All tests (unit + UI screenshot tour)
xcodebuild -project Voyage.xcodeproj -scheme Voyage \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

**Short flights for QA:** launch with `-VoyageShortFlights` to compress takeoff/climb to seconds:

```bash
xcrun simctl launch booted com.patliu.voyage -VoyageShortFlights
```

## Architecture in one minute

```
Voyage/
  App/        @main entry + RootView (routes on session stage)
  Models/     Airports, RouteCatalog (real block times, carriers, timetables),
              RoutePlanner, GreatCircle math, SwiftData logbook
  Flight/     FlightSession — the state machine that owns everything:
              phases, timing, audio cues, strict mode, logbook writes
  Views/      Home (globe + booking) · Boarding (seat → bag → pass)
              Flight (window + map) · Landing · Logbook
  Audio/      Procedural engine bed, chimes, one-shots, speech-synth PA
  Support/    Clock injection, weather fallback chain, scheduler, theme
```

`FlightSession` never reads the wall clock directly — time is injected (`VoyageClock`), so unit tests step through an entire flight instantly with a `ManualClock`.

## Notes

- Location is requested once, only to pick your nearest home airport (override in Settings).
- Backgrounding mid-flight starts a 30-second grace period; overstay and the flight diverts. Completed legs still earn miles.
- Scheduled flights fire a local boarding notification 10 minutes before departure.
