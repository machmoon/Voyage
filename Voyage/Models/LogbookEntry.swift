import Foundation
import SwiftData

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
    /// Optional caption added at share time (Strava-style activity description).
    var shareCaption: String?
    /// Optional title given to the flight when it is posted to the logbook.
    var postTitle: String?
    /// World choices are optional to keep existing logbook stores lightweight-migration compatible.
    var aircraftRaw: String?
    var weatherSnapshotData: Data?
    var departureProfileRaw: String?
    var worldRevision: String?
    var routeSamplesData: Data?
    /// Immutable real-world-twin inputs. Optional fields preserve lightweight
    /// migration for logbook rows written before trajectory revision 1.
    var departureCorridorID: String?
    var arrivalCorridorID: String?
    var environmentSnapshotData: Data?
    var trajectorySamplesData: Data?

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
         shareCaption: String? = nil,
         postTitle: String? = nil,
         aircraft: AircraftProfile? = nil,
         weatherSnapshot: WeatherSnapshot? = nil,
         departureProfile: DepartureProfile? = nil,
         worldRevision: String? = nil,
         routeSamples: [ReplayRouteSample]? = nil,
         departureCorridorID: String? = nil,
         arrivalCorridorID: String? = nil,
         environmentSnapshots: [FlightEnvironmentSnapshot]? = nil,
         trajectoryLegSamples: [[FlightTrajectorySample]]? = nil) {
        self.date = date
        self.originCode = originCode
        self.destinationCode = destinationCode
        self.connectionCode = connectionCode
        self.flightNumber = flightNumber
        self.seat = seat
        self.miles = miles
        self.focusSeconds = focusSeconds
        self.completed = completed
        self.intentions = intentions
        self.intentionsCompleted = intentionsCompleted
        self.shareCaption = shareCaption
        self.postTitle = postTitle
        self.aircraftRaw = aircraft?.rawValue
        self.weatherSnapshotData = weatherSnapshot.flatMap { try? JSONEncoder().encode($0) }
        self.departureProfileRaw = departureProfile?.rawValue
        self.worldRevision = worldRevision
        self.routeSamplesData = routeSamples.flatMap { try? JSONEncoder().encode($0) }
        self.departureCorridorID = departureCorridorID
        self.arrivalCorridorID = arrivalCorridorID
        self.environmentSnapshotData = environmentSnapshots.flatMap { try? JSONEncoder().encode($0) }
        self.trajectorySamplesData = trajectoryLegSamples.flatMap { try? JSONEncoder().encode($0) }
    }

    var origin: Airport { Airport.byCode(originCode) }
    var destination: Airport { Airport.byCode(destinationCode) }
    var aircraft: AircraftProfile { AircraftProfile(rawValue: aircraftRaw ?? "") ?? .voyageClassic }
    var weatherSnapshot: WeatherSnapshot? {
        weatherSnapshotData.flatMap { try? JSONDecoder().decode(WeatherSnapshot.self, from: $0) }
    }
    var departureProfile: DepartureProfile? {
        departureProfileRaw.flatMap(DepartureProfile.init(rawValue:))
    }
    var routeSamples: [ReplayRouteSample] {
        routeSamplesData.flatMap { try? JSONDecoder().decode([ReplayRouteSample].self, from: $0) } ?? []
    }
    var trajectoryRevision: String? { worldRevision }
    var environmentSnapshots: [FlightEnvironmentSnapshot] {
        environmentSnapshotData.flatMap {
            try? JSONDecoder().decode([FlightEnvironmentSnapshot].self, from: $0)
        } ?? []
    }
    var trajectoryLegSamples: [[FlightTrajectorySample]] {
        trajectorySamplesData.flatMap {
            try? JSONDecoder().decode([[FlightTrajectorySample]].self, from: $0)
        } ?? []
    }
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

    /// Completed flights in one local calendar week, oldest first, ready for
    /// a deterministic multi-flight replay.
    static func completedFlights(
        _ entries: [LogbookEntry],
        inWeekContaining date: Date = .now,
        calendar: Calendar = .current
    ) -> [LogbookEntry] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return [] }
        return entries
            .filter { $0.completed && interval.contains($0.date) }
            .sorted { $0.date < $1.date }
    }

    /// Time-of-day title pre-filled into the post composer. The user can
    /// overwrite it before posting.
    static func defaultPostTitle(
        at date: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12: return "Morning flight"
        case 12..<17: return "Afternoon flight"
        case 17..<22: return "Evening flight"
        default: return "Red-eye flight"
        }
    }

    /// True when `entry` holds the longest focus of any completed flight on the
    /// same directed route. `among` may include `entry` itself, since callers
    /// typically pass the whole logbook after the entry has been saved.
    static func isPersonalBestFocus(
        _ entry: LogbookEntry,
        among entries: [LogbookEntry]
    ) -> Bool {
        guard entry.completed else { return false }
        return entries
            .filter {
                $0 !== entry
                    && $0.completed
                    && $0.originCode == entry.originCode
                    && $0.destinationCode == entry.destinationCode
            }
            .allSatisfy { $0.focusSeconds < entry.focusSeconds }
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
