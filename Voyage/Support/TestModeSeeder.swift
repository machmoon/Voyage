import Foundation
import SwiftData

/// Populates the logbook with a believable few weeks of usage so demos, App
/// Store screenshots, and design review show a lived-in account (streaks,
/// Gold tier, a varied passport) instead of an empty state.
enum TestModeSeeder {

    /// One scripted flight in the demo history.
    private struct Flight {
        let dayOffset: Int          // days before today
        let hour: Int               // local departure hour
        let from: String
        let to: String
        let seat: String
        let intentions: [String]
        var completed: Bool = true
    }

    /// A ~3½-week history: mostly-completed daily focus flights with a current
    /// streak, a couple of diversions, and enough miles to reach Gold. Newest
    /// first isn't required — dates are stamped from the offsets.
    private static let script: [Flight] = [
        // This week — an active 5-day streak ending today.
        Flight(dayOffset: 0, hour: 9,  from: "BOS", to: "JFK", seat: "14A", intentions: ["Finish problem set 6", "Review lecture notes"]),
        Flight(dayOffset: 0, hour: 20, from: "BOS", to: "YYZ", seat: "7C",  intentions: ["Draft essay intro"]),
        Flight(dayOffset: 1, hour: 10, from: "BOS", to: "MIA", seat: "22F", intentions: ["Read Chapter 9", "Outline lab report"]),
        Flight(dayOffset: 2, hour: 8,  from: "BOS", to: "JFK", seat: "3A",  intentions: ["Deep work sprint"]),
        Flight(dayOffset: 3, hour: 14, from: "BOS", to: "LAX", seat: "18C", intentions: ["Study for midterm", "Flashcards"]),
        Flight(dayOffset: 4, hour: 19, from: "BOS", to: "YQR", seat: "11D", intentions: ["Write draft"]),
        // Last week.
        Flight(dayOffset: 6, hour: 9,  from: "BOS", to: "JFK", seat: "9A",  intentions: ["Problem set 5"]),
        Flight(dayOffset: 7, hour: 11, from: "JFK", to: "MIA", seat: "16B", intentions: ["Read Chapter 8"], completed: false),
        Flight(dayOffset: 8, hour: 13, from: "BOS", to: "YVR", seat: "2A",  intentions: ["Research reading", "Take notes"]),
        Flight(dayOffset: 9, hour: 10, from: "BOS", to: "YYZ", seat: "20F", intentions: ["Grade problem sets"]),
        Flight(dayOffset: 10, hour: 15, from: "BOS", to: "LAX", seat: "6C", intentions: ["Prep presentation"]),
        // Two weeks ago.
        Flight(dayOffset: 13, hour: 9,  from: "BOS", to: "JFK", seat: "12A", intentions: ["Chapter 7 reading"]),
        Flight(dayOffset: 14, hour: 18, from: "BOS", to: "MIA", seat: "24D", intentions: ["Draft methods section"]),
        Flight(dayOffset: 15, hour: 8,  from: "BOS", to: "YQR", seat: "4A",  intentions: ["Deep work"], completed: false),
        Flight(dayOffset: 16, hour: 12, from: "BOS", to: "JFK", seat: "8C",  intentions: ["Problem set 4", "Office hours prep"]),
        Flight(dayOffset: 18, hour: 10, from: "BOS", to: "YYZ", seat: "19A", intentions: ["Literature review"]),
        // Three-plus weeks ago — the account's first flights.
        Flight(dayOffset: 20, hour: 14, from: "BOS", to: "LAX", seat: "15F", intentions: ["Read syllabus", "Set up notes"]),
        Flight(dayOffset: 22, hour: 9,  from: "BOS", to: "JFK", seat: "10A", intentions: ["First study session"]),
        Flight(dayOffset: 24, hour: 11, from: "BOS", to: "MIA", seat: "21C", intentions: ["Intro reading"]),
    ]

    /// True when the store already holds seeded-looking history, so the UI can
    /// offer "clear" instead of re-seeding.
    static func hasSeededData(in context: ModelContext) -> Bool {
        let count = (try? context.fetchCount(FetchDescriptor<LogbookEntry>())) ?? 0
        return count > 0
    }

    /// Replaces the logbook with the scripted demo history.
    static func seed(into context: ModelContext, calendar: Calendar = .current) {
        clear(from: context)

        for flight in script {
            guard let date = departureDate(dayOffset: flight.dayOffset, hour: flight.hour, calendar: calendar) else { continue }
            let origin = Airport.byCode(flight.from)
            let destination = Airport.byCode(flight.to)
            let itinerary = RoutePlanner.itinerary(from: origin, to: destination)

            // Diversions credit only the portion flown before the bail-out.
            let flownFraction = flight.completed ? 1.0 : Double.random(in: 0.35...0.7)
            let entry = LogbookEntry(
                date: date,
                originCode: origin.code,
                destinationCode: destination.code,
                connectionCode: itinerary.connection?.code,
                flightNumber: itinerary.primaryFlightNumber,
                seat: flight.seat,
                miles: itinerary.totalMiles * flownFraction,
                focusSeconds: itinerary.totalFocusDuration * flownFraction,
                completed: flight.completed,
                intentions: flight.intentions,
                intentionsCompleted: flight.intentions.map { _ in flight.completed }
            )
            context.insert(entry)
        }
        try? context.save()
    }

    /// Removes every logbook entry.
    static func clear(from context: ModelContext) {
        guard let entries = try? context.fetch(FetchDescriptor<LogbookEntry>()) else { return }
        for entry in entries { context.delete(entry) }
        try? context.save()
    }

    private static func departureDate(dayOffset: Int, hour: Int, calendar: Calendar) -> Date? {
        let midnight = calendar.startOfDay(for: .now)
        guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: midnight) else { return nil }
        return calendar.date(byAdding: .hour, value: hour, to: day)
    }
}
