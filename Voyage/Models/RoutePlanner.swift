import Foundation

/// A single leg of an itinerary: one takeoff, one landing.
struct FlightLeg: Identifiable, Hashable, Codable {
    let origin: Airport
    let destination: Airport
    /// Focused-work duration of this leg, in seconds — the real block time.
    let duration: TimeInterval
    let flightNumber: String

    var id: String { flightNumber + origin.code + destination.code }
    var distanceMiles: Double { origin.distanceMiles(to: destination) }
}

/// A booked route mirroring the popular real-world itinerary: a nonstop
/// where one exists, otherwise a connection with a lounge break between legs.
struct Itinerary: Hashable, Codable {
    let legs: [FlightLeg]
    /// Lounge break between legs, in seconds. Zero for nonstops.
    let layoverDuration: TimeInterval

    var origin: Airport { legs[0].origin }
    var destination: Airport { legs[legs.count - 1].destination }
    var connection: Airport? { legs.count > 1 ? legs[0].destination : nil }
    var isConnection: Bool { legs.count > 1 }
    var totalMiles: Double { legs.reduce(0) { $0 + $1.distanceMiles } }
    var totalFocusDuration: TimeInterval { legs.reduce(0) { $0 + $1.duration } }
    var primaryFlightNumber: String { legs[0].flightNumber }
}

enum RoutePlanner {
    /// Lounge break between connection legs. Deliberately a Pomodoro-length
    /// breather rather than a real-world multi-hour layover.
    static let layoverDuration: TimeInterval = 15 * 60

    /// Builds the bookable itinerary between two airports using real-world
    /// block times and the popular routing from `RouteCatalog`.
    /// `flightNumberOverride` stamps a specific scheduled departure's number
    /// onto the first leg (later departures carry different numbers).
    static func itinerary(from origin: Airport, to destination: Airport,
                          flightNumberOverride: String? = nil) -> Itinerary {
        if let direct = RouteCatalog.nonstop(from: origin, to: destination) {
            let leg = FlightLeg(
                origin: origin,
                destination: destination,
                duration: direct.duration,
                flightNumber: flightNumberOverride ?? direct.flightNumberText
            )
            return Itinerary(legs: [leg], layoverDuration: 0)
        }

        if let via = RouteCatalog.via(from: origin, to: destination),
           let first = RouteCatalog.nonstop(from: origin, to: via),
           let second = RouteCatalog.nonstop(from: via, to: destination) {
            let leg1 = FlightLeg(origin: origin, destination: via,
                                 duration: first.duration,
                                 flightNumber: flightNumberOverride ?? first.flightNumberText)
            let leg2 = FlightLeg(origin: via, destination: destination,
                                 duration: second.duration,
                                 flightNumber: second.flightNumberText)
            return Itinerary(legs: [leg1, leg2], layoverDuration: layoverDuration)
        }

        // Defensive fallback for a pair missing from the catalog:
        // estimate a nonstop from great-circle distance.
        let leg = FlightLeg(
            origin: origin,
            destination: destination,
            duration: TimeInterval(estimatedMinutes(forMiles: origin.distanceMiles(to: destination))) * 60,
            flightNumber: flightNumberOverride ?? "VA \(100 + abs(origin.code.hashValue ^ destination.code.hashValue) % 800)"
        )
        return Itinerary(legs: [leg], layoverDuration: 0)
    }

    static func isConnection(from origin: Airport, to destination: Airport) -> Bool {
        RouteCatalog.nonstop(from: origin, to: destination) == nil
            && RouteCatalog.via(from: origin, to: destination) != nil
    }

    /// Session length for the route as booked (excludes the lounge break).
    static func focusDuration(from origin: Airport, to destination: Airport) -> TimeInterval {
        itinerary(from: origin, to: destination).totalFocusDuration
    }

    /// The route's display flight number (first leg of the base schedule).
    static func flightNumber(from origin: Airport, to destination: Airport) -> String {
        itinerary(from: origin, to: destination).primaryFlightNumber
    }

    /// Block-time estimate: cruise ~510 mph plus 40 min taxi/climb/descent
    /// overhead, rounded to 5 minutes. Used only as a catalog fallback.
    static func estimatedMinutes(forMiles miles: Double) -> Int {
        let raw = miles / 510.0 * 60.0 + 40.0
        return max(45, Int((raw / 5.0).rounded()) * 5)
    }
}
