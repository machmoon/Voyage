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

    /// Raw `PilotRating` of the endorsement this landing earned, when it
    /// raised the rating. `nil` on every other row, including rows written
    /// before ratings existed.
    var endorsementRaw: String?

    /// Answers to the post-landing retrieval check ("Anything to declare?"),
    /// up to three, blanks dropped. Empty when skipped or before it existed.
    var declarations: [String] = []

    /// One 3-letter bag tag code per intention ("OCP"), parallel to
    /// `intentions`. Empty on rows written before tags carried codes; the
    /// default keeps SwiftData's lightweight migration working.
    var tagCodes: [String] = []

    /// The rating this landing completed, if any.
    var endorsement: PilotRating? {
        get { endorsementRaw.flatMap(PilotRating.init(rawValue:)) }
        set { endorsementRaw = newValue?.rawValue }
    }

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
         trajectoryLegSamples: [[FlightTrajectorySample]]? = nil,
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
        self.scheduledSeconds = scheduledSeconds
        self.departedAt = departedAt
        self.outcomeRaw = outcome?.rawValue ?? ""
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

/// Frequent-flyer status, computed from status miles: the flown distance plus
/// the 500-mile welcome bonus (`VoyageMiles`).
///
/// Every threshold sits 500 above the original 5,000 / 15,000 / 40,000, so
/// the welcome bonus changes how progress *looks* (a card that starts with
/// stamps on it, Nunes & Drèze 2006) without changing anyone's tier: a
/// traveler with any logbook entry has the bonus, and m + 500 crosses a
/// new threshold exactly where m crossed the old one.
enum FlyerTier: String, CaseIterable, Identifiable, Comparable {
    case member = "Member"
    case silver = "Silver"
    case gold = "Gold"
    case platinum = "Platinum"

    var id: String { rawValue }

    var threshold: Double {
        switch self {
        case .member: return 0
        case .silver: return 5_500
        case .gold: return 15_500
        case .platinum: return 40_500
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
        case .silver: return "First-class seats"
        case .gold: return "Sunset scenes & priority bag tags"
        case .platinum: return "Aurora, livery tags & first-class chime"
        }
    }
}

enum LogbookStats {
    static func totalMiles(_ entries: [LogbookEntry]) -> Double {
        entries.reduce(0) { $0 + $1.miles }
    }

    /// The higher of the miles tier and the tier the pilot rating unlocks
    /// (Solo is Silver, Solo cross-country is Gold, Private is Platinum).
    /// Both stay, permanently: dropping miles would demote a traveler who
    /// reached Platinum by miles before ratings existed.
    static func tier(_ entries: [LogbookEntry]) -> FlyerTier {
        let byMiles = FlyerTier.tier(forMiles: VoyageMiles.statusMiles(entries))
        let byRating = RatingProgress.evaluate(entries: entries).current.cosmeticTier
        return max(byMiles, byRating)
    }

    /// Focus time of landed flights, the "total time" column of the ratings.
    static func totalFocusSeconds(_ entries: [LogbookEntry]) -> TimeInterval {
        entries.filter(\.completed).reduce(0) { $0 + $1.focusSeconds }
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

    /// The streak, with weather delays: rain-day grace tokens in airline
    /// language. The flight was delayed, not cancelled.
    ///
    /// Silverman & Barasch (2023, J. Consumer Research 49(6)) found visible
    /// streaks keep people going, and that being able to repair a broken one
    /// softens the blow. Voyage's repair is earned and free, never sold:
    /// every `delayEarnDays` days flown in a row bank one weather delay (at
    /// most `delayCap`), and a missed day spends one automatically. A token
    /// covers exactly one day; with none left, the streak resets and any
    /// banked tokens go with it.
    struct Streak: Equatable {
        /// Days with a landing in the current streak (delay days not counted).
        let days: Int
        /// Weather delays banked now, shown as cloud chips.
        let tokens: Int
        /// Delays spent inside the current streak.
        let delaysUsed: Int
        /// Yesterday was covered by a delay and today has no landing yet.
        let delayedYesterday: Bool

        static let none = Streak(days: 0, tokens: 0, delaysUsed: 0, delayedYesterday: false)

        /// "6-day streak", "6-day streak · weather delay", nil under 2 days.
        var line: String? {
            guard days >= 2 else { return nil }
            return delayedYesterday ? "\(days)-day streak · weather delay" : "\(days)-day streak"
        }
    }

    static let delayEarnDays = 5
    static let delayCap = 2

    static func streak(_ entries: [LogbookEntry],
                       calendar: Calendar = .current,
                       now: Date = .now) -> Streak {
        let flown = Set(entries.filter(\.completed).map { calendar.startOfDay(for: $0.date) })
        guard let first = flown.min() else { return .none }
        let today = calendar.startOfDay(for: now)
        guard first <= today else { return .none }

        var days = 0, tokens = 0, used = 0
        var lastWasDelay = false
        var day = first
        while day <= today {
            if flown.contains(day) {
                days += 1
                lastWasDelay = false
                if days % delayEarnDays == 0 { tokens = min(delayCap, tokens + 1) }
            } else if day == today {
                // Today is still in progress: not a miss yet.
                break
            } else if days > 0 && tokens > 0 {
                tokens -= 1
                used += 1
                lastWasDelay = true
            } else {
                days = 0; tokens = 0; used = 0
                lastWasDelay = false
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return Streak(days: days, tokens: tokens, delaysUsed: used,
                      delayedYesterday: lastWasDelay && !flown.contains(today))
    }

    /// Consecutive-day streak of completed flights ending today or yesterday.
    /// `now` is injected so a test can pin the day it is asked about.
    static func streakDays(_ entries: [LogbookEntry],
                           calendar: Calendar = .current,
                           now: Date = .now) -> Int {
        let days = Set(entries.filter(\.completed).map { calendar.startOfDay(for: $0.date) })
        guard !days.isEmpty else { return 0 }
        var cursor = calendar.startOfDay(for: now)
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
