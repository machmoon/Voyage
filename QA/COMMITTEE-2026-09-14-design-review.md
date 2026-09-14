# Design committee, September 14, 2026

Pat's brief: the app and the App Store page read as cluttered and "AI generated"; a student
with ADHD wants an Apple-like design. The committee is not a set of personas. It is five
published rulebooks, fetched and read today, applied to ten captured screens and the eight
captions. Every finding cites its source.

| Rulebook | Source read | Test applied |
|---|---|---|
| Dieter Rams, ten principles | vitsoe.com/us/about/good-design | Honest (nothing invented), unobtrusive, as little design as possible |
| Apple HIG, Designing for iOS | developer.apple.com/design/human-interface-guidelines/ios | "Limit the number of onscreen controls"; "initiate actions in a list row"; controls in reach |
| Edward Tufte, Visual Display of Quantitative Information | 1983, via holistics.io and infovis-wiki | Erase non-data ink; erase redundant data ink |
| Karri Saarinen, Linear | figma.com/blog ten rules; review.firstround.com; linear.app/method | Opinionated; reduce scope; "don't invent terms"; design for someone |
| Palantir Blueprint | github.com/palantir/blueprint README | Applied as a boundary: "optimized for complex, data-dense desktop interfaces. Not a mobile-first UI toolkit." Palantir publishes no other visual principles and none are claimed. |

## Pass one (before the committee)

One primary element, one line of context, everything else behind a tap. One type family.

- Departure board: duration and routing said once in the header, not on every row; typical-departures pill and reminder footer removed.
- Seat map: the footer is one button; the callout already names seat and cabin.
- Boarding pass: invented fields (passenger name, gate, "board now") removed; Airplane Mode chip and "slide across the tear line" instruction removed.
- Recorder: shouted title, kickers, INFORMATIONAL badge, per-card footer and axis label removed; labels in sentence case.
- Logbook: hours as the one large number; rating as its caption; only open requirements; rows are route, date and length.

## Committee findings applied

| Screen | Rulebook | Finding | Change |
|---|---|---|---|
| Recorder | Rams honest, Tufte | Bar length did not equal the printed fraction; band-and-tick read as a slider | Fill equals the rate |
| Recorder | Tufte, Linear | Two cards reported the same 38 of 44 against 6 of 13 seam | Same-seam findings are dropped in `FlightDataRecorder.report` |
| Logbook | Tufte | Hours and airports printed twice within one card | Subtitle keeps rating and landings only |
| Logbook | HIG list rows | Two always-visible controls per row | Row tap replays; share is the one control |
| Boarding pass | HIG one primary control | The only action was a dim capsule | Filled accent button |
| Departure board | Linear, Rams honest | Invented carrier codes and flight numbers on every row and in the button | Rows are time and day with a checkmark; button reads "Schedule 6:00 AM" |
| Seat map | Tufte | Aircraft and cabin repeated in the callout | Callout is seat and cabin |
| Check a bag | Rams thorough | Focus note covered the third field with the keyboard up | Note scrolls with the fields |
| Captions 2 and 5 | Rams honest | "Real routes" over invented carriers; "No countdown to stare at" over a large timer | "Real flight times."; "The plane moves as you work." |

## Findings deferred, with the reason

- Rename "bags" to "tasks", "diverted" to "stopped early", drop "solo cross-country" (Linear, don't invent terms). These change the product's vocabulary across audio clips, stamps and the logbook model. Worth a decision from Pat, not a side effect of a design pass.
- Move the in-flight toolbar to the bottom; collapse the map's three control clusters (HIG reach). Touches the flight screen, which was out of scope and is the screen that already reads best.
- Replace the seat grid with a window-or-aisle choice (Linear, reduce scope). Removes a feature; Pat's call.
- Remove the passport's MRZ and identity block (Blueprint boundary). The passport is a physical document by design; leaving it.
- System navigation bars and segmented controls across the booking flow (HIG). A larger refactor; noted for 1.3.
- Home globe label collisions and the oblique window camera (Rams understandable, honest). Rendering work, separate task.

## Verification

- Unit tests: 287, 0 failures.
- `MarketingCaptureUITests` and `RecorderScreenshotUITests` pass; the recorder tests were updated to the new copy.
- `VoyageSmokeUITests.testWeeklyReplayDesignAndPlayback` fails on this simulator because it needs a persisted logbook with flights this week. Pre-existing.

## Decisions from Pat, September 14, and what was built

- **Keep "bags", make them physical.** Each bag field is now a paper luggage label: eyelet, carrier mark and destination in the head, the task on a ruled line. Modelled on the SFO Museum's c. 1965 paper destination tag (collection.sfomuseum.org/objects/1511928635). The thermal IATA strip was rejected for its proportion. In-flight chips carry a tag glyph.
- **"Stopped early" replaces "diverted"** on the logbook stamp, the fail screen, the recovery alert, Settings, the recorder headline and the export text. The `diverted` enum case stays in code.
- **Toolbar stays on top.** The in-flight screen is unchanged.
- **Seat grid stays; airframe redrawn.** Wings end inside the screen with a raked tip. The cockpit is one curved windscreen band. Galley and lavatory are plain boxes with the fork-and-knife and toilet symbols, the convention on SeatGuru and the carriers' own maps.
- **Passport rebuilt on the achievement-grid rules** read from HabitRPG/habitica-ios (`AchievementsCollectionViewController.swift`, `AchievementIconView`) and Duolingo's published redesign: the identity page, machine-readable lines and passport number are gone; the header carries one "3 of 10" count; every unvisited city is the same faint silhouette with its code and no text.
