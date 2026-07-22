import Foundation

/// The fictional carriers operating Voyage routes. Block times, airports, and
/// departure banks are drawn from the real world; the airlines flying them are
/// invented, so no real carrier's marks appear anywhere in the product.
enum Carrier: String, CaseIterable, Codable {
    case harborline = "HN"
    case meridian = "MD"
    case voyageAir = "VG"
    case cascadia = "CD"
    case northstar = "NS"
    case summit = "SM"

    var name: String {
        switch self {
        case .harborline: return "Harborline"
        case .meridian: return "Meridian"
        case .voyageAir: return "Voyage Air"
        case .cascadia: return "Cascadia"
        case .northstar: return "Northstar"
        case .summit: return "Summit"
        }
    }
}

/// One directed nonstop route: the real-world block time (gate to gate),
/// the fictional carrier assigned to it, and its typical daily departures.
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
    /// Other airlines flying the same pair. Busy routes are fought over, and a
    /// board showing one airline all day reads like a private timetable.
    var competitors: [Carrier] = []

    var duration: TimeInterval { TimeInterval(minutes) * 60 }
    var flightNumberText: String { flightNumberText(departureIndex: 0) }

    /// Departures alternate between the airlines serving the pair, so
    /// consecutive rows on the board come from different carriers.
    func carrier(departureIndex: Int) -> Carrier {
        let airlines = [carrier] + competitors
        return airlines[departureIndex % airlines.count]
    }

    func flightNumberText(departureIndex: Int) -> String {
        "\(carrier(departureIndex: departureIndex).rawValue) \(baseFlightNumber + departureIndex * 2)"
    }
}

/// A bookable upcoming departure — one row of the Google-Flights-style board.
struct DepartureOption: Identifiable, Hashable {
    let departure: Date
    let flightNumber: String
    let carrier: Carrier
    let itinerary: Itinerary
    /// Curated rows are based on common carrier service and are not live status.
    var isVerifiedLive: Bool = false

    var id: String { flightNumber + String(departure.timeIntervalSinceReferenceDate) }
    /// Wheels-down at the final destination (focus time + lounge break).
    var arrival: Date {
        departure.addingTimeInterval(itinerary.totalFocusDuration + itinerary.layoverDuration)
    }
}

