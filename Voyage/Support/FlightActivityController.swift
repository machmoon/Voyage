import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Thin ActivityKit wrapper so `FlightSession` stays clean and unit tests
/// (which run without Live Activity authorization) never touch ActivityKit
/// state. Updates happen only on phase/stage transitions — the countdown
/// itself renders live in the widget via `Text(timerInterval:)`.
///
/// Two things here exist because a Live Activity outlives the process that
/// started it, and Voyage has no background modes to lean on. Both follow
/// DuckDuckGo's VPN snooze activity, which has the same shape: a card that
/// stops being true at a known instant while the app is not running. See
/// `iOS/DuckDuckGo/VPNSnoozeLiveActivityManager.swift` in
/// duckduckgo/apple-browsers.
///
/// 1. Every content carries `staleDate: session.activityStaleDate`, their
///    `ActivityContent(state:..., staleDate: endDate)`. The widget renders its
///    ended state from `context.isStale` alone, so the lock screen tells the
///    truth without an update we may never be awake to send.
/// 2. `endOrphaned()` walks `Activity<FlightActivityAttributes>.activities`
///    rather than the in-memory handle, which is exactly their
///    `endSnoozeActivity()`. The handle dies with the process; the activity
///    does not.
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
            content: content(for: session)
        )
    }

    func update(session: FlightSession) {
        guard let activity else { return }
        let content = content(for: session)
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
        let content = ActivityContent(state: final, staleDate: session.activityStaleDate)
        self.activity = nil
        Task { await activity.end(content, dismissalPolicy: .after(.now + 60 * 5)) }
    }

    /// Ends any activity this process does not hold a handle to: one started
    /// before the app was killed, whose flight ended while we were suspended.
    /// Call it when the app becomes active with no session in hand.
    func endOrphaned() {
        let live = Activity<FlightActivityAttributes>.activities
        guard !live.isEmpty else { return }
        activity = nil
        for stray in live {
            var final = stray.content.state
            final.concluded = true
            final.phaseCaption = "Flight ended"
            final.phaseSymbol = "xmark.circle"
            Task {
                await stray.end(ActivityContent(state: final, staleDate: Date()),
                                dismissalPolicy: .immediate)
            }
        }
    }

    private func content(for session: FlightSession)
        -> ActivityContent<FlightActivityAttributes.ContentState> {
        ActivityContent(state: state(for: session), staleDate: session.activityStaleDate)
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
    func endOrphaned() {}
#endif
}
