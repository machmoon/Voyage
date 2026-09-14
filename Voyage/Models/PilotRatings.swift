import Foundation

// The traveler is a student pilot. Study hours are flight hours, and the
// next rating is the progression surface.
//
// Shaped after MyFlightbook (github.com/ericberman/MyFlightbookWeb):
//   MyFlightbook.Web/AppCode/Flights/Ratings/MilestoneProgress.cs
//     `MilestoneItem` carries Title, FARRef, Type (AchieveOnce, Count, Time),
//     Progress and Threshold; `IsSatisfied` is `Progress > 0` for AchieveOnce
//     and `Progress >= Threshold` otherwise. `MilestoneProgress` owns a Title
//     and a Milestones collection and folds one flight at a time through
//     `ExamineFlight`.
//   MyFlightbook.Web/AppCode/Flights/Ratings/PPLRatings.cs
//     `PPL61109Base.Init` declares each item with its threshold and the
//     paragraph of 61.109 it comes from; `ExamineFlight` adds Time and Count
//     items with `AddEvent` and marks the long cross-country with
//     `MatchFlightEvent` once a single flight clears every gate.
//
// Deviations, and why: MyFlightbook's items are mutable classes accumulated
// in place; here the columns are summed into a value once and the items are
// built from the sums, because SwiftUI re-evaluates and a pure function is
// easier to test. Entries are projected into `LoggedFlight` first, the way
// `FlightDataRecorder.RecordedFlight` does, so nothing here touches a
// `@Model` object. The calendar is injected and no code path reads
// `Date.now`.

/// The rungs, in order. Requirements are modelled on 14 CFR 61.83, 61.87,
/// 61.93 and 61.109; nothing above Private is defined here.
enum PilotRating: String, CaseIterable, Comparable {
    case student
    case solo
    case soloCrossCountry
    case privatePilot

    var title: String {
        switch self {
        case .student: return "Student pilot"
        case .solo: return "Solo"
        case .soloCrossCountry: return "Solo cross-country"
        case .privatePilot: return "Private pilot"
        }
    }

    /// The name used after "toward" and in the endorsement line, where the
    /// full title reads as a sentence fragment.
    var shortTitle: String {
        switch self {
        case .student: return "Student"
        case .solo: return "Solo"
        case .soloCrossCountry: return "Cross-country"
        case .privatePilot: return "Private"
        }
    }

    /// The paragraph of 14 CFR 61 the rung is modelled on.
    var reference: String {
        switch self {
        case .student: return "61.83"
        case .solo: return "61.87"
        case .soloCrossCountry: return "61.93"
        case .privatePilot: return "61.109"
        }
    }

    /// The cosmetic tier the rating unlocks. `LogbookStats.tier` takes the
    /// higher of this and the miles tier, so nobody is demoted.
    var cosmeticTier: FlyerTier {
        switch self {
        case .student: return .member
        case .solo: return .silver
        case .soloCrossCountry: return .gold
        case .privatePilot: return .platinum
        }
    }

    var next: PilotRating? {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self), index + 1 < all.count else { return nil }
        return all[index + 1]
    }

    private var ordinal: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    static func < (lhs: PilotRating, rhs: PilotRating) -> Bool {
        lhs.ordinal < rhs.ordinal
    }
}

/// One line of the next rating's checklist. `MilestoneItem` in MyFlightbook.
struct RatingRequirement: Identifiable, Equatable {
    enum Kind: Equatable {
        /// Seconds of flight time.
        case time
        /// Whole events.
        case count
        /// Satisfied by a single flight, once.
        case achieveOnce
    }

    let title: String
    /// The paragraph the requirement is modelled on, for the footnote.
    let reference: String
    let kind: Kind
    let progress: Double
    let threshold: Double

    var id: String { title }

    var isSatisfied: Bool {
        kind == .achieveOnce ? progress > 0 : progress >= threshold
    }

    /// 0 to 1, for a bar.
    var fraction: Double {
        guard threshold > 0 else { return isSatisfied ? 1 : 0 }
        return min(1, max(0, progress / threshold))
    }

    /// "2h 10m of 40h", "7 of 10 landings", or the title for achieve-once rows.
    var progressText: String {
        switch kind {
        case .time:
            return "\(PilotRatings.hoursText(progress)) of \(PilotRatings.hoursText(threshold))"
        case .count:
            return "\(Int(progress)) of \(Int(threshold)) \(title.lowercased())"
        case .achieveOnce:
            return title
        }
    }

    /// What is still owed: "37h 50m to go", "3 more landings", or the
    /// achieve-once description. Empty once satisfied.
    var remainingText: String {
        guard !isSatisfied else { return "" }
        switch kind {
        case .time:
            return "\(PilotRatings.hoursText(threshold - progress)) to go"
        case .count:
            let remaining = Int(threshold - progress)
            return "\(remaining) more \(remaining == 1 ? PilotRatings.singular(title) : title.lowercased())"
        case .achieveOnce:
            return title
        }
    }
}

/// One landed or diverted flight, flattened out of SwiftData into a value.
struct LoggedFlight: Equatable {
    let endedAt: Date
    let arrived: Bool
    let focusSeconds: TimeInterval
    let destinationCode: String
    let hasConnection: Bool

    init(entry: LogbookEntry) {
        endedAt = entry.date
        arrived = entry.completed
        focusSeconds = entry.focusSeconds
        destinationCode = entry.destinationCode
        hasConnection = entry.connectionCode != nil
    }

