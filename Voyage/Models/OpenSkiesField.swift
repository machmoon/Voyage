import Foundation
import CoreLocation

/// An airport an Open skies flight can land at, with the runways it lands on.
///
/// The ten bookable airports keep their authored runways from
/// `FlightRunwayCatalog`; the regional fields in `OpenSkiesFieldCatalog.swift`
/// carry their longest runway from OurAirports. Regional fields are never
/// bookable: they exist so a 25-minute flight, which covers about 100 miles,
/// always has somewhere real to come down.
struct OpenSkiesField: Equatable, Identifiable {
    let airport: Airport
    /// Both directions of each runway, as `RunwayProfile`s (threshold first).
    let runways: [RunwayProfile]

    var id: String { airport.code }
    var code: String { airport.code }
    var coordinate: CLLocationCoordinate2D { airport.coordinate }
    var location: CLLocation { airport.location }

    /// Every field: the bookable ten, then the regional catalog.
    static let all: [OpenSkiesField] = Airport.all.map {
        OpenSkiesField(airport: $0, runways: FlightVisualEngine.runways(for: $0))
    } + regional

    static func named(_ code: String) -> OpenSkiesField? {
        all.first { $0.code == code }
    }

    /// The nearest field to `location`.
    static func nearest(to location: CLLocation,
                        in fields: [OpenSkiesField] = all) -> OpenSkiesField? {
        fields.min { $0.location.distance(from: location) < $1.location.distance(from: location) }
    }

    /// The runway end to land on when arriving on `course`: the one whose
    /// heading is closest to it, so the approach needs the smallest turn.
    func landingRunway(arrivingOn course: Double) -> RunwayProfile? {
        runways.min {
            abs(Self.angle(from: $0.trueHeadingDegrees, to: course))
                < abs(Self.angle(from: $1.trueHeadingDegrees, to: course))
        }
    }

    static func angle(from: Double, to: Double) -> Double {
        var delta = (to - from).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }

    /// One regional entry, in the shape OurAirports publishes: the field, then
    /// each runway end as (designator, latitude, longitude, elevation in feet).
    static func field(_ code: String,
                      _ city: String,
                      _ name: String,
                      _ latitude: Double,
                      _ longitude: Double,
                      _ elevationFeet: Double,
                      _ low: (String, Double, Double, Double),
                      _ high: (String, Double, Double, Double),
                      _ lengthMeters: Double) -> OpenSkiesField {
        let airport = Airport(code: code, city: city, name: name,
                              latitude: latitude, longitude: longitude,
                              accentHex: accent(for: code))
        func end(_ value: (String, Double, Double, Double)) -> FlightGeodeticPoint {
            FlightGeodeticPoint(latitude: value.1, longitude: value.2,
                                altitudeMeters: value.3 * 0.3048)
        }
        let elevation = (low.3 + high.3) * 0.1524
        let runways = [
            RunwayProfile(airportCode: code, designator: low.0,
                          threshold: end(low), oppositeThreshold: end(high),
                          elevationMeters: elevation, usableLengthMeters: lengthMeters,
                          defaultPriority: 10),
            RunwayProfile(airportCode: code, designator: high.0,
                          threshold: end(high), oppositeThreshold: end(low),
                          elevationMeters: elevation, usableLengthMeters: lengthMeters,
                          defaultPriority: 9),
        ]
        return OpenSkiesField(airport: airport, runways: runways)
    }

    /// Regional fields borrow an accent from the bookable ten, chosen by code
    /// so the same field always arrives in the same colour.
    private static func accent(for code: String) -> String {
        let palette = Airport.all.map(\.accentHex)
        let seed = code.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }
        return palette[abs(seed) % palette.count]
    }
}

extension Airport {
    /// The destination an Open skies flight carries until it is cleared to
    /// land: no city of its own, at the origin's coordinates so weather and
    /// scenery stay local. Its code is the app's "not chosen" dash, the same
    /// one an unassigned seat prints.
    static func openSkiesPlaceholder(near origin: Airport) -> Airport {
        Airport(code: "—", city: "Open skies", name: "Open skies",
                latitude: origin.latitude, longitude: origin.longitude,
                accentHex: "5E8FFF")
    }

    var isOpenSkiesPlaceholder: Bool { code == "—" }

    /// Any airport Voyage knows, bookable or an Open skies field.
    static func find(_ code: String) -> Airport? {
        all.first { $0.code == code } ?? OpenSkiesField.regional.first { $0.code == code }?.airport
    }
}
