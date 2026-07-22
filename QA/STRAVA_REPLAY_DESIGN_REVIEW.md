# Voyage Replay Design Review

## Product objective

Make replay feel like a reward for focused work: the map should remain the hero, progress should produce immediate feedback, and completion should feel earned without turning Voyage into a fitness dashboard.

## What Strava gets right

- **Motion tells the story.** Activity Replay reveals the route instead of presenting a finished line immediately.
- **Stats are synchronized.** Flyover overlays distance, elevation, and pace as they happened, so the animation always communicates progress.
- **Playback is user-controlled.** Play/pause, scrubbing, speed, camera adjustment, and recentering let people watch or explore.
- **Achievements are selective.** Activity Replay highlights at most three achievements, preserving their significance.
- **Sharing is an output, not the main event.** The replay is satisfying before the user decides to export it.
- **Fallbacks preserve continuity.** Strava displays a static map while an animation is not ready instead of blocking the activity.

Official references:

- [Strava Activity Replay](https://support.strava.com/en-us/articles/15401546-activity-replay)
- [Strava Flyover](https://support.strava.com/en-us/articles/15401641-flyover)
- [Stats overlays for Flyovers](https://stories.strava.com/articles/new-add-stats-to-your-flyovers)
- [Viewing activities and achievements](https://support.strava.com/en-us/articles/15401981-viewing-activities)

## Voyage translation

Adopt the interaction principles, not Strava's brand or fitness metaphors:

| Strava pattern | Voyage expression |
| --- | --- |
| Live distance, elevation, pace | Miles flown, focus earned, flights completed |
| Segment achievements | Destination collected and flight-complete moments |
| Playback speed | 1×, 2×, and 4× recap speed |
| Camera recenter | Return to fitted active-flight route |
| Orange route emphasis | One restrained Voyage blue route ink |
| Shareable Flyover | Existing portrait replay export, visually secondary |

## Implemented in this pass

- Live replay statistics now advance with the aircraft.
- Destination and week-completion moments appear as short, haptic milestone banners.
- Playback speed cycles between 1×, 2×, and 4×.
- A recenter control restores the active route after map exploration.
- Export controls have lower visual emphasis.
- Decorative aircraft imagery was removed from the card; aircraft direction now appears only where it carries route meaning.

## Next high-value iteration

1. Add a final three-item recap: longest flight, deepest focus flight, and destinations collected.
2. Offer a simple statistics visibility toggle for people who want a pure cinematic view.
3. Measure replay frame pacing on the oldest supported physical iPhone.
4. Keep global 3D terrain outside replay until it can maintain stable performance and offline fallback behavior.

## Design guardrails

- Never assign a different route color to each flight.
- Never show more than three completion highlights.
- Avoid continuous camera movement while the map annotation is moving.
- Preserve scrubbing and Reduce Motion behavior.
- Keep social mechanics, leaderboards, and competition out of Voyage's focus-first product promise.