    init(endedAt: Date,
         arrived: Bool,
         focusSeconds: TimeInterval,
         destinationCode: String,
         hasConnection: Bool = false) {
        self.endedAt = endedAt
        self.arrived = arrived
        self.focusSeconds = focusSeconds
        self.destinationCode = destinationCode
        self.hasConnection = hasConnection
    }
}

/// Where the traveler stands: the highest rating every requirement of which
/// is met, and the checklist for the one after it.
struct RatingProgress: Equatable {
    let current: PilotRating
    let next: PilotRating?
    /// The next rating's checklist; empty at the top of the ladder.
    let nextRequirements: [RatingRequirement]

    var isAtTop: Bool { next == nil }

    /// The first open item on the next checklist, which is what a one-line
    /// surface shows.
    var firstOpenRequirement: RatingRequirement? {
        nextRequirements.first { !$0.isSatisfied }
    }

    /// "Student pilot · 12h 40m of 40h toward Private", or the rating alone
    /// at the top of the ladder.
    var summaryLine: String {
        guard let next, let open = firstOpenRequirement else { return current.title }
        return "\(current.title) · \(open.progressText) toward \(next.shortTitle)"
    }

    static func evaluate(entries: [LogbookEntry], calendar: Calendar = .current) -> RatingProgress {
        evaluate(flights: entries.map(LoggedFlight.init(entry:)), calendar: calendar)
    }

    static func evaluate(flights: [LoggedFlight], calendar: Calendar = .current) -> RatingProgress {
        let columns = PilotRatings.Columns(flights: flights, calendar: calendar)
        var current = PilotRating.student
        for rating in PilotRating.allCases.dropFirst() {
            guard PilotRatings.requirements(for: rating, columns: columns).allSatisfy(\.isSatisfied) else { break }
            current = rating
        }
        let next = current.next
        return RatingProgress(
            current: current,
            next: next,
            nextRequirements: next.map { PilotRatings.requirements(for: $0, columns: columns) } ?? []
        )
    }
}

enum PilotRatings {
    /// Forty hours of total time, 61.109(a).
    static let privateTotalSeconds: TimeInterval = 40 * 3_600
    /// The one long flight, 61.109(a)(5)(ii) stands in for the 150 nm solo
    /// cross-country. A connection counts because a two-leg itinerary is
    /// the app's own long flight.
    static let privateLongFlightSeconds: TimeInterval = 2 * 3_600

    /// The four columns, summed once. Only landed flights count.
    struct Columns: Equatable {
        let totalSeconds: TimeInterval
        let landings: Int
        let airports: Int
        let longestSeconds: TimeInterval
        let hasConnection: Bool
        let calendar: Calendar

        init(flights: [LoggedFlight], calendar: Calendar) {
            let landed = flights.filter(\.arrived)
            totalSeconds = landed.reduce(0) { $0 + $1.focusSeconds }
            landings = landed.count
            airports = Set(landed.map(\.destinationCode)).count
            longestSeconds = landed.map(\.focusSeconds).max() ?? 0
            hasConnection = landed.contains(where: \.hasConnection)
            self.calendar = calendar
        }
    }

    static func requirements(for rating: PilotRating, columns: Columns) -> [RatingRequirement] {
        switch rating {
        case .student:
            return []
        case .solo:
            return [
                RatingRequirement(title: "Landings", reference: "61.87", kind: .count,
                                  progress: Double(columns.landings), threshold: 3),
            ]
        case .soloCrossCountry:
            return [
                RatingRequirement(title: "Landings", reference: "61.93", kind: .count,
                                  progress: Double(columns.landings), threshold: 10),
                RatingRequirement(title: "Airports", reference: "61.93", kind: .count,
                                  progress: Double(columns.airports), threshold: 3),
            ]
        case .privatePilot:
            let longFlight = columns.longestSeconds >= privateLongFlightSeconds || columns.hasConnection
            return [
                RatingRequirement(title: "Total time", reference: "61.109(a)", kind: .time,
                                  progress: columns.totalSeconds, threshold: privateTotalSeconds),
                RatingRequirement(title: "Landings", reference: "61.109(a)", kind: .count,
                                  progress: Double(columns.landings), threshold: 10),
                RatingRequirement(title: "Airports", reference: "61.109(a)(5)", kind: .count,
                                  progress: Double(columns.airports), threshold: 5),
                RatingRequirement(title: "One flight of 2 hours, or a connection",
                                  reference: "61.109(a)(5)", kind: .achieveOnce,
                                  progress: longFlight ? 1 : 0, threshold: 1),
            ]
        }
    }

    /// The card footnote.
    static let footnote = "Modelled on 14 CFR 61.87, 61.93 and 61.109."

    /// "12h 40m", "40h", "0h". Whole hours drop the minutes.
    static func hoursText(_ seconds: TimeInterval) -> String {
        let minutes = Int((max(0, seconds) / 60).rounded(.down))
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }

    /// "Solo endorsement · 14 SEP 2026", the line the stamp page and the
    /// passport print when a landing raises the rating.
    static func endorsementLine(for rating: PilotRating, on date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd MMM yyyy"
        return "\(rating.shortTitle) endorsement · \(formatter.string(from: date).uppercased())"
    }

    fileprivate static func singular(_ title: String) -> String {
        let lower = title.lowercased()
        return lower.hasSuffix("s") ? String(lower.dropLast()) : lower
    }
}
