import Foundation
import SwiftData

/// A synthetic logbook, written only when the app is launched with
/// `-VoyageRecorderDemo`, so the flight data recorder can be reviewed and
/// screenshotted without flying a semester of real sessions.
///
/// It is deliberately not a "nice" logbook. Flights fail in the traveler's
/// best hour and land in their worst, so no group is a perfect record and
/// every confidence band has visible width. Numbers that only ever look
/// clean are not a fair test of a screen whose whole job is to show
/// uncertainty honestly.
///
/// It loads into an in-memory store, never the real one, so a demo launch
/// cannot contaminate anybody's actual logbook.
enum RecorderDemoLogbook {

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-VoyageRecorderDemo")
    }

    /// Anchored to a fixed date so a capture taken on any day looks the same.
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private static func departure(day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 2 + day
        components.hour = hour
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    private struct Spec {
        let hour: Int
        let outcome: FlightOutcome
        let minutes: Int
        let bag: String
        let claimed: Bool
        let route: (String, String, String)
    }

    /// Roughly a semester for someone who studies after dinner: mostly
    /// short evening sessions that land, a handful of late-night long hauls
    /// that mostly do not, and a few afternoons.
    ///
    /// The group sizes are lopsided on purpose. A finding that compares 38
    /// flights against 6 is what makes the confidence bands do their job on
    /// screen: the large group's band is a narrow mark, the small group's is
    /// a wide smear, and the difference is legible without reading a number.
    private static var specs: [Spec] {
        var specs: [Spec] = []
        let evening = ("BOS", "JFK", "VOY 118")
        let longHaul = ("JFK", "LAX", "VOY 402")
        let afternoon = ("SFO", "SEA", "VOY 231")

        // 44 evening sessions: 38 land, 6 do not. No perfect records.
        for index in 0..<44 {
            let outcome: FlightOutcome
            switch index {
            case 6, 17, 28, 39: outcome = .interrupted
            case 11, 34: outcome = .leftEarly
            default: outcome = .arrived
            }
            specs.append(Spec(hour: 19, outcome: outcome, minutes: 42,
                              bag: "Reading", claimed: outcome.didArrive, route: evening))
        }
        // 7 late-night long hauls: 1 lands.
        for index in 0..<7 {
            let outcome: FlightOutcome = index == 3
                ? .arrived
                : (index.isMultiple(of: 3) ? .leftEarly : .interrupted)
            specs.append(Spec(hour: 23, outcome: outcome, minutes: 195,
                              bag: "Calculus", claimed: false, route: longHaul))
        }
        // 6 afternoons. The calculus bag lands and is never claimed.
        for index in 0..<6 {
            specs.append(Spec(hour: 15, outcome: index == 5 ? .interrupted : .arrived, minutes: 55,
                              bag: "Calculus", claimed: false, route: afternoon))
        }
        return specs
    }

    static func entries() -> [LogbookEntry] {
        specs.enumerated().map { day, spec in
            let departed = departure(day: day, hour: spec.hour)
            let scheduled = TimeInterval(spec.minutes * 60)
            // A flight that did not land credits only the time it flew.
            let flown = spec.outcome.didArrive ? scheduled : scheduled * 0.4
            return LogbookEntry(
                date: departed.addingTimeInterval(flown),
                originCode: spec.route.0,
                destinationCode: spec.route.1,
                flightNumber: spec.route.2,
                seat: "C10",
                miles: spec.outcome.didArrive ? Double(spec.minutes) * 7.4 : 0,
                focusSeconds: flown,
                completed: spec.outcome.didArrive,
                intentions: [spec.bag],
                intentionsCompleted: [spec.claimed],
                scheduledSeconds: scheduled,
                departedAt: departed,
                outcome: spec.outcome
            )
        }
    }

    /// An in-memory container preloaded with the demo logbook.
    @MainActor
    static func makeContainer() throws -> ModelContainer {
        let container = try ModelContainer(
            for: LogbookEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        for entry in entries() { container.mainContext.insert(entry) }
        try? container.mainContext.save()
        return container
    }
}
