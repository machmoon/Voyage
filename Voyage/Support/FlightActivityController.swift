import Foundation
#if canImport(ActivityKit)
import ActivityKit
import os
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
    private static let logger = Logger(subsystem: "com.patrickliu.voyage", category: "live-activity")
    static let shared = FlightActivityController()
    private init() {}

#if canImport(ActivityKit)
    private var activity: Activity<FlightActivityAttributes>?

    /// The in-flight request, if one is running. Only one may be in flight, and
    /// it must be reconcilable with an `end` that arrives while it runs.
    private var startTask: Task<Void, Never>?

    /// Bumped by `end`. A request that completes against a stale token belongs
    /// to a session that is already over, so it is ended rather than adopted.
    private var generation = 0

    /// Lets the departure beat finish before any ActivityKit traffic. The rip
    /// is the app's most animation-dense moment and the Live Activity is not
    /// visible while Voyage is foregrounded, so this costs the traveller
    /// nothing and buys the transition a clear main thread.
    private static let startDelay: Duration = .milliseconds(300)

    /// Requests the Live Activity, off the rip.
    ///
    /// `ActivityAuthorizationInfo()` queries the Live Activity daemon when it is
    /// constructed and `Activity.request` performs its own synchronous IPC, so
    /// calling both inline from `FlightSession.startLeg` put a cross-process
    /// round trip on the main thread at the exact frame the boarding pass tears.
    /// That is the same shape of defect as the CoreLocation and AVAudioEngine
    /// hangs, and it gets the same treatment as `CoreLocationRequester`: no
    /// framework object is constructed and no framework property is read until
    /// the moment that needed the main thread has passed.
    ///
    /// Callers stay synchronous. The ordering hazard the deferral introduces,
    /// an `end` landing while the request is still running, is handled by
    /// `generation` rather than left to timing.
    func start(session: FlightSession) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        // A new leg on an existing activity is an update, not a new request.
        if activity != nil {
            update(session: session)
            return
        }
        guard startTask == nil else { return }

        let token = generation
        startTask = Task { @MainActor [weak self, weak session] in
            // Only retire our own handle. `end` followed by a new `start`
            // installs a different task, and this one must not clear it.
            defer { if token == self?.generation { self?.startTask = nil } }
            try? await Task.sleep(for: Self.startDelay)
            guard !Task.isCancelled, let self, let session else { return }
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

            let attributes = FlightActivityAttributes(
                originCode: session.itinerary.origin.code,
                destinationCode: session.itinerary.destination.code,
                viaCode: session.itinerary.connection?.code,
                flightNumber: session.currentLeg.flightNumber
            )
            // Built here rather than at call time so the first frame the
            // traveller sees reflects the flight now, not 300 ms ago.
            let requested: Activity<FlightActivityAttributes>
            do {
                requested = try Activity.request(
                    attributes: attributes,
                    content: self.content(for: session)
                )
            } catch {
                // A missing NSSupportsLiveActivities key or a user who turned
                // Live Activities off both land here. Say which, or the lock
                // screen stays empty with no trace of why.
                Self.logger.error("Live Activity request failed: \(error.localizedDescription, privacy: .public)")
                return
            }

            guard token == self.generation else {
                // The session ended while the daemon was answering. Nothing is
                // going to send this a final frame, so retire it immediately
                // instead of leaving it on the lock screen.
                await requested.end(nil, dismissalPolicy: .immediate)
                return
            }
            self.activity = requested
        }
    }

    func update(session: FlightSession) {
        guard let activity else { return }
        let content = content(for: session)
        Task { await activity.update(content) }
    }

    /// Ends the activity with a final frame ("Landed in …" / "Diverted").
    func end(session: FlightSession) {
        // Invalidate any request still in flight before looking at `activity`:
        // a session can end before the daemon has answered.
        generation &+= 1
        startTask?.cancel()
        startTask = nil

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
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        generation &+= 1
        startTask?.cancel()
        startTask = nil
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
        let now = session.now
        switch session.stage {
        case .layover:
            let caption = session.isFinalCall
                ? "Final call. Board now."
                : "Lounge · connection boards soon"
            let symbol = session.isFinalCall ? "exclamationmark.circle.fill" : "cup.and.saucer.fill"
            let arrival: Date
            if session.isFinalCall, let departs = session.connectionDeparts {
                arrival = departs.addingTimeInterval(FlightSession.finalCallWindow)
            } else if let departs = session.connectionDeparts {
                arrival = departs
            } else {
                arrival = now
            }
            let departure = arrival.addingTimeInterval(-RoutePlanner.layoverDuration)
            return .init(
                phaseCaption: caption,
                phaseSymbol: symbol,
                arrival: arrival,
                departure: departure,
                legNumber: session.legIndex + 1,
                legCount: session.itinerary.legs.count,
                concluded: false
            )
        default:
            break
        }

        let (caption, symbol): (String, String)
        switch session.stage {
        case .layover:
            (caption, symbol) = ("", "") // unreachable
        default:
            switch session.phase {
            case .takeoffRoll: (caption, symbol) = ("Taking off", "airplane.departure")
            case .climb: (caption, symbol) = ("Climbing", "arrow.up.right")
            case .cruise: (caption, symbol) = ("Cruise · deep work", "airplane")
            case .descent: (caption, symbol) = ("Descending", "arrow.down.right")
            case .landing: (caption, symbol) = ("Landing", "airplane.arrival")
            }
        }
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
