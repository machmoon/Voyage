import CoreLocation
import XCTest
@testable import Voyage

final class FlightDataAPIArchiveTests: XCTestCase {
    private let api = FlightDataAPI.shared

    func testValidConnectionArchivePreservesLegOrderAndEndpoints() {
        let sfo = Airport.byCode("SFO")
        let yyz = Airport.byCode("YYZ")
        let yqr = Airport.byCode("YQR")
        let firstLeg = legSamples(from: sfo, to: yyz, duration: 100, course: 55)
        let secondLeg = legSamples(from: yyz, to: yqr, duration: 100, course: 285)
        let entry = makeConnectionEntry(trajectoryLegSamples: [firstLeg, secondLeg])

        let snapshot = api.replaySnapshot(for: entry, progress: 0.75)
        let expected = GreatCircle.point(
            from: yyz.coordinate,
            to: yqr.coordinate,
            fraction: 0.5
        )

        XCTAssertEqual(snapshot.legIndex, 1)
        XCTAssertEqual(snapshot.legProgress, 0.5, accuracy: 0.0001)
        XCTAssertEqual(snapshot.coordinate.latitude, expected.latitude, accuracy: 0.000001)
        XCTAssertEqual(snapshot.coordinate.longitude, expected.longitude, accuracy: 0.000001)

        let route = api.routeCoordinates(for: entry)
        XCTAssertEqual(route.count, 3)
        assertCoordinate(route[0], equals: sfo.coordinate)
        assertCoordinate(route[1], equals: yyz.coordinate)
        assertCoordinate(route[2], equals: yqr.coordinate)
    }

    func testAnyCorruptConnectionLegRejectsTheEntireArchiveWithoutReindexing() {
        let sfo = Airport.byCode("SFO")
        let lax = Airport.byCode("LAX")
        let yyz = Airport.byCode("YYZ")
        let yqr = Airport.byCode("YQR")
        let firstLeg = legSamples(from: sfo, to: yyz, duration: 100, course: 55)
        let secondLeg = legSamples(from: yyz, to: yqr, duration: 100, course: 285)
        let wrongEndpoint = legSamples(from: sfo, to: lax, duration: 100, course: 180)
        let reversedTime = [firstLeg[1], firstLeg[0]]
        let legacy = legacyFallbackSamples

        let corruptArchives: [(name: String, legs: [[FlightTrajectorySample]])] = [
            ("missing first leg", [secondLeg]),
            ("undersampled first leg", [[firstLeg[0]], secondLeg]),
            ("swapped leg order", [secondLeg, firstLeg]),
            ("wrong first-leg endpoint", [wrongEndpoint, secondLeg]),
            ("out-of-order samples", [reversedTime, secondLeg]),
        ]
        let expectedMidpoint = GreatCircle.point(
            from: CLLocationCoordinate2D(latitude: legacy[0].latitude, longitude: legacy[0].longitude),
            to: CLLocationCoordinate2D(latitude: legacy[1].latitude, longitude: legacy[1].longitude),
            fraction: 0.5
        )

        for corrupt in corruptArchives {
            let entry = makeConnectionEntry(
                trajectoryLegSamples: corrupt.legs,
                routeSamples: legacy
            )
            let snapshot = api.replaySnapshot(for: entry, progress: 0.5)
            XCTAssertEqual(
                snapshot.coordinate.latitude,
                expectedMidpoint.latitude,
                accuracy: 0.000001,
                corrupt.name
            )
            XCTAssertEqual(
                snapshot.coordinate.longitude,
                expectedMidpoint.longitude,
                accuracy: 0.000001,
                corrupt.name
            )

            let route = api.routeCoordinates(for: entry)
            XCTAssertEqual(route.count, legacy.count, corrupt.name)
            assertCoordinate(
                route[0],
                equals: CLLocationCoordinate2D(latitude: legacy[0].latitude, longitude: legacy[0].longitude),
                message: corrupt.name
            )
            assertCoordinate(
                route[1],
                equals: CLLocationCoordinate2D(latitude: legacy[1].latitude, longitude: legacy[1].longitude),
                message: corrupt.name
            )
        }
    }

    private var legacyFallbackSamples: [ReplayRouteSample] {
        [
            ReplayRouteSample(latitude: 35, longitude: -105, progress: 0),
            ReplayRouteSample(latitude: 36, longitude: -104, progress: 1),
        ]
    }

    private func makeConnectionEntry(
        trajectoryLegSamples: [[FlightTrajectorySample]],
        routeSamples: [ReplayRouteSample]? = nil
    ) -> LogbookEntry {
        LogbookEntry(
            originCode: "SFO",
            destinationCode: "YQR",
            connectionCode: "YYZ",
            flightNumber: "NLN 740",
            seat: "A8",
            miles: 1_500,
            focusSeconds: 8_000,
            completed: true,
            worldRevision: FlightVisualEngine.trajectoryRevision,
            routeSamples: routeSamples,
            trajectoryLegSamples: trajectoryLegSamples
        )
    }

    private func legSamples(
        from origin: Airport,
        to destination: Airport,
        duration: TimeInterval,
        course: Double
    ) -> [FlightTrajectorySample] {
        [
            sample(elapsed: 0, coordinate: origin.coordinate, course: course, routeProgress: 0),
            sample(elapsed: duration, coordinate: destination.coordinate, course: course, routeProgress: 1),
        ]
    }

    private func sample(
        elapsed: TimeInterval,
        coordinate: CLLocationCoordinate2D,
        course: Double,
        routeProgress: Double
    ) -> FlightTrajectorySample {
        FlightTrajectorySample(
            elapsed: elapsed,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            altitudeMeters: routeProgress == 0 || routeProgress == 1 ? 0 : 10_000,
            courseDegrees: course,
            pitchDegrees: 0,
            bankDegrees: 0,
            routeProgress: routeProgress
        )
    }

    private func assertCoordinate(
        _ actual: CLLocationCoordinate2D,
        equals expected: CLLocationCoordinate2D,
        message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.latitude, expected.latitude, accuracy: 0.000001, message, file: file, line: line)
        XCTAssertEqual(actual.longitude, expected.longitude, accuracy: 0.000001, message, file: file, line: line)
    }
}