/// Hardcoded real-world route data for the eight Voyage airports:
/// actual block times, the fictional carrier assigned to each pair, whether the popular
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
        /// Other airlines on the same pair, for routes that are genuinely fought over.
        var competitors: [Carrier] = []
    }

    private static let pairs: [PairSpec] = [
        PairSpec(a: "BOS", b: "JFK", carrier: .harborline, aToB: 80, bToA: 80, number: 816,
                 aDeps: ["06:30", "08:30", "10:30", "12:30", "14:30", "16:30", "18:30", "20:30"],
                 bDeps: ["07:00", "09:00", "11:00", "13:00", "15:00", "17:00", "19:00", "21:00"],
                 competitors: [.meridian, .voyageAir]),
        PairSpec(a: "BOS", b: "MIA", carrier: .harborline, aToB: 215, bToA: 205, number: 253,
                 aDeps: ["07:00", "10:59", "14:25", "19:30"],
                 bDeps: ["08:15", "12:40", "16:55", "20:59"]),
        PairSpec(a: "BOS", b: "SFO", carrier: .voyageAir, aToB: 405, bToA: 340, number: 1545,
                 aDeps: ["06:45", "10:15", "17:30"],
                 bDeps: ["07:05", "13:20", "22:55"]),
        PairSpec(a: "BOS", b: "LAX", carrier: .meridian, aToB: 390, bToA: 335, number: 117,
                 aDeps: ["07:00", "11:20", "18:05"],
                 bDeps: ["08:10", "14:35", "21:59"]),
        PairSpec(a: "BOS", b: "YYZ", carrier: .northstar, aToB: 115, bToA: 110, number: 741,
                 aDeps: ["06:00", "09:40", "13:15", "17:45", "21:10"],
                 bDeps: ["06:35", "10:20", "14:05", "18:30"]),
        PairSpec(a: "BOS", b: "YVR", carrier: .northstar, aToB: 385, bToA: 350, number: 305,
                 aDeps: ["08:10", "17:25"],
                 bDeps: ["09:05", "22:45"]),
        PairSpec(a: "JFK", b: "MIA", carrier: .meridian, aToB: 195, bToA: 185, number: 1279,
                 aDeps: ["06:59", "09:30", "12:45", "16:20", "19:59"],
                 bDeps: ["07:25", "11:10", "15:00", "18:40"]),
        PairSpec(a: "JFK", b: "SFO", carrier: .cascadia, aToB: 400, bToA: 330, number: 310,
                 aDeps: ["07:00", "09:45", "13:30", "17:15"],
                 bDeps: ["07:15", "10:50", "15:30", "22:59"]),
        PairSpec(a: "JFK", b: "LAX", carrier: .cascadia, aToB: 385, bToA: 325, number: 423,
                 aDeps: ["07:00", "08:30", "11:00", "14:15", "17:30", "20:45"],
                 bDeps: ["06:45", "09:15", "12:30", "15:45", "21:30"],
                 competitors: [.voyageAir, .meridian]),
        PairSpec(a: "JFK", b: "YYZ", carrier: .northstar, aToB: 100, bToA: 95, number: 721,
                 aDeps: ["07:15", "11:30", "15:40", "19:50"],
                 bDeps: ["06:50", "10:35", "14:45", "18:55"]),
        PairSpec(a: "JFK", b: "YVR", carrier: .northstar, aToB: 375, bToA: 335, number: 551,
                 aDeps: ["08:30", "18:45"],
                 bDeps: ["09:10", "22:30"]),
        PairSpec(a: "MIA", b: "SFO", carrier: .meridian, aToB: 400, bToA: 345, number: 621,
                 aDeps: ["07:30", "12:10", "18:20"],
                 bDeps: ["06:55", "13:05", "22:40"]),
        PairSpec(a: "MIA", b: "LAX", carrier: .meridian, aToB: 355, bToA: 305, number: 281,
                 aDeps: ["07:00", "10:45", "15:30", "20:15"],
                 bDeps: ["08:00", "12:20", "16:40", "22:55"]),
        PairSpec(a: "MIA", b: "YYZ", carrier: .northstar, aToB: 205, bToA: 200, number: 1635,
                 aDeps: ["07:50", "13:25", "18:40"],
                 bDeps: ["08:30", "14:10", "19:20"]),
        PairSpec(a: "MIA", b: "YVR", carrier: .northstar, aToB: 405, bToA: 365, number: 553,
                 aDeps: ["09:15", "19:30"],
                 bDeps: ["08:45", "20:10"]),
        PairSpec(a: "SFO", b: "LAX", carrier: .voyageAir, aToB: 85, bToA: 80, number: 424,
                 aDeps: ["06:00", "07:30", "09:00", "10:30", "12:00", "13:30",
                         "15:00", "16:30", "18:00", "19:30", "21:00"],
                 bDeps: ["06:15", "07:45", "09:15", "10:45", "12:15", "13:45",
                         "15:15", "16:45", "18:15", "19:45", "21:15"],
                 competitors: [.cascadia, .meridian]),
        PairSpec(a: "SFO", b: "YYZ", carrier: .northstar, aToB: 285, bToA: 325, number: 745,
                 aDeps: ["07:05", "13:40", "22:55"],
                 bDeps: ["08:20", "12:45", "18:10"]),
        PairSpec(a: "SFO", b: "YVR", carrier: .northstar, aToB: 140, bToA: 135, number: 570,
                 aDeps: ["07:00", "11:30", "16:00", "20:30"],
                 bDeps: ["06:40", "10:55", "15:25", "19:50"]),
        PairSpec(a: "LAX", b: "YYZ", carrier: .northstar, aToB: 280, bToA: 305, number: 793,
                 aDeps: ["08:00", "13:30", "22:45"],
                 bDeps: ["07:45", "12:15", "17:50"]),
        PairSpec(a: "LAX", b: "YVR", carrier: .northstar, aToB: 170, bToA: 175, number: 555,
                 aDeps: ["07:30", "12:15", "17:45", "21:30"],
                 bDeps: ["06:55", "11:20", "16:05", "20:40"]),
        PairSpec(a: "YYZ", b: "YVR", carrier: .northstar, aToB: 305, bToA: 265, number: 103,
                 aDeps: ["08:00", "10:30", "13:00", "17:00", "19:45"],
                 bDeps: ["07:00", "09:30", "12:30", "16:15", "18:50"]),
        PairSpec(a: "YYZ", b: "YQR", carrier: .northstar, aToB: 185, bToA: 165, number: 1141,
                 aDeps: ["08:25", "13:10", "18:35", "22:40"],
                 bDeps: ["06:00", "10:15", "15:30", "19:05"]),
        PairSpec(a: "YVR", b: "YQR", carrier: .summit, aToB: 115, bToA: 125, number: 226,
                 aDeps: ["07:10", "11:45", "16:20", "20:50"],
                 bDeps: ["06:30", "11:00", "15:35", "20:05"]),

        // Seattle
        PairSpec(a: "BOS", b: "SEA", carrier: .cascadia, aToB: 380, bToA: 320, number: 631,
                 aDeps: ["07:30", "11:45", "18:15"],
                 bDeps: ["07:15", "13:00", "22:40"]),
        PairSpec(a: "JFK", b: "SEA", carrier: .cascadia, aToB: 370, bToA: 315, number: 645,
                 aDeps: ["07:00", "10:40", "16:25", "19:50"],
                 bDeps: ["06:50", "11:35", "16:10", "22:20"]),
        PairSpec(a: "MIA", b: "SEA", carrier: .cascadia, aToB: 400, bToA: 350, number: 662,
                 aDeps: ["08:20", "16:45"],
                 bDeps: ["07:40", "18:05"]),
        PairSpec(a: "SFO", b: "SEA", carrier: .cascadia, aToB: 125, bToA: 120, number: 508,
                 aDeps: ["06:15", "08:45", "11:15", "14:00", "16:30", "19:00", "21:20"],
                 bDeps: ["06:00", "08:30", "11:00", "13:45", "16:15", "18:45", "21:05"]),
        PairSpec(a: "LAX", b: "SEA", carrier: .cascadia, aToB: 170, bToA: 160, number: 512,
                 aDeps: ["06:30", "09:20", "12:10", "15:40", "18:50", "21:30"],
                 bDeps: ["06:10", "09:00", "11:50", "15:15", "18:25", "21:00"]),
        PairSpec(a: "SEA", b: "YVR", carrier: .cascadia, aToB: 70, bToA: 70, number: 246,
                 aDeps: ["07:20", "11:50", "16:30", "20:15"],
                 bDeps: ["06:45", "11:10", "15:50", "19:35"]),
        PairSpec(a: "SEA", b: "YYZ", carrier: .northstar, aToB: 275, bToA: 310, number: 767,
                 aDeps: ["07:45", "13:20", "22:30"],
                 bDeps: ["08:15", "12:40", "17:55"]),

        // Raleigh–Durham
        PairSpec(a: "BOS", b: "RDU", carrier: .harborline, aToB: 140, bToA: 135, number: 872,
                 aDeps: ["06:45", "09:50", "13:20", "17:10", "20:30"],
                 bDeps: ["07:10", "10:30", "14:05", "18:00", "21:15"]),
        PairSpec(a: "JFK", b: "RDU", carrier: .harborline, aToB: 105, bToA: 100, number: 884,
                 aDeps: ["07:00", "10:15", "13:45", "17:30", "20:50"],
                 bDeps: ["06:40", "09:55", "13:25", "17:05", "20:25"]),
        PairSpec(a: "MIA", b: "RDU", carrier: .meridian, aToB: 130, bToA: 135, number: 318,
                 aDeps: ["08:05", "12:40", "17:20", "21:05"],
                 bDeps: ["07:30", "12:05", "16:45", "20:30"]),
        PairSpec(a: "RDU", b: "SFO", carrier: .voyageAir, aToB: 375, bToA: 315, number: 1566,
                 aDeps: ["07:20", "16:40"],
                 bDeps: ["08:00", "22:15"]),
        PairSpec(a: "RDU", b: "LAX", carrier: .meridian, aToB: 355, bToA: 300, number: 344,
                 aDeps: ["07:40", "17:05"],
                 bDeps: ["08:25", "22:35"]),
        PairSpec(a: "RDU", b: "SEA", carrier: .cascadia, aToB: 355, bToA: 300, number: 356,
                 aDeps: ["08:10", "16:55"],
                 bDeps: ["07:50", "22:10"]),
        PairSpec(a: "RDU", b: "YYZ", carrier: .northstar, aToB: 125, bToA: 120, number: 1158,
                 aDeps: ["07:25", "12:50", "18:20"],
                 bDeps: ["08:05", "13:35", "19:00"]),
    ]

    /// Pairs with no mainstream nonstop: the connection the real-world
    /// popular itinerary routes through.
    private static let connectionVias: [String: String] = [
        "BOS-YQR": "YYZ", "YQR-BOS": "YYZ",
        "JFK-YQR": "YYZ", "YQR-JFK": "YYZ",
        "MIA-YQR": "YYZ", "YQR-MIA": "YYZ",
        "SFO-YQR": "YVR", "YQR-SFO": "YVR",
        "LAX-YQR": "YVR", "YQR-LAX": "YVR",
        // Seattle and Raleigh–Durham reach the prairies and each other over
        // the same western and eastern hubs a real booking would use.
        "SEA-YQR": "YVR", "YQR-SEA": "YVR",
        "RDU-YQR": "YYZ", "YQR-RDU": "YYZ",
        // Westbound from RDU connects over JFK, not SFO: the transcon leg from
        // the west coast doubles back and pushes the trip past the 8h cap.
        "RDU-YVR": "JFK", "YVR-RDU": "JFK",
    ]

    /// Directed nonstops keyed "ORG-DST".
    static let nonstops: [String: NonstopRoute] = {
        var table: [String: NonstopRoute] = [:]
        for pair in pairs {
            table["\(pair.a)-\(pair.b)"] = NonstopRoute(
                originCode: pair.a, destinationCode: pair.b, carrier: pair.carrier,
                minutes: pair.aToB, baseFlightNumber: pair.number, departureTimes: pair.aDeps,
                competitors: pair.competitors
            )
            table["\(pair.b)-\(pair.a)"] = NonstopRoute(
                originCode: pair.b, destinationCode: pair.a, carrier: pair.carrier,
                minutes: pair.bToA, baseFlightNumber: pair.number + 1, departureTimes: pair.bDeps,
                competitors: pair.competitors
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
                    carrier: route.carrier(departureIndex: index),
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
