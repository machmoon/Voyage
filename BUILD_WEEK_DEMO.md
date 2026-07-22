# Voyage — OpenAI Build Week demo

Target length: **2:40–2:55**. The official limit is under three minutes.

The video must show the working product and include spoken coverage of both **Codex** and **GPT-5.6**. Do not place the AI-development explanation only in captions; say it aloud.

## Recording setup

- Use an iPhone simulator with `-VoyageShortFlights` enabled.
- Record the app at native portrait resolution.
- Capture a separate landscape shot of Codex beside the repository.
- Keep pointer movement deliberate and remove terminal clutter.
- Use the same SFO route throughout so the story feels like one flight.
- Show the product before the architecture. Judges should understand why they care before being asked to admire the state machine.

## Script and shot list

### 0:00–0:12 — Hook

**Video:** Begin on the globe. Select a destination so the route appears.

**Voiceover:**

> Starting a focus timer is easy. Obeying one is not. Voyage turns the session into something much harder to casually abandon: a flight.

### 0:12–0:38 — The commitment ritual

**Video:** Move quickly through route booking, aircraft and seat selection, checking a task as baggage, and the boarding pass. Pause briefly before tearing it.

**Voiceover:**

> You book a real route, choose a seat, check your tasks as baggage, and receive a boarding pass. Tearing it is the commitment. Before the tear, you are considering a study session. After the tear, you are on a flight.

### 0:38–1:05 — The product magic

**Video:** Tear the pass. Show the departure curtain, runway roll, climb through clouds, and the window/map toggle. Briefly show the Dynamic Island or Live Activity if the recording setup allows it.

**Voiceover:**

> The phone becomes an airplane window. Takeoff, climb, cruise, descent, and landing drive the weather, camera, map, altitude, announcements, haptics, and cabin state. The selected seat even determines your side of the aircraft and whether you see the wing.

### 1:05–1:22 — The consequence

**Video:** Show the leave-flight confirmation or a prepared diversion screen. Do not spend 30 real seconds waiting on camera.

**Voiceover:**

> Leave the app and a 30-second grace period begins. Stay away and the plane diverts. “I only opened one notification” is not recognized as a valid emergency by Voyage Air.

### 1:22–1:48 — Codex and GPT-5.6

**Video:** Cut to Codex with the repository open. Show `FlightSession.swift`, the visual QA screenshots, tests, and the README section titled “How Codex and GPT-5.6 were used.” Use visible, real project artifacts rather than a generic chat screen.

**Voiceover:**

> I built Voyage with GPT-5.6 as the reasoning and coding model inside Codex. Codex stayed in the loop from product design through SwiftUI, Metal, MapKit, procedural audio, aviation data, debugging, and visual QA. GPT-5.6 was especially valuable when a decision crossed several systems—for example, centralizing every clock, lifecycle transition, renderer, Live Activity, and replay around one deterministic flight session.

### 1:48–2:10 — Proof of technical implementation

**Video:** Show `FlightSession`, `ManualClock`, one digital-twin test, the green test result, and the committed screenshot tour. Keep code shots large enough to read.

**Voiceover:**

> Codex also helped turn model output into verified engineering. Voyage has 107 unit tests and eight UI and visual tours. A manual clock can fly an entire route instantly, while the same elapsed time drives the live app, automated screenshots, and logbook replay. The app is native iOS, carries a single optional dependency for photorealistic scenery, and still works when live aviation services fail.

### 2:10–2:35 — Landing payoff

**Video:** Show descent or landing, claim the completed baggage item, stamp the passport, then open the logbook.

**Voiceover:**

> Finish the flight and your task arrives with you. Voyage records the route, miles, weather, completed intentions, streak, and passport stamp. A normal timer measures time you hoped to spend. Voyage remembers a journey you chose to finish.

### 2:35–2:48 — Close

**Video:** End on the passport or globe with the Voyage mark and the line “A focus timer you have to land.”

**Voiceover:**

> Voyage is commitment infrastructure disguised as an airline—a personal app for making focus feel meaningful and completion feel memorable.

## Submission checklist

- [ ] Select **Apps for Your Life**.
- [ ] Upload a public YouTube video shorter than three minutes.
- [ ] Confirm the audio explicitly says **Codex** and **GPT-5.6**.
- [ ] Show the application working, not only mockups or screenshots.
- [ ] Make the repository public under the MIT license, or share the private repository with both judging addresses specified by Devpost.
- [ ] Confirm the README includes setup instructions, sample-data guidance, the Codex/GPT-5.6 workflow, and key decisions.
- [ ] Run the judge path from a fresh clone if time permits.
- [ ] Enter the `/feedback` Codex Session ID from the session where most core functionality was built.
- [ ] Verify every Devpost link in a logged-out browser.
- [ ] Submit before the displayed Devpost deadline; do not use the deadline as a target upload time.

## Final editing rule

If the video runs long, remove technical nouns before removing the ritual, diversion, Codex/GPT-5.6 explanation, or landing. Those four beats establish the idea, consequence, Build Week qualification, and emotional payoff.
