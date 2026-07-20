import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Thin ActivityKit wrapper so `FlightSession` stays clean and unit tests
/// (which run without Live Activity authorization) never touch ActivityKit
/// state. Updates happen only on phase/stage transitions — the countdown
/// itself renders live in the widget via `Text(timerInterval:)`.
@MainActor
final class FlightActivityController {
    static let shared = FlightActivityController()
    private init() {}

#if canImport(ActivityKit)
    private var activity: Activity<FlightActivityAttributes>?

    func start(session: FlightSession) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // A new leg on an existing activity is an update, not a new request.
        if activity != nil {
            update(session: session)
            return
        }
        let attributes = FlightActivityAttributes(
            originCode: session.itinerary.origin.code,
            destinationCode: session.itinerary.destination.code,
            viaCode: session.itinerary.connection?.code,
            flightNumber: session.currentLeg.flightNumber
        )
        activity = try? Activity.request(
            attributes: attributes,
            content: .init(state: state(for: session), staleDate: nil)
        )
    }

    func update(session: FlightSession) {
        guard let activity else { return }
        let content = ActivityContent(state: state(for: session), staleDate: nil)
        Task { await activity.update(content) }
    }

    /// Ends the activity with a final frame ("Landed in …" / "Diverted").
    func end(session: FlightSession) {
        guard let activity else { return }
        var final = state(for: session)
        final.concluded = true
        final.phaseCaption = session.stage == .arrived
            ? "Landed in \(session.itinerary.destination.city)"
            : "Flight ended"
        final.phaseSymbol = session.stage == .arrived ? "airplane.arrival" : "xmark.circle"
        let content = ActivityContent(state: final, staleDate: nil)
        self.activity = nil
        Task { await activity.end(content, dismissalPolicy: .after(.now + 60 * 5)) }
    }

    private func state(for session: FlightSession) -> FlightActivityAttributes.ContentState {
        let (caption, symbol): (String, String)
        switch session.stage {
        case .layover:
            (caption, symbol) = ("Lounge — connection boards soon", "cup.and.saucer.fill")
        default:
            switch session.phase {
            case .takeoffRoll: (caption, symbol) = ("Taking off", "airplane.departure")
            case .climb: (caption, symbol) = ("Climbing", "arrow.up.right")
            case .cruise: (caption, symbol) = ("Cruise · deep work", "airplane")
            case .descent: (caption, symbol) = ("Descending", "arrow.down.right")
            case .landing: (caption, symbol) = ("Landing", "airplane.arrival")
            }
        }
        let now = session.now
        return .init(
            phaseCaption: caption,
            phaseSymbol: symbol,
            arrival: now.addingTimeInterval(session.legRemaining),
            departure: now.addingTimeInterval(-session.legElapsed),
            legNumber: session.legIndex + 1,
            legCount: session.itinerary.legs.count,
            concluded: false
        )
    }
#else
    func start(session: FlightSession) {}
    func update(session: FlightSession) {}
    func end(session: FlightSession) {}
#endif
}
