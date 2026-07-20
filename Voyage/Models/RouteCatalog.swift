import Foundation

/// Real-world carriers operating Voyage routes.
enum Carrier: String, CaseIterable, Codable {
    case jetBlue = "B6"
    case american = "AA"
    case united = "UA"
    case delta = "DL"
    case airCanada = "AC"
    case westJet = "WS"

    var name: String {
        switch self {
        case .jetBlue: return "JetBlue"
        case .american: return "American"
        case .united: return "United"
        case .delta: return "Delta"
        case .airCanada: return "Air Canada"
        case .westJet: return "WestJet"
        }
    }
}

/// One directed nonstop route: the real-world block time (gate to gate),
/// the carrier that actually flies it, and its typical daily departures.
struct NonstopRoute: Hashable {
    let originCode: String
    let destinationCode: String
    let carrier: Carrier
    /// Real-world block time in minutes. Directional: eastbound rides the
    /// jet stream and is shorter than the westbound return.
    let minutes: Int
    /// First departure's flight number; later departures step by 2.
    let baseFlightNumber: Int
    /// Typical local departure times, "HH:mm", ascending.
    let departureTimes: [String]

    var duration: TimeInterval { TimeInterval(minutes) * 60 }
    var flightNumberText: String { flightNumberText(departureIndex: 0) }

    func flightNumberText(departureIndex: Int) -> String {
        "\(carrier.rawValue) \(baseFlightNumber + departureIndex * 2)"
    }
}

/// A bookable upcoming departure — one row of the Google-Flights-style board.
struct DepartureOption: Identifiable, Hashable {
    let departure: Date
    let flightNumber: String
    let carrier: Carrier
    let itinerary: Itinerary

    var id: String { flightNumber + String(departure.timeIntervalSinceReferenceDate) }
    /// Wheels-down at the final destination (focus time + lounge break).
    var arrival: Date {
        departure.addingTimeInterval(itinerary.totalFocusDuration + itinerary.layoverDuration)
    }
}

/// Hardcoded real-world route data for the eight Voyage airports:
/// actual block times, the carriers that fly each pair, whether the popular
/// booking is nonstop or a connection, and typical departure schedules.
enum RouteCatalog {

    // MARK: Pair specs (undirected; both directions derived)

    private struct PairSpec {
        let a: String
        let b: String
        let carrier: Carrier
        /// a→b block minutes (westbound legs are longer than the return).
        let aToB: Int
        let bToA: Int
        /// a→b uses this number; b→a uses number + 1 (airline convention).
        let number: Int
        let aDeps: [String]
        let bDeps: [String]
    }

