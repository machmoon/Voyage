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
         intentionsCompleted: [Bool] = []) {
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
    }

    var origin: Airport { Airport.byCode(originCode) }
    var destination: Airport { Airport.byCode(destinationCode) }
}

/// Frequent-flyer status, computed from lifetime completed miles.
enum FlyerTier: String, CaseIterable, Identifiable {
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
