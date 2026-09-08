import XCTest
@testable import Voyage

final class DigitalTwinTests: XCTestCase {
    func testWindowSideTracksSelectedSeat() {
        // A/B/C sit port of the aisle on every cabin plan, D/E/F starboard —
        // including the 2-2 First cabins, which skip B and E.
        XCTAssertEqual(WindowSide(seat: "A12"), .left)
        XCTAssertEqual(WindowSide(seat: "B7"), .left)
        XCTAssertEqual(WindowSide(seat: "C7"), .left)
        XCTAssertEqual(WindowSide(seat: "D12"), .right)
        XCTAssertEqual(WindowSide(seat: "E7"), .right)
        XCTAssertEqual(WindowSide(seat: "F7"), .right)
    }

    func testSFOProfileIsWeatherSelected() {
        let sfo = Airport.byCode("SFO")
        let bay = WeatherSnapshot(airportCode: "SFO", observedAt: .now, condition: .clear,
                                  windDirectionDegrees: 280, windSpeedKnots: 12,
                                  visibilityMiles: 10, cloudBaseFeet: nil,
                                  temperatureCelsius: 18, source: "fixture")
        let city = WeatherSnapshot(airportCode: "SFO", observedAt: .now, condition: .clear,
                                   windDirectionDegrees: 120, windSpeedKnots: 8,
                                   visibilityMiles: 10, cloudBaseFeet: nil,
                                   temperatureCelsius: 18, source: "fixture")
        XCTAssertEqual(AirportWorldCatalog.departureProfile(for: sfo, weather: bay), .sfoBay)
        XCTAssertEqual(AirportWorldCatalog.departureProfile(for: sfo, weather: city), .sfoCity)
    }

    func testTakeoffSimulationIsDeterministic() {
        let simulation = AirportWorldSimulation(
            airport: Airport.byCode("SFO"), aircraft: .boeing737800, seat: "A8",
            weather: .fallback(for: Airport.byCode("SFO"), condition: .cloudy)
        )
        let first = simulation.frame(phase: .takeoffRoll, legElapsed: 12, altitudeFeet: 0)
        let second = simulation.frame(phase: .takeoffRoll, legElapsed: 12, altitudeFeet: 0)
        XCTAssertEqual(first, second)
        XCTAssertGreaterThan(first.rollProgress, 0)
        XCTAssertLessThan(first.rollProgress, 1)
        XCTAssertEqual(first.camera, second.camera)
    }

    func testPassengerCameraUsesGeographicallyDistinctSides() {
        let airport = Airport.byCode("SFO")
        let left = AirportWorldSimulation(
            airport: airport, aircraft: .boeing737800, seat: "A8", weather: nil
        ).frame(phase: .climb, legElapsed: FlightSession.takeoffRollDuration + 10, altitudeFeet: 8_000)
        let right = AirportWorldSimulation(
            airport: airport, aircraft: .boeing737800, seat: "F8", weather: nil
        ).frame(phase: .climb, legElapsed: FlightSession.takeoffRollDuration + 10, altitudeFeet: 8_000)

        XCTAssertLessThan(left.camera.position.x, 0)
        XCTAssertGreaterThan(right.camera.position.x, 0)
        XCTAssertGreaterThan(left.camera.yawDegrees, 0)
        XCTAssertLessThan(right.camera.yawDegrees, 0)
        XCTAssertGreaterThan(abs(left.camera.yawDegrees), 50)
        XCTAssertGreaterThan(abs(right.camera.yawDegrees), 50)
        XCTAssertEqual(left.camera.position.y, right.camera.position.y, accuracy: 0.001)
    }

    func testSFOCityIsOnRightSideOfRunway28World() {
        let downtown = SFOAirportWorldData.localPosition(for: SFOAirportWorldData.downtown)
        XCTAssertGreaterThan(downtown.x, 0)
        XCTAssertLessThan(downtown.z, 0)
        XCTAssertFalse(SFOAirportWorldData.attribution.isEmpty)
    }

    func testRendererSelectionFallsBackDeterministically() {
        let simulation = AirportWorldSimulation(
            airport: Airport.byCode("SFO"), aircraft: .voyageClassic, seat: "C8", weather: nil
        )
        let frame = simulation.frame(phase: .takeoffRoll, legElapsed: 4, altitudeFeet: 0)
        // Illustrated procedural canvas is always selected — the authored SFO Metal
        // scene was retired in favor of the hand-drawn runway/tower look.
        for (phase, reduceMotion) in [
            (LegPhase.takeoffRoll, false),
            (LegPhase.takeoffRoll, true),
            (LegPhase.landing, false),
        ] {
            XCTAssertEqual(
                WindowWorldRendererPolicy.selection(
                    for: frame, phase: phase, reduceMotion: reduceMotion, metalAvailable: true
                ),
                .procedural
            )
        }
    }

    func testCatalogAlwaysProvidesTenUpcomingRows() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 23, minute: 30))!
        let rows = RouteCatalog.upcomingDepartures(
            from: Airport.byCode("SFO"), to: Airport.byCode("LAX"),
            after: start, count: 10, calendar: calendar
        )
        XCTAssertEqual(rows.count, 10)
        XCTAssertTrue(rows.allSatisfy { !$0.isVerifiedLive })
        XCTAssertTrue(rows.allSatisfy { $0.departure > start })
    }

    func testReplayMetadataRoundTrips() {
        let airport = Airport.byCode("SFO")
        let weather = WeatherSnapshot.fallback(for: airport, condition: .fog)
        let samples = [ReplayRouteSample(latitude: airport.latitude, longitude: airport.longitude, progress: 0)]
        let entry = LogbookEntry(originCode: "SFO", destinationCode: "LAX", flightNumber: "VOY 424",
                                 seat: "A8", miles: 337, focusSeconds: 5_100, completed: true,
                                 aircraft: .airbusA320neo, weatherSnapshot: weather,
                                 departureProfile: .sfoBay, worldRevision: AirportWorldCatalog.revision,
                                 routeSamples: samples)
        XCTAssertEqual(entry.aircraft, .airbusA320neo)
        XCTAssertEqual(entry.weatherSnapshot?.condition, .fog)
        XCTAssertEqual(entry.routeSamples, samples)
    }
}
