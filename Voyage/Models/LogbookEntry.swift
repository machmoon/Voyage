import Foundation
import SwiftData

/// How a flight ended. Stored as a raw string on `LogbookEntry` so that
/// entries written by older builds (which recorded only `completed`) keep
/// loading; those decode as `.unknown` and the recorder excludes them from
/// any finding that needs a cause.
enum FlightOutcome: String, CaseIterable {
    /// Reached the gate at the final destination.
    case arrived
    /// Strict mode ended the flight: the app was backgrounded past the grace period.
    case interrupted
    /// The traveler left the flight deliberately from the in-flight screen.
    case leftEarly
    /// The layover boarding window expired.
    case missedConnection
    /// Written by a build that did not record a cause.
    case unknown

    var didArrive: Bool { self == .arrived }
}

/// A completed (or diverted) flight in the passport logbook.
@Model
final class LogbookEntry {
    var date: Date
    var originCode: String
    var destinationCode: String
    var connectionCode: String?
    var flightNumber: String
    var seat: String
    /// Miles actually earned: completed legs credit even on a diverted itinerary.
    var miles: Double
    var focusSeconds: TimeInterval
    var completed: Bool
    var intentions: [String]
    var intentionsCompleted: [Bool]

    // MARK: Flight-data-recorder signals
    //
    // Added after the first release. Every one has a default so SwiftData's
    // lightweight migration can open an existing store, and every reader
    // treats the default as "not recorded" rather than as a real value.

    /// Block time the itinerary was booked for, in seconds. `0` on rows
    /// written before this was recorded.
    var scheduledSeconds: TimeInterval = 0

    /// Wall-clock moment the boarding pass was torn and leg one began.
    /// `nil` on rows written before this was recorded; `date` is the
    /// moment the flight ended, which is not the same thing.
    var departedAt: Date?

    /// Raw `FlightOutcome`. Empty string on rows written before this
    /// was recorded, which decodes as `.unknown`.
    var outcomeRaw: String = ""

    /// How the flight ended. Falls back to `completed` for legacy rows so
    /// arrivals still read as arrivals; only the *cause* of a non-arrival
    /// is unrecoverable, and that reads as `.unknown`.
    var outcome: FlightOutcome {
        get {
            if let stored = FlightOutcome(rawValue: outcomeRaw) { return stored }
            return completed ? .arrived : .unknown
        }
        set {
            outcomeRaw = newValue.rawValue
            completed = newValue.didArrive
        }
    }

    init(date: Date = .now,
         originCode: String,
         destinationCode: String,
         connectionCode: String? = nil,
         flightNumber: String,
         seat: String,
         miles: Double,
         focusSeconds: TimeInterval,
         completed: Bool,
         intentions: [String] = [],
         intentionsCompleted: [Bool] = [],
         scheduledSeconds: TimeInterval = 0,
         departedAt: Date? = nil,
         outcome: FlightOutcome? = nil) {
        self.date = date
        self.originCode = originCode
        self.destinationCode = destinationCode
        self.connectionCode = connectionCode
        self.flightNumber = flightNumber
        self.seat = seat
        self.miles = miles
        self.focusSeconds = focusSeconds
        // An explicit outcome is the more specific fact and wins, so the two
        // can never disagree on a row this build wrote.
        self.completed = outcome?.didArrive ?? completed
        self.intentions = intentions
        self.intentionsCompleted = intentionsCompleted
        self.scheduledSeconds = scheduledSeconds
        self.departedAt = departedAt
        self.outcomeRaw = outcome?.rawValue ?? ""
    }

    var origin: Airport { Airport.byCode(originCode) }
    var destination: Airport { Airport.byCode(destinationCode) }
}

/// Frequent-flyer status, computed from lifetime completed miles.
enum FlyerTier: String, CaseIterable, Identifiable, Comparable {
    case member = "Member"
    case silver = "Silver"
    case gold = "Gold"
    case platinum = "Platinum"

    var id: String { rawValue }

    var threshold: Double {
        switch self {
        case .member: return 0
        case .silver: return 5_000
        case .gold: return 15_000
        case .platinum: return 40_000
        }
    }

    static func tier(forMiles miles: Double) -> FlyerTier {
        allCases.last { miles >= $0.threshold } ?? .member
    }

    static func < (lhs: FlyerTier, rhs: FlyerTier) -> Bool {
        lhs.threshold < rhs.threshold
    }

    var next: FlyerTier? {
        switch self {
        case .member: return .silver
        case .silver: return .gold
        case .gold: return .platinum
        case .platinum: return nil
        }
    }

    /// Cosmetic perks unlocked at this tier and below.
    var perkDescription: String {
        switch self {
        case .member: return "Economy cabin"
        case .silver: return "Business-class seats"
        case .gold: return "Sunset window scenes"
        case .platinum: return "Aurora red-eyes & first-class chime"
        }
    }
}

enum LogbookStats {
    static func totalMiles(_ entries: [LogbookEntry]) -> Double {
        entries.reduce(0) { $0 + $1.miles }
    }

    static func tier(_ entries: [LogbookEntry]) -> FlyerTier {
        FlyerTier.tier(forMiles: totalMiles(entries))
    }

    /// Consecutive-day streak of completed flights ending today or yesterday.
    static func streakDays(_ entries: [LogbookEntry], calendar: Calendar = .current) -> Int {
        let days = Set(entries.filter(\.completed).map { calendar.startOfDay(for: $0.date) })
        guard !days.isEmpty else { return 0 }
        var cursor = calendar.startOfDay(for: .now)
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  days.contains(yesterday) else { return 0 }
            cursor = yesterday
        }
        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }
}