    private static let pairs: [PairSpec] = [
        PairSpec(a: "BOS", b: "JFK", carrier: .jetBlue, aToB: 80, bToA: 80, number: 816,
                 aDeps: ["06:30", "08:30", "10:30", "12:30", "14:30", "16:30", "18:30", "20:30"],
                 bDeps: ["07:00", "09:00", "11:00", "13:00", "15:00", "17:00", "19:00", "21:00"]),
        PairSpec(a: "BOS", b: "MIA", carrier: .jetBlue, aToB: 215, bToA: 205, number: 253,
                 aDeps: ["07:00", "10:59", "14:25", "19:30"],
                 bDeps: ["08:15", "12:40", "16:55", "20:59"]),
        PairSpec(a: "BOS", b: "SFO", carrier: .united, aToB: 405, bToA: 340, number: 1545,
                 aDeps: ["06:45", "10:15", "17:30"],
                 bDeps: ["07:05", "13:20", "22:55"]),
        PairSpec(a: "BOS", b: "LAX", carrier: .american, aToB: 390, bToA: 335, number: 117,
                 aDeps: ["07:00", "11:20", "18:05"],
                 bDeps: ["08:10", "14:35", "21:59"]),
        PairSpec(a: "BOS", b: "YYZ", carrier: .airCanada, aToB: 115, bToA: 110, number: 741,
                 aDeps: ["06:00", "09:40", "13:15", "17:45", "21:10"],
                 bDeps: ["06:35", "10:20", "14:05", "18:30"]),
        PairSpec(a: "BOS", b: "YVR", carrier: .airCanada, aToB: 385, bToA: 350, number: 305,
                 aDeps: ["08:10", "17:25"],
                 bDeps: ["09:05", "22:45"]),
        PairSpec(a: "JFK", b: "MIA", carrier: .american, aToB: 195, bToA: 185, number: 1279,
                 aDeps: ["06:59", "09:30", "12:45", "16:20", "19:59"],
                 bDeps: ["07:25", "11:10", "15:00", "18:40"]),
        PairSpec(a: "JFK", b: "SFO", carrier: .delta, aToB: 400, bToA: 330, number: 310,
                 aDeps: ["07:00", "09:45", "13:30", "17:15"],
                 bDeps: ["07:15", "10:50", "15:30", "22:59"]),
        PairSpec(a: "JFK", b: "LAX", carrier: .delta, aToB: 385, bToA: 325, number: 423,
                 aDeps: ["07:00", "08:30", "11:00", "14:15", "17:30", "20:45"],
                 bDeps: ["06:45", "09:15", "12:30", "15:45", "21:30"]),
        PairSpec(a: "JFK", b: "YYZ", carrier: .airCanada, aToB: 100, bToA: 95, number: 721,
                 aDeps: ["07:15", "11:30", "15:40", "19:50"],
                 bDeps: ["06:50", "10:35", "14:45", "18:55"]),
        PairSpec(a: "JFK", b: "YVR", carrier: .airCanada, aToB: 375, bToA: 335, number: 551,
                 aDeps: ["08:30", "18:45"],
                 bDeps: ["09:10", "22:30"]),
        PairSpec(a: "MIA", b: "SFO", carrier: .american, aToB: 400, bToA: 345, number: 621,
                 aDeps: ["07:30", "12:10", "18:20"],
                 bDeps: ["06:55", "13:05", "22:40"]),
        PairSpec(a: "MIA", b: "LAX", carrier: .american, aToB: 355, bToA: 305, number: 281,
                 aDeps: ["07:00", "10:45", "15:30", "20:15"],
                 bDeps: ["08:00", "12:20", "16:40", "22:55"]),
        PairSpec(a: "MIA", b: "YYZ", carrier: .airCanada, aToB: 205, bToA: 200, number: 1635,
                 aDeps: ["07:50", "13:25", "18:40"],
                 bDeps: ["08:30", "14:10", "19:20"]),
        PairSpec(a: "MIA", b: "YVR", carrier: .airCanada, aToB: 405, bToA: 365, number: 553,
                 aDeps: ["09:15", "19:30"],
                 bDeps: ["08:45", "20:10"]),
        PairSpec(a: "SFO", b: "LAX", carrier: .united, aToB: 85, bToA: 80, number: 424,
                 aDeps: ["06:00", "07:30", "09:00", "10:30", "12:00", "13:30",
                         "15:00", "16:30", "18:00", "19:30", "21:00"],
                 bDeps: ["06:15", "07:45", "09:15", "10:45", "12:15", "13:45",
                         "15:15", "16:45", "18:15", "19:45", "21:15"]),
        PairSpec(a: "SFO", b: "YYZ", carrier: .airCanada, aToB: 285, bToA: 325, number: 745,
                 aDeps: ["07:05", "13:40", "22:55"],
                 bDeps: ["08:20", "12:45", "18:10"]),
        PairSpec(a: "SFO", b: "YVR", carrier: .airCanada, aToB: 140, bToA: 135, number: 570,
                 aDeps: ["07:00", "11:30", "16:00", "20:30"],
                 bDeps: ["06:40", "10:55", "15:25", "19:50"]),
        PairSpec(a: "LAX", b: "YYZ", carrier: .airCanada, aToB: 280, bToA: 305, number: 793,
                 aDeps: ["08:00", "13:30", "22:45"],
                 bDeps: ["07:45", "12:15", "17:50"]),
        PairSpec(a: "LAX", b: "YVR", carrier: .airCanada, aToB: 170, bToA: 175, number: 555,
                 aDeps: ["07:30", "12:15", "17:45", "21:30"],
                 bDeps: ["06:55", "11:20", "16:05", "20:40"]),
        PairSpec(a: "YYZ", b: "YVR", carrier: .airCanada, aToB: 305, bToA: 265, number: 103,
                 aDeps: ["08:00", "10:30", "13:00", "17:00", "19:45"],
                 bDeps: ["07:00", "09:30", "12:30", "16:15", "18:50"]),
        PairSpec(a: "YYZ", b: "YQR", carrier: .airCanada, aToB: 185, bToA: 165, number: 1141,
                 aDeps: ["08:25", "13:10", "18:35", "22:40"],
                 bDeps: ["06:00", "10:15", "15:30", "19:05"]),
        PairSpec(a: "YVR", b: "YQR", carrier: .westJet, aToB: 115, bToA: 125, number: 226,
                 aDeps: ["07:10", "11:45", "16:20", "20:50"],
                 bDeps: ["06:30", "11:00", "15:35", "20:05"]),
    ]

