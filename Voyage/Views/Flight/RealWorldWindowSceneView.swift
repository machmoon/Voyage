import SwiftUI

/// Immutable inputs shared by the live window and replay checkpoints. The
/// trajectory owns all geographic motion; this context contains only cabin and
/// presentation choices that do not alter the route.
struct FlightVisualContext {
    let trajectory: FlightTrajectory
    let seat: String
    let isNight: Bool
    let showsWing: Bool
    let showsSunset: Bool
    let showsAurora: Bool
    let realWorldTwinEnabled: Bool
    /// Which world the passenger chose to look out at.
    var worldMode: WindowWorldMode = .real
}

/// A low-frequency clock-owned trajectory sample plus the display instant at
/// which it was observed. TimelineView extrapolates from this anchor so session
/// events remain inexpensive while geographic camera motion updates at 60/30Hz.
struct FlightVisualClockAnchor: Equatable {
    let legElapsed: TimeInterval
    let displayDate: Date

    func elapsed(at date: Date, legDuration: TimeInterval) -> TimeInterval {
        let displayDelta = max(0, date.timeIntervalSince(displayDate))
        return min(legDuration, max(0, legElapsed + displayDelta))
    }
}

/// One continuous, route-aware world from the runway threshold through
/// rollout. MapKit satellite flyover and the deterministic procedural fallback
/// consume the exact same passenger camera pose and therefore never switch
/// geography at a phase boundary.
///
/// MapKit is the only streamed provider. It draws Apple's own attribution, which
/// `RealWorldTwinView` keeps legible by insetting the map's `layoutMargins` clear
/// of the rounded window corners and masking cabin overlays out of that band.
struct WindowSceneView: View {
    let context: FlightVisualContext
    let clockAnchor: FlightVisualClockAnchor

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: frameInterval, paused: isPaused)) { timeline in
            let elapsed = clockAnchor.elapsed(
                at: timeline.date,
                legDuration: context.trajectory.schedule.legEnd
            )
            let state = context.trajectory.state(
                at: elapsed,
                seat: context.seat,
                reduceMotion: reduceMotion
            )
            let weather = state.environment.weather(at: state.routeProgress)

            switch context.worldMode {
            case .real:
                RealWorldTwinView(
                    pose: WorldCameraPose(state.camera),
                    realWorldTwinEnabled: context.realWorldTwinEnabled,
                    reduceMotion: reduceMotion
                ) {
                    RouteAwareProceduralWorld(state: state, isNight: context.isNight)
                } foregroundOverlay: {
                    foregroundLayers(state: state, weather: weather)
                }
            case .illustrated:
                // The drawn world paints its own sky, weather, and wing, so it
                // takes the trajectory directly rather than layering over a map.
                IllustratedWindowSceneView(
                    airport: context.trajectory.leg.origin,
                    phase: state.phase,
                    altitudeFraction: min(1, max(0, state.aircraft.altitudeMeters / 10_972.8)),
                    isNight: context.isNight,
                    condition: weather?.condition ?? .clear,
                    showSunset: context.showsSunset,
                    showAurora: context.showsAurora,
                    showWing: context.showsWing,
                    isLeftSide: state.camera.side == .left,
                    legElapsed: state.elapsed,
                    phaseElapsed: phaseElapsed(for: state),
                    phaseProgress: state.phaseProgress,
                    weatherSnapshot: weather,
                    takeoffRollLength: context.trajectory.schedule.takeoffDuration,
                    climbLength: context.trajectory.schedule.climbDuration
                )
            }
        }
        .allowsHitTesting(false)
    }

    private var isPaused: Bool {
        scenePhase != .active
    }

    private var frameInterval: TimeInterval {
        let phase = context.trajectory.schedule.phase(at: clockAnchor.legElapsed)
        return phase == .cruise ? 1.0 / 30.0 : 1.0 / 60.0
    }

    private func phaseElapsed(for state: FlightVisualState) -> TimeInterval {
        let schedule = context.trajectory.schedule
        switch state.phase {
        case .takeoffRoll: return state.elapsed
        case .climb: return max(0, state.elapsed - schedule.takeoffEnd)
        case .cruise: return max(0, state.elapsed - schedule.climbEnd)
        case .descent: return max(0, state.elapsed - schedule.descentStart)
        case .landing: return max(0, state.elapsed - schedule.landingStart)
        }
    }

    @ViewBuilder
    private func foregroundLayers(
        state: FlightVisualState,
        weather: WeatherSnapshot?
    ) -> some View {
        let condition = weather?.condition ?? .clear
        let visibility = min(1, max(0.08, (weather?.visibilityMiles ?? 10) / 10))
        let altitudeFraction = min(1, max(0, state.aircraft.altitudeMeters / 10_972.8))

        ZStack {
            FlightAtmosphereLayer(
                phase: state.phase,
                phaseProgress: state.phaseProgress,
                altitudeFraction: altitudeFraction,
                elapsed: state.elapsed,
                condition: condition,
                visibility: visibility,
                isNight: context.isNight,
                goldenHour: context.showsSunset && !context.isNight,
                reduceMotion: reduceMotion
            )

            // Real-world scenery omits the illustrated wing — it reads as a
            // sticker on streamed satellite tiles.

            if context.showsAurora && context.isNight && state.phase == .cruise {
                LinearGradient(
                    colors: [.clear, Color.green.opacity(0.08), Color.cyan.opacity(0.04), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blendMode(.screen)
                .allowsHitTesting(false)
            }

            PassengerGlassLayer(condition: condition, isNight: context.isNight)
        }
    }
}

/// Coordinate-seeded procedural terrain used only when streamed providers are
/// disabled or unavailable. It is intentionally deterministic so a replay
/// never flashes an empty pane while a provider recovers.
private struct RouteAwareProceduralWorld: View {
    let state: FlightVisualState
    let isNight: Bool

    var body: some View {
        GeometryReader { proxy in
            Canvas { graphics, size in
                let skyTop = isNight ? Color(hex: "071226") : Color(hex: "4389BD")
                let skyBottom = isNight ? Color(hex: "18233C") : Color(hex: "B9D8E9")
                graphics.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .linearGradient(
                        Gradient(colors: [skyTop, skyBottom]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )

                let coordinateSeed = state.aircraft.coordinate.latitude * 17.13
                    + state.aircraft.coordinate.longitude * 31.71
                for layer in 0..<5 {
                    let depth = Double(layer) / 4
                    var ridge = Path()
                    ridge.move(to: CGPoint(x: 0, y: size.height))
                    for index in 0...18 {
                        let x = size.width * Double(index) / 18
                        let noise = sin(Double(index) * 1.29 + coordinateSeed + depth * 4.7)
                            + sin(Double(index) * 0.47 + coordinateSeed * 0.31) * 0.45
                        let horizon = size.height * (0.54 + depth * 0.085)
                        let y = horizon - noise * size.height * (0.018 + depth * 0.014)
                        ridge.addLine(to: CGPoint(x: x, y: y))
                    }
                    ridge.addLine(to: CGPoint(x: size.width, y: size.height))
                    ridge.closeSubpath()
                    let base = isNight ? 0.08 : 0.18
                    graphics.fill(
                        ridge,
                        with: .color(Color(
                            red: base + depth * 0.08,
                            green: base + 0.09 + depth * 0.10,
                            blue: base + 0.07 + depth * 0.07
                        ))
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
