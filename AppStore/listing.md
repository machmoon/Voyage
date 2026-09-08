# App Store listing copy, Voyage 1.0

Paste-ready values for App Store Connect. Character counts are exact and were measured, not
estimated. Apple's limits are in the headings.

Sources for the structural choices are in the launch package (positioning, competitive research,
keyword reasoning). This file is only the copy.

---

## App name (30 max)

```
Voyage: Focus Flight Timer
```

**26 / 30.** Identity first, then a plain-English category. Backup, if "Voyage" is contested:
`Voyage Focus: Flight Timer` (26 / 30).

## Subtitle (30 max)

```
Study Timer, Pomodoro & Focus
```

**29 / 30.** Keyword line, no verb, no claim, no price term.

## Promotional text (170 max)

Editable without a new build. Use this slot for seasonal swaps.

```
New: 37 routes across 10 airports, a 15-minute lounge break on connections, and a trip replay you can export. Book a flight, study until you land.
```

**146 / 170.**

Finals-week alternate:

```
Finals week. Book the long haul: Boston to San Francisco is 6h 45m of block time. Pack three tasks, tear the pass, and do not leave the aircraft.
```

**145 / 170.**

## Keywords (100 max)

```
study,pomodoro,focus,timer,concentration,deep work,homework,exam,revision,session,plane,adhd
```

**92 / 100.** No spaces after commas. No plurals, since Apple stems. No competitor names, no
`free`, no `best`, no manufacturer names, no `airline`.

Optional trade: `study`, `pomodoro`, `focus` and `timer` already appear in the name or subtitle
and are indexed from there. Dropping all four frees 30 characters for
`flashcards,library,semester`. Owner's call.

## Description (4000 max)

**2,814 / 4000.** Re-measured after the "live" edit. Leaves room to add press quotes later.

```
Pick a destination and the real flight time becomes your study timer. San Francisco to
Los Angeles is 1 hour 25 minutes because that is what the flight takes. Tear the boarding
pass to start. Leave the app for more than thirty seconds and the flight diverts.

I'm Patrick. I built Voyage because starting a timer is easy and obeying one is not. A
countdown asks nothing of you. A flight has a destination, a seat you picked, and bags you
checked, and you do not walk off it halfway.

HOW A FLIGHT WORKS

- Book a route. Spin the satellite globe, pick a runway. Real directional block times set
  the session length, so eastbound is shorter than westbound.
- Choose a seat. Your seat decides which side the window looks out of and whether the wing
  is in the way.
- Pack your tasks. Up to three, checked as baggage. You claim the ones you finished after
  you land.
- Tear the pass. Slide across the tear line. That is the start button.
- Study. Watch the window or the moving map. Takeoff, climb, cruise, descent and
  landing each change what you see and hear.
- Land. Claim your bags, take the passport stamp, add the miles to your logbook.

WHAT HAPPENS IF YOU LEAVE

Strict mode gives you a thirty second grace period. Miss it and the aircraft diverts and
the session ends. You keep the miles for the legs you finished. Turn strict mode off in
Settings if you would rather not fly that way.

A LONG SESSION HAS A BREAK IN IT

Longer routes connect. You land at the connecting airport, get fifteen minutes in the
lounge to stretch and drink something, and board again before the gate closes. The break
is part of the itinerary, not a button you have to remember to press.

THE CABIN

- 37 routes between 10 airports, from a 1 hour 10 minute hop to a 6 hour 45 minute long haul
- Cabin crew and captain announcements for every destination, bundled into the app so they
  play offline and no audio leaves your device
- Procedurally generated cabin ambience that mixes with your own music
- Live Activity and Dynamic Island, so you can check the remaining time without opening the
  app and diverting your own flight
- Beverage service during cruise, if you want a reminder to drink some water
- "Depart on a focus flight" works from Siri and Shortcuts

YOUR LOGBOOK

Every completed flight is stored on your device. Routes, seats, miles, streaks, the tasks
you claimed, and the weather at departure. Passport stamps fill in as you visit new cities.
Export a trip replay of your week as a video.

FREE, AND ACTUALLY FREE

Voyage costs nothing. There is no subscription, no in-app purchase, no advertising and no
analytics. There is no account and no sign-in. Your logbook stays on your phone.

Voyage is open source under the MIT license.
https://github.com/machmoon/Voyage

Weather data by Open-Meteo, CC BY 4.0.
```

## What's New (4000 max)

**482 characters.** Measured.

```
This is the first release.

Voyage turns a study session into a flight. Book a real route, pick a seat, pack up to
three tasks, tear the pass, and study until you land. Leave the app and you divert.

37 routes between 10 airports. Cabin announcements for every destination. A
fifteen minute lounge break on connections. A logbook that stamps every arrival.

No account, no subscription, no ads. If something is broken or a route is wrong, open an
issue on GitHub and I will read it.
```

---

## Other App Store Connect fields

| Field | Value |
| --- | --- |
| Primary category | Education |
| Secondary category | Productivity |
| Age rating | 4+ |
| Price | Free, no in-app purchases |
| Localizations | English (US) only. There are no `.lproj` directories in the tree |
| Support URL | https://github.com/machmoon/Voyage/issues |
| Marketing URL | https://github.com/machmoon/Voyage |
| Copyright | 2026 Patrick Liu |

**Privacy nutrition label:** Data Not Collected. There are no analytics or advertising SDKs in
the tree. If the location prompt ships, declare Location as used but not linked to identity and
not used for tracking. See `review-notes.md` for the reviewer-facing explanation.

---

## Claims that must not appear anywhere in metadata

Each of these has a specific reason, and two of them have already caused a rejection on this
project.

| Do not write | Why |
| --- | --- |
| Any real airline name, or a real carrier's flight number | App Review 5.2.5. Carriers in the app are fictional. See `review-notes.md` |
| `Boeing`, `Airbus`, `Boom`, or any manufacturer mark | Other companies' trademarks. See the aircraft-naming recommendation in the launch package |
| Apple WeatherKit, or any Apple Weather attribution | The app does not use WeatherKit and never should. Weather is Open-Meteo only |
| Google, Google Maps, streamed or photorealistic scenery, any third-party SDK | There is no Google dependency. `project.yml` declares no packages at all |
| `free` in the name or subtitle, or any price claim | Apple prohibits price and promotional terms in those fields. The description body may state it, and does |
| `best`, `#1`, or any superlative | Apple prohibits unverifiable superlatives |
| A competitor's app name | Apple rejects competitor names in metadata |
