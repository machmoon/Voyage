# Voyage product design audit

## Product promise

Voyage turns an uninterrupted focus session into a flight: choose a duration, board, work through the flight, land, and collect the result. The travel metaphor should make focus feel ceremonial without obscuring what the app actually does.

## What is already strong

- The globe creates an immediate sense of place and differentiates Voyage from ordinary timers.
- Seat selection, task “baggage,” the boarding pass, the aircraft window, arrival, and passport form a memorable beginning-to-end ritual.
- The in-flight timer is calm, glanceable, and subordinate controls stay out of the work area.
- Logbook and passport provide a credible long-term reward loop without turning the experience into a generic points dashboard.

## Priority findings

### P0 — Explain the utility before the metaphor

The first screen previously asked “Where are we flying today?” before explaining that routes represent study time. A person handed the app could reasonably mistake it for a travel planner. Home now names “focus flights,” explains that each route is a study session, shows “focus” on duration cards, and uses “Start focus flight” as the primary action.

### P0 — Never lead with permission prompts

Notification and Focus Status prompts interrupted the first impression before the user had expressed intent. Notifications are now requested when a user schedules a flight. Focus Status is requested only after they configure the Focus integration.

### P0 — Make scheduled flights legible and honest

The half-height sheet compressed ten dense rows over a visually busy satellite map. The schedule now uses a full-height opaque surface, clearer hierarchy, larger airline identifiers, one disclosure that departures are typical rather than live, and one obvious scheduling action.

### P1 — Remove fake transaction language

The seat screen showed a theatrical numeric “fare,” which looked like an unexplained charge. It now shows the actual focus block and labels it as uninterrupted study time. The continuation action is verbal rather than an unexplained circular arrow.

### P1 — Give each step one primary action

The goals screen had two nearly identical continue actions. It now has a single adaptive action: continue with the packed goals or skip for now. The screen no longer forces the keyboard open on arrival.

### P1 — Tighten supporting copy

Settings footers were long enough to dominate the controls. They now explain consequences in one sentence. Boarding copy explicitly connects tearing the ticket with starting the focus session.

## Design principles going forward

1. Say “focus” before relying on an aviation metaphor.
2. Keep one visually dominant action per screen.
3. Ask for system permissions at the moment their value becomes concrete.
4. Never present simulated information as live or financially real.
5. Preserve atmosphere in the hero moment; use quiet, opaque surfaces for decisions and dense data.
