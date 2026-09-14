# Plan: Voyage 1.2, "Flight training"

September 14, 2026. Draft 2, after two adversarial reviews (a product and persona pass, and an
engineering pass that verified every code claim against source). Draft 1's thresholds, night
column, Instrument and Commercial rungs, Home streak, second endorsement page, PA line, and
"same shape" short-haul routes were all cut or reshaped; the reasons are recorded under each
workstream so the decisions can be checked.

Inputs: `RESEARCH-2026-09-14.md` (FocusFlight comparison and user panel),
`RESEARCH-2026-09-14-pilot-progression.md` (FAA ladder, MyFlightbook, ADHD evidence),
`RESEARCH-2026-09-14-appstore-page.md` (screenshot research).

## Thesis

Voyage's loop (book, tear, fly, land, stamp) is finished and strong. What it lacks is a reason to
fly tomorrow that is not a guilt mechanic. The evidence says the reason should be **near, typed,
honest sub-goals**, not one distant number: Bandura and Schunk found distal goals had no
demonstrable effect while proximal sub-goals built efficacy and interest; ADHD research finds
immediate, concrete rewards nearly double in effect; students in reviews reward per-minute honesty
and punish anything that "moms" them.

The metaphor the app already owns supplies exactly that structure. Real pilots progress through a
ratings ladder of typed hours and one-time events (14 CFR 61), and every real logbook app
(MyFlightbook, ForeFlight, LogTen) shows progress per requirement, one rating at a time. So: **the
traveler is a student pilot. Study hours are flight hours. The next rating, and only the next
rating, is the progression surface.** There is no instructor character. Nothing scolds.

## Ground truth (verified by the engineering review)

- Progression is `FlyerTier` by lifetime miles (0 / 5,000 / 15,000 / 40,000), consumed for
  cosmetics only. `LogbookStats.tier(entries)` at `LogbookEntry.swift:218` is the single choke
  point; call sites are `HomeView.swift:611`, `LogbookView.swift:24`, `PassportView.swift:50`.
  Unlock predicates at `FlightSession.swift:51-54` compare `FlyerTier`.
- Nothing aggregates time. `focusSeconds` (completed, excludes the lounge) and `scheduledSeconds`
  (planned, 0 on legacy rows) exist per row. `connectionCode` and `outcome` are stored.
- `departedAt` is nil on legacy rows and on every `TestModeSeeder` row. `RecorderDemoLogbook`
  sets it but anchors to March 2026.
- `LogbookStats.streakDays` reads `.now` at `LogbookEntry.swift:271`.
- Identity strings: "FOCUSED FLYER" at `BoardingPassView.swift:326`; "FOCUS / DEEP WORK" at
  `PassportView.swift:148-149`; MRZ line 2 at `PassportView.swift:200` already appends the tier
  name and is padded to 36 characters, so long rating names overflow.
- Adding an airport today requires `Airport.all`, the `timeZone` and `runway` switches
  (`Airport.swift:29-71`), `FlightRunwayCatalog.runwaysByAirport` (`FlightVisualEngine.swift:1801`,
  a missing entry is a `precondition` crash at `:391`), catalog pairs for every directed pair
  (`RouteCatalogTests.swift:30-48` requires all-pairs reachability), and ten PA clips per city.
- No persisted seat exists (`SeatSelectionView.swift:20` uses `@State`). Recent bags already
  prefill (`CheckBagView.swift:20-26`).

## Workstreams, in build order

### WS1. Ratings engine (pure model, unit-tested)

New `Voyage/Models/PilotRatings.swift`, shaped after MyFlightbook's `MilestoneProgress.cs` and
`PPLRatings.cs` (github.com/ericberman/MyFlightbookWeb,
`MyFlightbook.Web/AppCode/Flights/Ratings/`): a `RatingRequirement` with `title`, `reference`,
`kind` (`.time`, `.count`, `.achieveOnce`), `progress`, `threshold`, `isSatisfied`; a
`PilotRating` enum in order; `RatingProgress.evaluate(entries:calendar:)` returning the highest
fully satisfied rating and the next rating's requirements. Entries are projected into a value
type first, the way `FlightDataRecorder.RecordedFlight` does, so nothing touches `@Model` objects
off the main actor. No `Date.now` reads.

Only landed flights count. Columns, all measurable on legacy rows:

| Column | Definition |
|---|---|
| Total time | `focusSeconds` of landed flights (lounge time is already excluded) |
| Landings | count of landed flights |
| Airports | distinct destination codes among landed flights |
| Longest flight | max `focusSeconds` of a landed flight; a connection counts as one flight |

Rungs, with the regulation each is modelled on:

| Rating | Requirements | Modelled on |
|---|---|---|
| Student pilot | none | 61.83 |
| Solo | 3 landings | 61.87 (a sign-off, not hours) |
| Solo cross-country | 10 landings, 3 airports | 61.93 |
| Private pilot | 40 h total, 10 landings, 5 airports, one flight of 2 h or more or a connection | 61.109 |

