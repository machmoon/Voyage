# App Review Information

Paste the block below into the **Notes** field under App Review Information in App Store
Connect. Everything above the block is context for the owner and should not be submitted.

## Why this field matters on this project

Voyage has been rejected twice, and both rejections came from a reviewer inferring something
from the binary that was not true of the product:

- **5.2.5**, for real airline branding, which came from a stray framework link and from carrier
  names that collided with live carriers.
- **2.5.4**, for declaring the `audio` background mode without earning it.

Both are fixed in the code. The risk now is that a reviewer re-derives the same suspicion from
what the app looks like: it is an aviation app full of flight numbers and cabin announcements,
it asks for location, and it plays audio. The notes below pre-empt each inference in the order
a reviewer will encounter it.

Keep this field factual. Do not market in it.

## Blocking issue before this is submitted

**The PA audio licence question is unresolved.** See `out/LEGAL-pa-audio-licence.md`. The
submitted notes below say the app's audio is original content, and the Content Rights answer in
App Store Connect asserts the same. **Do not submit either claim until you have confirmed the
ElevenLabs clips were generated under a paid plan**, because on the free tier the licence is
non-commercial only and that assertion would not be accurate.

Note the wording chosen below is "original to this app and bundled", which is true of the audio
as a work either way. It is the Content Rights checkbox and the licence itself that need the
answer, not this sentence.

## Maintenance

- **`-VoyageDemoFlight` is partially broken, and the note below reflects that accurately.** The
  session does complete at 60 seconds, so arrival, baggage claim, the stamp and the logbook are
  all reachable in about a minute. What is broken is the visual phase progression: `climbEnd`
  computes past the end of the leg, so the window scene stays in climb for the whole flight and
  cruise, descent and landing never render. The submitted note therefore offers the demo flag as
  the fast path to an arrival while stating plainly that the window will look wrong, and offers
  `-VoyageShortFlights` for anyone who wants the visuals to progress correctly. **Once the
  phase-schedule bug is fixed, simplify that section to the one-minute path and drop the
  caveat**, because a reviewer who sees a landing in sixty seconds is far less likely to invent
  a reason to reject.
- Re-check the version numbers and the route example if the catalog changes.

---

## Submit this

```
Voyage is a focus timer for students. A study session is presented as a flight: you pick a
destination, the real block time of that route becomes the session length, and you study
until you land. There is no account and no sign-in. Everything below is offered because
this app is aviation-themed and several details look, from the outside, like things they
are not.

SEE A COMPLETE FLIGHT QUICKLY

The shortest real route is San Francisco to Los Angeles at 1 hour 25 minutes, which is
longer than a review session should need. There are two launch arguments that compress it.

To reach a landing and the arrival flow in about one minute:

  xcrun simctl launch booted com.patrickliu.voyage -VoyageDemoFlight

This clamps the flight to 60 seconds and completes normally, so the landing, baggage
claim, passport stamp and logbook can all be inspected quickly. Please note a known
cosmetic defect in this mode: the window scene remains in the climb state for the whole
compressed flight instead of progressing through cruise and descent. This affects only the
compressed demo mode and not real flights. A fix is in progress.

To see the in-flight visuals progress correctly through takeoff, climb and cruise:

  xcrun simctl launch booted com.patrickliu.voyage -VoyageShortFlights

This shortens the takeoff roll to about 3 seconds and reaches cruise at about 8 seconds,
leaving the route length itself unchanged.

To inspect the logbook, passport and history without flying at all: open Settings, tap
"Load demo history", and open the Logbook. That populates completed flights, miles, streaks
and passport stamps directly.

To see strict mode end a session: begin any flight, then background the app for more than
30 seconds and return. The flight diverts and the session ends.

AIRLINES AND FLIGHT NUMBERS ARE FICTIONAL

Every carrier in this app is invented. The operating carriers are Voyage Air, Harborline,
Ridgeway, Northline, Baywater and Lantern, defined in Voyage/Models/RouteCatalog.swift.
Their two and three letter codes, flight numbers, liveries and colors are ours. No real
airline's name, code, trademark, livery or palette appears anywhere in the app, and we do
not claim any affiliation with, endorsement by, or authorization from any airline.

Airport codes and coordinates are factual public geographic data. Block times are typical
scheduled durations for those city pairs and are used to set a focus-timer duration. The
app does not present live flight status, does not sell or book travel, and cannot be
mistaken for a booking or flight-tracking service.

LOCATION

Voyage requests When In Use location for one purpose: to pick the airport nearest the
device so the globe opens somewhere relevant. It resolves the nearest airport from a
bundled list of 10 airports, stores only the resulting three-letter airport code, and
discards the coordinate. No location is transmitted anywhere, no location history is kept,
and there is no server to send it to. The permission is optional. If it is denied, the app
works normally and a departure airport can be chosen manually in Settings under Origin.

NO BACKGROUND AUDIO, DELIBERATELY

This app plays cabin ambience and recorded announcements, but it does not declare the audio
background mode in UIBackgroundModes, and this is intentional rather than an oversight. All
audio is foreground only. The app's core mechanic ends the session 30 seconds after the app
is backgrounded, so there is nothing that needs to keep playing. A previous version of this
app declared that background mode without needing it and was correctly rejected under
2.5.4. It has been removed and will not be re-added.

WEATHER DATA

All weather comes from Open-Meteo (open-meteo.com), which is free and requires no API key.
It is licensed CC BY 4.0 and the required credit appears in Settings under "Weather data".
When no reading is available, the app computes clear conditions on device. This app does
not use Apple WeatherKit, does not link the WeatherKit framework, and displays no Apple
Weather data or attribution.

MAPS

All map and satellite imagery is Apple MapKit. Apple Maps attribution is visible on the
globe and on the in-flight map. There are no third-party map SDKs and no third-party
runtime dependencies of any kind; the Xcode project declares no package dependencies.

DATA AND ACCOUNTS

There is no account, no sign-in, and no server operated by us. The logbook is stored
locally with SwiftData. There are no analytics SDKs, no advertising SDKs, no tracking, and
no third-party data collection. There are no in-app purchases and no subscriptions.

The app is open source under the MIT license: https://github.com/machmoon/Voyage

AUDIO

The cabin announcements bundled with this app are synthetic speech generated by the
developer, not recordings of real airline crew, and they do not imitate any real airline's
announcements or any identifiable person.

CONTACT

Any question during review can be answered quickly at the email on this submission.
```

---

## Also complete these fields in App Store Connect

| Field | Value |
| --- | --- |
| Sign-in required | **No.** Do not attach a demo account; there is no login |
| Contact first name, last name, phone, email | Owner's real details. A reachable phone number materially reduces rejection risk on ambiguous cases |
| Attachment | Optional. If the demo flag is fixed, none is needed. While it is broken, consider attaching a short screen recording of a completed flight so the reviewer never has to wait out a real route |
| Content rights | **Hold.** The route data is factual and the carriers are invented, but the PA audio is AI-generated through ElevenLabs and its licence tier is unconfirmed. Resolve `out/LEGAL-pa-audio-licence.md` before answering this |
| Export compliance | Standard. The app makes plain HTTPS requests to Open-Meteo and uses no non-exempt encryption |
