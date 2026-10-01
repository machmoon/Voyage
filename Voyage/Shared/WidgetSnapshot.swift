import Foundation

/// The App Group the app and the widget extension share. The widget cannot
/// open the app's SwiftData store or call `FlightScheduler`, so the app writes
/// the little the widget shows into this suite and asks WidgetKit to reload.
///
/// Same arrangement as apple/sample-backyard-birds, whose app and widget both
/// carry one `com.apple.security.application-groups` entry
/// (`Widgets/Widgets.entitlements`) so the timeline provider can read what the
/// app wrote (`Widgets/Backyard/BackyardSnapshotTimelineProvider.swift`). Theirs
/// shares a whole SwiftData container; Voyage needs one small Codable value,
/// so it shares a defaults suite instead.
enum VoyageAppGroup {
    static let identifier = "group.com.patrickliu.voyage"

    /// Falls back to the standard suite when the group is missing (an
    /// unsigned CI build). The widget then shows its idle state, which is
    /// true: it does not know about any flight.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}

/// Everything the Home Screen widget draws. Written by the app
/// (`WidgetBridge`, and `FlightActivityController` for the flight in the
/// air), read by the widget's timeline provider. Every field added after the
/// first release is optional, so a snapshot an older build wrote still decodes.
struct WidgetSnapshot: Codable, Equatable {
    /// A flight booked for later (`ScheduledFlight`), flattened so the widget
    /// needs no airport table.
    struct ScheduledLeg: Codable, Equatable {
        var originCode: String
        var destinationCode: String
        var destinationCity: String
        var flightNumber: String
        var departure: Date
        var boardingOpens: Date
        var boardingCloses: Date
        /// Block time of the route.
        var duration: TimeInterval?
        /// Initial great-circle course, degrees true (the Heading style).
        var courseDegrees: Double?
    }

    /// The route "Take off" will fly: the last one flown, or the shortest open
    /// one from home.
    struct QuickRoute: Codable, Equatable {
        var originCode: String
        var destinationCode: String
        var duration: TimeInterval
        var destinationCity: String?
        var courseDegrees: Double?
    }

    /// The leg in the air right now. The widget precomputes a timeline entry
    /// per minute from `departure` to `arrival`, so it moves without reloads.
    struct ActiveLeg: Codable, Equatable {
        var originCode: String
        var destinationCode: String
        var destinationCity: String
        var departure: Date
        var arrival: Date
        var seat: String?
        var bags: Int?
        var courseDegrees: Double?
    }

    var scheduled: ScheduledLeg?
    var quickRoute: QuickRoute?
    var active: ActiveLeg?

    init(scheduled: ScheduledLeg? = nil, quickRoute: QuickRoute? = nil, active: ActiveLeg? = nil) {
        self.scheduled = scheduled
        self.quickRoute = quickRoute
        self.active = active
    }

    static let empty = WidgetSnapshot()
}

enum WidgetSnapshotStore {
    private static let key = "voyage.widget.snapshot"

    static func load(from defaults: UserDefaults = VoyageAppGroup.defaults) -> WidgetSnapshot {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    /// Returns true when the stored value changed, so the caller reloads
    /// timelines only then: WidgetKit budgets reloads, and Home calls this on
    /// every appearance.
    /// Replaces only the in-flight leg, keeping what Home wrote.
    @discardableResult
    static func setActive(_ leg: WidgetSnapshot.ActiveLeg?,
                          in defaults: UserDefaults = VoyageAppGroup.defaults) -> Bool {
        var snapshot = load(from: defaults)
        snapshot.active = leg
        return save(snapshot, to: defaults)
    }

    @discardableResult
    static func save(_ snapshot: WidgetSnapshot,
                     to defaults: UserDefaults = VoyageAppGroup.defaults) -> Bool {
        guard load(from: defaults) != snapshot,
              let data = try? JSONEncoder().encode(snapshot) else { return false }
        defaults.set(data, forKey: key)
        return true
    }
}

/// The widget's "Take off" button, handed to the app. The intent runs with
/// `openAppWhenRun`, so it leaves a timestamped request here and posts a
/// notification; Home consumes it on whichever of the two it sees first.
/// The timestamp keeps a request that arrived mid-flight (Home not on screen)
/// from launching a second flight minutes later.
enum TakeOffRequest {
    private static let key = "voyage.widget.takeOffRequestedAt"
    static let notification = Notification.Name("voyage.widget.takeOff")
    /// Long enough for a cold launch and the launch flyover.
    static let freshness: TimeInterval = 120

    static func post(at date: Date = .now, to defaults: UserDefaults = VoyageAppGroup.defaults) {
        defaults.set(date.timeIntervalSince1970, forKey: key)
    }

    /// True at most once per request, and only while it is fresh.
    static func consume(at date: Date = .now, from defaults: UserDefaults = VoyageAppGroup.defaults) -> Bool {
        let stamp = defaults.double(forKey: key)
        guard stamp > 0 else { return false }
        defaults.removeObject(forKey: key)
        let age = date.timeIntervalSince1970 - stamp
        return age >= 0 && age <= freshness
    }
}