    /// Pairs with no mainstream nonstop: the connection the real-world
    /// popular itinerary routes through.
    private static let connectionVias: [String: String] = [
        "BOS-YQR": "YYZ", "YQR-BOS": "YYZ",
        "JFK-YQR": "YYZ", "YQR-JFK": "YYZ",
        "MIA-YQR": "YYZ", "YQR-MIA": "YYZ",
        "SFO-YQR": "YVR", "YQR-SFO": "YVR",
        "LAX-YQR": "YVR", "YQR-LAX": "YVR",
    ]

    /// Directed nonstops keyed "ORG-DST".
    static let nonstops: [String: NonstopRoute] = {
        var table: [String: NonstopRoute] = [:]
        for pair in pairs {
            table["\(pair.a)-\(pair.b)"] = NonstopRoute(
                originCode: pair.a, destinationCode: pair.b, carrier: pair.carrier,
                minutes: pair.aToB, baseFlightNumber: pair.number, departureTimes: pair.aDeps
            )
            table["\(pair.b)-\(pair.a)"] = NonstopRoute(
                originCode: pair.b, destinationCode: pair.a, carrier: pair.carrier,
                minutes: pair.bToA, baseFlightNumber: pair.number + 1, departureTimes: pair.bDeps
            )
        }
        return table
    }()

    static func nonstop(from origin: Airport, to destination: Airport) -> NonstopRoute? {
        nonstops["\(origin.code)-\(destination.code)"]
    }

    /// The connection airport of the popular real-world routing,
    /// or nil when the pair has a popular nonstop.
    static func via(from origin: Airport, to destination: Airport) -> Airport? {
        connectionVias["\(origin.code)-\(destination.code)"].map(Airport.byCode)
    }

    // MARK: Departure board

    /// The next `count` real-schedule departures strictly after `date`.
    /// Connections use the first leg's schedule (you book the through-itinerary).
    static func upcomingDepartures(
        from origin: Airport,
        to destination: Airport,
        after date: Date = .now,
        count: Int = 5,
        calendar: Calendar = .current
    ) -> [DepartureOption] {
        let route: NonstopRoute?
        if let direct = nonstop(from: origin, to: destination) {
            route = direct
        } else if let via = via(from: origin, to: destination) {
            route = nonstop(from: origin, to: via)
        } else {
            route = nil
        }
        guard let route, count > 0 else { return [] }

        var options: [DepartureOption] = []
        var day = calendar.startOfDay(for: date)
        // Two calendar days always cover `count` ≤ daily departures × 2.
        for _ in 0..<3 where options.count < count {
            for (index, time) in route.departureTimes.enumerated() {
                guard options.count < count else { break }
                guard let departure = concreteDate(time, on: day, calendar: calendar),
                      departure > date else { continue }
                let number = route.flightNumberText(departureIndex: index)
                options.append(DepartureOption(
                    departure: departure,
                    flightNumber: number,
                    carrier: route.carrier,
                    itinerary: RoutePlanner.itinerary(from: origin, to: destination,
                                                      flightNumberOverride: number)
                ))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return options
    }

    private static func concreteDate(_ hhmm: String, on day: Date, calendar: Calendar) -> Date? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }
}