No night column (draft 1's 21:00 to 05:00 definition rewarded midnight study, and `departedAt` is
nil on legacy rows). No Instrument, Commercial or ATP: after Private, the surface becomes a
non-regulatory "firsts" list in a later release, per MyFlightbook's `RecentAchievements.cs`.
Cross-country is geographic (new airports), so a 45-minute traveler can reach it. Copy footnote:
"Modelled on 14 CFR 61.87, 61.93 and 61.109."

Tests, `VoyageTests/PilotRatingsTests.swift`: empty logbook is student; solo after three landed
flights and not after three diverted ones; cross-country counts distinct airports; legacy rows
with `scheduledSeconds == 0` and nil `departedAt` still count toward time and landings; a
connection satisfies the long-flight item; current returns the highest fully satisfied rating;
next reports remaining amounts; ratings are monotonic as entries are appended.

### WS2. Where the rating shows

- **Logbook status card** (`LogbookView.swift:135-232`): headline becomes the rating name
  ("STUDENT PILOT"); the three stats become hours / landings / day streak; the miles bar becomes
  the next rating's checklist, one row per requirement with a bar and "2h 10m of 3h" text,
  `achieveOnce` rows as a check. Footnote as above. Miles stay on stamps and receipts.
- **Home** (`HomeView.swift:248`): the lifetime-miles text in the origin line becomes
  "Student pilot · 12h 40m of 40h toward Private". No streak on Home (a streak without a freeze
  on the launch screen is the Duolingo nag without the amulet). Compute once into `@State` keyed
  on the entry count and last date, not per body evaluation.
- **Cosmetic unlocks**: `FlyerTier` stays the type the call sites use.
  `LogbookStats.tier(entries)` returns `max(milesTier, ratingTier)` with Solo = Silver,
  Solo cross-country = Gold, Private = Platinum. Permanent, not for one release: draft 1's
  "remove miles later" would demote a Platinum-by-miles traveler. `FlyerTierTests` gains
  `testTierNeverDecreasesForMilesPlatinumWithZeroHours`.
- **Passport**: the cover chip shows the rating; the MRZ line 2 keeps the tier name because of
  the 36-character limit. "FOCUS / DEEP WORK" is left alone.
- `SeatSelectionView.swift:517` "unlock at Silver tier" copy is unchanged; the contract holds.

### WS3. Endorsement on the stamp page

When a landing completes a rating, the existing stamp page (no new `Step`) shows a second line
under the cachet, "Solo endorsement · 14 SEP 2026", with the same `Haptics.stamp()` beat, before
`askForReviewIfEarned` runs. No signature, no PA line, no character. Stored as
`LogbookEntry.endorsementRaw: String?` (optional with a default, following `LogbookEntry.swift:55-72`),
asserted in `LogbookMigrationTests.swift`. The passport lists endorsements under the stamps.

### WS4. Fewer taps to the tear

"Same seat as last time": a `SettingsStore.lastSeat` key written at departure and read as the
seat map's default when the aircraft matches. "Book again" from a logbook row is deferred; it
needs `LogbookView` to hand a route back through `HomeView` and `BoardingFlowView` to start at
the pass.

### WS5. Logbook export and the debrief prompt

Settings and the Logbook gain "Export logbook": one Markdown string, prompt first (the earlier
memo's template), then a 90-day summary, then the recorder's findings with their intervals, then
the last 20 flights as CSV rows, shared through `ShareLink` of a `String` (as at
`ArrivalFlowView.swift:506`) plus Copy. Pure formatter in `Voyage/Models/LogbookExport.swift`,
tested in `LogbookExportTests.swift` (legacy rows render, prompt appears first, findings carry
intervals).

### WS6. Short-haul routes: deferred to 1.3 with a design

The user panel ranked the 70-minute floor first, and it stays first for 1.3. Draft 1's "same
`PairSpec` shape" is wrong: ten new airports create 190 directed pairs the catalog tests require
to be reachable, a missing runway entry crashes the first booking, and each city needs ten PA
clips. The design for 1.3 is a spoke: `Airport.isSpoke` airports reachable only from their hub,
excluded from all-pairs tests, with six verified sub-60-minute pairs (LAX to SAN, SEA to PDX, SFO
to SMF, MIA to TPA, YYZ to YOW, RDU to CLT). Real block times are 50 to 65 minutes, so this is
honestly "shorter", not "45 minutes".

### WS7. App Store page

Eight screenshots per `RESEARCH-2026-09-14-appstore-page.md`, captured by
`MarketingCaptureUITests` and composited from `AppStore/screenshots-1.2.json`. Slot 6 stays the
recorder (the one angle no competitor has); the rating appears only inside slot 7's logbook card
once WS2 lands.

## What is deliberately not in this plan

- An in-app language model, an instructor character, chat, or any notification about ratings or
  streaks.
- Leaderboards or social features. Body-doubled "dual" sessions are the strongest 1.3 candidate
  and need their own research.
- App blocking, pause, a minute picker, night hours, Instrument and above.

## Acceptance

`xcodebuild test -only-testing:VoyageTests` green with the new test files; no em-dashes in prose
strings; every new design cites its precedent in a comment; `xcodegen generate` run after adding
files; the marketing capture tour still passes.
