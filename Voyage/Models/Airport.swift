import Foundation
import CoreLocation

/// One of the eight hardcoded Voyage airports.
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

    /// Great-circle distance in statute miles.
    func distanceMiles(to other: Airport) -> Double {
        location.distance(from: other.location) / 1609.344
    }
}

extension Airport {
    static let all: [Airport] = [
        Airport(code: "BOS", city: "Boston", name: "Logan International", latitude: 42.3656, longitude: -71.0096, accentHex: "1E6FEB"),
        Airport(code: "JFK", city: "New York", name: "John F. Kennedy International", latitude: 40.6413, longitude: -73.7781, accentHex: "F5B02C"),
        Airport(code: "MIA", city: "Miami", name: "Miami International", latitude: 25.7959, longitude: -80.2870, accentHex: "FF4F81"),
        Airport(code: "SFO", city: "San Francisco", name: "San Francisco International", latitude: 37.6213, longitude: -122.3790, accentHex: "FF7A45"),
        Airport(code: "LAX", city: "Los Angeles", name: "Los Angeles International", latitude: 33.9416, longitude: -118.4085, accentHex: "B36BFF"),
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
}
