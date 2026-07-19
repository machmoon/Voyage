import Foundation

/// A single leg of an itinerary: one takeoff, one landing.
struct FlightLeg: Identifiable, Hashable, Codable {
    let origin: Airport
    let destination: Airport
    /// Focused-work duration of this leg, in seconds.
    let duration: TimeInterval
    let flightNumber: String

    var id: String { flightNumber + origin.code + destination.code }
    var distanceMiles: Double { origin.distanceMiles(to: destination) }
}

/// A booked route: either a direct 2h short-haul, or a 6h long-haul
/// split into two legs with a layover in between.
struct Itinerary: Hashable, Codable {
    let legs: [FlightLeg]
    /// Lounge break between legs, in seconds. Zero for direct flights.
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
    /// Great-circle distance above which a route is a 6h long-haul.
    static let longHaulThresholdMiles: Double = 1500
    static let shortHaulDuration: TimeInterval = 2 * 3600
    static let longHaulDuration: TimeInterval = 6 * 3600
    static let layoverDuration: TimeInterval = 15 * 60

    static func isLongHaul(from origin: Airport, to destination: Airport) -> Bool {
        origin.distanceMiles(to: destination) >= longHaulThresholdMiles
    }

    /// Session length for the route as booked (excludes the layover break).
    static func focusDuration(from origin: Airport, to destination: Airport) -> TimeInterval {
        isLongHaul(from: origin, to: destination) ? longHaulDuration : shortHaulDuration
    }

    /// Builds the bookable itinerary between two airports.
    /// Long-hauls always connect through the airport with the smallest detour.
    static func itinerary(from origin: Airport, to destination: Airport) -> Itinerary {
        guard isLongHaul(from: origin, to: destination) else {
            let leg = FlightLeg(
                origin: origin,
                destination: destination,
                duration: shortHaulDuration,
                flightNumber: flightNumber(from: origin, to: destination)
            )
            return Itinerary(legs: [leg], layoverDuration: 0)
        }

        let via = connectionAirport(from: origin, to: destination)
        let d1 = origin.distanceMiles(to: via)
        let d2 = via.distanceMiles(to: destination)

        // Split the 6h of focused time across the legs in proportion to
        // distance, clamped so no leg drops below 90 minutes, rounded to 5 min.
        let minLeg: TimeInterval = 90 * 60
        var first = longHaulDuration * (d1 / (d1 + d2))
        first = min(max(first, minLeg), longHaulDuration - minLeg)
        first = (first / 300).rounded() * 300
        let second = longHaulDuration - first

        let leg1 = FlightLeg(origin: origin, destination: via, duration: first,
                             flightNumber: flightNumber(from: origin, to: via))
        let leg2 = FlightLeg(origin: via, destination: destination, duration: second,
                             flightNumber: flightNumber(from: via, to: destination))
        return Itinerary(legs: [leg1, leg2], layoverDuration: layoverDuration)
    }

    /// The intermediate stop that adds the least total distance.
    static func connectionAirport(from origin: Airport, to destination: Airport) -> Airport {
        Airport.all
            .filter { $0 != origin && $0 != destination }
            .min { lhs, rhs in
                let l = origin.distanceMiles(to: lhs) + lhs.distanceMiles(to: destination)
                let r = origin.distanceMiles(to: rhs) + rhs.distanceMiles(to: destination)
                return l < r
            }!
    }

    /// Deterministic pseudo-real flight number per city pair.
    static func flightNumber(from origin: Airport, to destination: Airport) -> String {
        var hash: UInt64 = 5381
        for byte in (origin.code + destination.code).utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return "VA \(100 + Int(hash % 800))"
    }
}
