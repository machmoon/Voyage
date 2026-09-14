import Foundation
import CoreLocation

/// One of the hardcoded Voyage airports.
struct Airport: Identifiable, Hashable, Codable {
    let code: String
    let city: String
    let name: String
    let latitude: Double
    let longitude: Double
    /// City accent color used on arrival screens and destination cards.
    let accentHex: String

    var id: String { code }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    /// Local airport time drives exterior light, rather than the device's
    /// current time zone (a 5 p.m. SFO departure should not render as night
    /// just because the traveler booked it from the East Coast).
    var timeZone: TimeZone {
        let identifier: String
        switch code {
        case "BOS", "JFK", "MIA", "RDU": identifier = "America/New_York"
        case "SFO", "LAX", "SEA": identifier = "America/Los_Angeles"
        case "YYZ": identifier = "America/Toronto"
        case "YVR": identifier = "America/Vancouver"
        case "YQR": identifier = "America/Regina"
        default: identifier = TimeZone.current.identifier
        }
        return TimeZone(identifier: identifier) ?? .current
    }

    /// Great-circle distance in statute miles.
    func distanceMiles(to other: Airport) -> Double {
        location.distance(from: other.location) / 1609.344
    }
}

extension Airport {
    /// The runway used for window-view choreography. Departures roll away from
    /// the threshold along `heading`; arrivals approach toward it on the
    /// reciprocal track. Coordinates are approximate — close enough that the
    /// satellite-flyover camera passes over the real airfield.
    struct Runway {
        /// True heading of the departure roll, in degrees.
        let heading: Double
        let threshold: CLLocationCoordinate2D
    }

    var runway: Runway? {
        switch code {
        case "BOS": return Runway(heading: 326, threshold: .init(latitude: 42.3500, longitude: -70.9930))
        case "JFK": return Runway(heading: 300, threshold: .init(latitude: 40.6222, longitude: -73.7692))
        case "MIA": return Runway(heading: 87, threshold: .init(latitude: 25.7932, longitude: -80.3100))
        case "SFO": return Runway(heading: 284, threshold: .init(latitude: 37.6119, longitude: -122.3579))
        case "LAX": return Runway(heading: 263, threshold: .init(latitude: 33.9490, longitude: -118.4015))
        case "YYZ": return Runway(heading: 237, threshold: .init(latitude: 43.6862, longitude: -79.6038))
        case "YVR": return Runway(heading: 259, threshold: .init(latitude: 49.1947, longitude: -123.1620))
        case "YQR": return Runway(heading: 312, threshold: .init(latitude: 50.4237, longitude: -104.6516))
        case "SEA": return Runway(heading: 164, threshold: .init(latitude: 47.4664, longitude: -122.3114))
        case "RDU": return Runway(heading: 225, threshold: .init(latitude: 35.8950, longitude: -78.7792))
        default: return nil
        }
    }

    static let all: [Airport] = [
        Airport(code: "BOS", city: "Boston", name: "Logan International", latitude: 42.3656, longitude: -71.0096, accentHex: "1E6FEB"),
        Airport(code: "JFK", city: "New York", name: "John F. Kennedy International", latitude: 40.6413, longitude: -73.7781, accentHex: "F5B02C"),
        Airport(code: "MIA", city: "Miami", name: "Miami International", latitude: 25.7959, longitude: -80.2870, accentHex: "FF4F81"),
        Airport(code: "RDU", city: "Raleigh–Durham", name: "Raleigh–Durham International", latitude: 35.8801, longitude: -78.7880, accentHex: "4F6FA8"),
        Airport(code: "SFO", city: "San Francisco", name: "San Francisco International", latitude: 37.6213, longitude: -122.3790, accentHex: "FF7A45"),
        Airport(code: "LAX", city: "Los Angeles", name: "Los Angeles International", latitude: 33.9416, longitude: -118.4085, accentHex: "B36BFF"),
        Airport(code: "SEA", city: "Seattle", name: "Seattle–Tacoma International", latitude: 47.4502, longitude: -122.3088, accentHex: "3F7FA6"),
        Airport(code: "YYZ", city: "Toronto", name: "Toronto Pearson International", latitude: 43.6777, longitude: -79.6248, accentHex: "2FA3E8"),
        Airport(code: "YVR", city: "Vancouver", name: "Vancouver International", latitude: 49.1967, longitude: -123.1815, accentHex: "2EC08B"),
        Airport(code: "YQR", city: "Regina", name: "Regina International", latitude: 50.4319, longitude: -104.6658, accentHex: "E8B23A"),
    ]

    static func byCode(_ code: String) -> Airport {
        all.first { $0.code == code } ?? all[0]
    }

    static func nearest(to location: CLLocation) -> Airport {
        all.min { $0.location.distance(from: location) < $1.location.distance(from: location) } ?? all[0]
    }

    /// The nearest catalog airport, or nil when even that one is farther than `distance`.
    static func nearest(to location: CLLocation, within distance: CLLocationDistance) -> Airport? {
        let closest = nearest(to: location)
        return closest.location.distance(from: location) <= distance ? closest : nil
    }
}
