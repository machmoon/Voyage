import Foundation
import CoreLocation

/// Great-circle math for positioning the aircraft along a route.
enum GreatCircle {

    /// Spherical linear interpolation between two coordinates.
    /// `fraction` 0 = start, 1 = end.
    static func point(from start: CLLocationCoordinate2D,
                      to end: CLLocationCoordinate2D,
                      fraction: Double) -> CLLocationCoordinate2D {
        let f = min(1, max(0, fraction))

        let lat1 = start.latitude * .pi / 180
        let lon1 = start.longitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let lon2 = end.longitude * .pi / 180

        // Angular distance via haversine.
        let dLat = lat2 - lat1
        let dLon = lon2 - lon1
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let delta = 2 * asin(min(1, sqrt(h)))

        // Degenerate (same point): nothing to interpolate.
        guard delta > 1e-9 else { return start }

        let a = sin((1 - f) * delta) / sin(delta)
        let b = sin(f * delta) / sin(delta)

        let x = a * cos(lat1) * cos(lon1) + b * cos(lat2) * cos(lon2)
        let y = a * cos(lat1) * sin(lon1) + b * cos(lat2) * sin(lon2)
        let z = a * sin(lat1) + b * sin(lat2)

        let lat = atan2(z, sqrt(x * x + y * y))
        let lon = atan2(y, x)
        return CLLocationCoordinate2D(latitude: lat * 180 / .pi, longitude: lon * 180 / .pi)
    }

    /// Initial course (degrees clockwise from true north) from `start`
    /// toward `end` along the great circle.
    static func bearing(from start: CLLocationCoordinate2D,
                        to end: CLLocationCoordinate2D) -> Double {
        let lat1 = start.latitude * .pi / 180
        let lon1 = start.longitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let lon2 = end.longitude * .pi / 180

        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Evenly spaced points along the great circle, endpoints included.
    /// Used to draw the flown / remaining route split on the map.
    static func points(from start: CLLocationCoordinate2D,
                       to end: CLLocationCoordinate2D,
                       count: Int) -> [CLLocationCoordinate2D] {
        guard count > 1 else { return [start] }
        return (0..<count).map { i in
            point(from: start, to: end, fraction: Double(i) / Double(count - 1))
        }
    }
}
