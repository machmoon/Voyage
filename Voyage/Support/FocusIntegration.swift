import Foundation
import AppIntents
import Intents
import UIKit
import UserNotifications

/// Platform-native focus helpers: Focus Filter registration, honest pre-flight
/// guidance, and depart/land notifications. Voyage cannot flip Do Not Disturb
/// for you — this wires the pieces Apple allows.
@MainActor
@Observable
final class FocusIntegration {
    static let shared = FocusIntegration()

    /// True when the user has added Voyage to a Focus filter in Settings.
    private(set) var filterConfigured = false
    /// True when a Focus filter reports an active in-flight session.
    private(set) var filterInFlight = false
    /// Whether iOS reports any Focus mode as enabled (requires authorization).
    private(set) var systemFocusEnabled = false

    private init() {
        filterConfigured = UserDefaults.standard.bool(forKey: Keys.filterConfigured)
        filterInFlight = UserDefaults.standard.bool(forKey: Keys.filterInFlight)
    }

    // MARK: - Lifecycle

    /// Call when the app becomes active. Sync the app's Focus Filter quietly;
    /// only ask for system Focus status after the user has configured that
    /// integration. First launch should never open with a permission wall.
    func refresh() async {
        await syncFocusFilter()
        if filterConfigured {
            await refreshSystemFocusStatus()
        } else {
            systemFocusEnabled = false
        }
    }

    /// Called when the boarding pass is ripped and the first leg begins.
    func onDepart(session: FlightSession) {
        applyFilter(inFlight: true)
        guard SettingsStore.shared.flightFocusRemindersEnabled else { return }
        // The preflight flow already shows this guidance. A local banner while
        // Voyage is foregrounded covers the window at the exact takeoff beat.
        guard UIApplication.shared.applicationState != .active else { return }
        // Skip the banner during QA short flights — it covers the departure beat.
        guard !FlightSession.shortFlightsEnabled else { return }
        if !systemFocusEnabled {
            FlightNotifications.postDepartFocusReminder(for: session)
        }
    }

    /// Called when the session ends (landed, diverted, or missed connection).
    func onSessionEnded(session: FlightSession, completed: Bool) {
        applyFilter(inFlight: false)
        guard completed, UIApplication.shared.applicationState != .active else { return }
        FlightNotifications.postLandingNotification(for: session)
    }

    func markFilterConfigured() {
        filterConfigured = true
        UserDefaults.standard.set(true, forKey: Keys.filterConfigured)
    }

    func applyFilter(inFlight: Bool) {
        filterInFlight = inFlight
        UserDefaults.standard.set(inFlight, forKey: Keys.filterInFlight)
    }

    /// Opens the Settings app — the closest public entry to Focus configuration.
    func openFocusSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// One-line status for the boarding pass banner.
    var boardingStatusText: String {
        if systemFocusEnabled {
            return "Focus is on — you're cleared for takeoff"
        }
        if filterConfigured {
            return "Turn on Focus before boarding for zero interruptions"
        }
        return "Add Voyage to Focus once, then enable Do Not Disturb"
    }

    var boardingStatusSymbol: String {
        systemFocusEnabled ? "checkmark.circle.fill" : "moon.fill"
    }

    // MARK: - Private

    private enum Keys {
        static let filterConfigured = "voyage.focusFilterConfigured"
        static let filterInFlight = "voyage.focusFilterInFlight"
    }

    private func syncFocusFilter() async {
        do {
            let current = try await FlightFocusFilterIntent.current
            markFilterConfigured()
            applyFilter(inFlight: current.inFlight)
        } catch {
            // Filter not configured yet — expected on first launch.
        }
    }

    private func refreshSystemFocusStatus() async {
        // Skip the Focus Status permission prompt during QA short flights /
        // UI demos — it hijacks the first seconds of every recording.
        if FlightSession.shortFlightsEnabled {
            systemFocusEnabled = false
            return
        }
        let center = INFocusStatusCenter.default
        let status = await withCheckedContinuation { continuation in
            center.requestAuthorization { _ in
                continuation.resume(returning: center.focusStatus.isFocused ?? false)
            }
        }
        systemFocusEnabled = status
    }
}

// MARK: - Focus Filter Intent

/// Lets users add Voyage under Settings → Focus → [mode] → Add Filter.
/// When enabled, Voyage knows a flight-focus session should stay distraction-free.
struct FlightFocusFilterIntent: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Flight Focus"
    static var description = IntentDescription(
        "Marks when you're in an active Voyage focus flight so the app can stay quiet."
    )

    @Parameter(title: "In Flight", default: false)
    var inFlight: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: inFlight ? "In flight" : "On the ground"))
    }

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            FocusIntegration.shared.applyFilter(inFlight: inFlight)
            FocusIntegration.shared.markFilterConfigured()
        }
        return .result()
    }
}
