import Foundation

/// Small, offline source-data contract for the SFO proof. Coordinates are kept
/// in geographic form here, then projected into the authored runway-local
/// scene. This lets a future asset generator replace the primitive geometry
/// without changing flight or renderer interfaces.
enum SFOAirportWorldData {
    struct Point: Equatable {
        let latitude: Double
        let longitude: Double
    }

    /// Source acknowledgement displayed in Settings and retained alongside the
    /// world contract. The proof uses coordinate-derived geometry rather than
    /// downloading tiles or imagery at runtime.
    static let attribution = "Airport geometry © OpenStreetMap contributors; terrain reference USGS 3DEP (public domain)"

    static let runwayThreshold = Point(latitude: 37.6119, longitude: -122.3579)
    static let downtown = Point(latitude: 37.7936, longitude: -122.3970)
    static let sanBrunoMountain = Point(latitude: 37.6878, longitude: -122.4350)
    static let terminal = Point(latitude: 37.6152, longitude: -122.3899)
    static let headingDegrees = 284.0

    /// Equirectangular projection is accurate enough for this compact airport
    /// corridor. A cinematic scale keeps the skyline legible through a phone-
    /// sized window while retaining its geographically correct side.
    static func localPosition(for point: Point, elevation: Double = 0) -> SIMD3<Double> {
        let latitudeRadians = runwayThreshold.latitude * .pi / 180
        let east = (point.longitude - runwayThreshold.longitude) * 111_320 * cos(latitudeRadians)
        let north = (point.latitude - runwayThreshold.latitude) * 111_320
        let heading = headingDegrees * .pi / 180
        let forward = east * sin(heading) + north * cos(heading)
        let right = east * cos(heading) - north * sin(heading)
        // Lateral distance is compressed more aggressively than forward
        // distance. A phone window has a narrow frustum; this preserves which
        // side a landmark belongs on while bringing the skyline into view.
        let lateralScale = 0.05
        let forwardScale = 0.55
        return SIMD3(right * lateralScale, elevation, -forward * forwardScale)
    }
}
