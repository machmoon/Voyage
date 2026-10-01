import XCTest
import CoreLocation
@testable import Voyage

final class FlightFollowCameraPlanTests: XCTestCase {

    func testDistanceClimbsWithTheAircraftAndHoldsAtCruise() {
        let plan = FlightFollowCameraPlan.self
        XCTAssertEqual(plan.altitudeDistance(altitudeMeters: 0), plan.groundDistance, accuracy: 1)
        XCTAssertEqual(plan.altitudeDistance(altitudeMeters: -40), plan.groundDistance, accuracy: 1)
        XCTAssertEqual(plan.altitudeDistance(altitudeMeters: plan.cruiseAltitude), plan.cruiseDistance, accuracy: 1)
        XCTAssertEqual(plan.altitudeDistance(altitudeMeters: 12_000), plan.cruiseDistance, accuracy: 1)
        // Log interpolation: halfway up is the geometric mean.
        let half = plan.altitudeDistance(altitudeMeters: plan.cruiseAltitude / 2)
        XCTAssertEqual(half, (plan.groundDistance * plan.cruiseDistance).squareRoot(), accuracy: 1)
        // Monotonic.
        var last = 0.0
        for metres in stride(from: 0.0, through: 10_000, by: 250) {
            let d = plan.altitudeDistance(altitudeMeters: metres)
            XCTAssertGreaterThanOrEqual(d, last)
            last = d
        }
    }

    func testFastGroundRaisesTheCameraToTheSweepBound() {
        let plan = FlightFollowCameraPlan.self
        // A real airliner at 250 m/s never reaches the bound.
        XCTAssertEqual(plan.targetDistance(altitudeMeters: 0, groundSpeed: 250, screenfulPerDistance: 1),
                       plan.groundDistance, accuracy: 1)
        // A compressed demo leg covering 60 km/s does: 60 km/s at half a
        // screenful a second needs a 120 km screenful.
        let fast = plan.targetDistance(altitudeMeters: 0, groundSpeed: 60_000, screenfulPerDistance: 1)
        XCTAssertEqual(fast, 60_000 / ReplayCameraPlan.maxScreenfulsPerSecond, accuracy: 1)
        let sweep = fast * 1 / 60_000
        XCTAssertLessThanOrEqual(1 / sweep, ReplayCameraPlan.maxScreenfulsPerSecond + 1e-9)
        // Unknown speed or view falls back to altitude alone.
        XCTAssertEqual(plan.targetDistance(altitudeMeters: 0, groundSpeed: .nan, screenfulPerDistance: 1),
                       plan.groundDistance, accuracy: 1)
        XCTAssertEqual(plan.targetDistance(altitudeMeters: 0, groundSpeed: 60_000, screenfulPerDistance: 0),
                       plan.groundDistance, accuracy: 1)
    }

    func testZoomEasesInLogSpaceAndNeverOvershoots() {
        let plan = FlightFollowCameraPlan.self
        var d = 30_000.0
        var previous = d
        for _ in 0..<600 {
            d = plan.easedDistance(from: d, to: 220_000, elapsed: 1.0 / 60)
            XCTAssertGreaterThanOrEqual(d, previous)
            XCTAssertLessThanOrEqual(d, 220_000)
            previous = d
        }
        // Ten seconds is five time constants: within 1 % in log terms.
        XCTAssertLessThan(abs(log(d / 220_000)), 0.01 * log(220_000 / 30_000.0))
        // One time constant covers 1 - 1/e of the zoom change.
        let one = plan.easedDistance(from: 30_000, to: 220_000, elapsed: plan.distanceTimeConstant)
        let share = log(one / 30_000) / log(220_000 / 30_000.0)
        XCTAssertEqual(share, 1 - exp(-1), accuracy: 1e-9)
        // No time, no change.
        XCTAssertEqual(plan.easedDistance(from: 50_000, to: 220_000, elapsed: 0), 50_000)
    }

    func testBelowTheSweepFloorTheCameraClimbsFaster() {
        let plan = FlightFollowCameraPlan.self
        let calm = plan.easedDistance(from: 30_000, to: 220_000, elapsed: 0.5)
        let urgent = plan.easedDistance(from: 30_000, to: 220_000, sweepFloor: 100_000, elapsed: 0.5)
        XCTAssertGreaterThan(urgent, calm)
        XCTAssertLessThanOrEqual(urgent, 220_000)
    }

    func testAircraftSitsInTheMiddleOfTheMapAboveTheControls() {
        let plan = FlightFollowCameraPlan.self
        XCTAssertEqual(plan.centreOffsetPoints(topInset: 0, bottomInset: 60), 30)
        XCTAssertEqual(plan.centreOffsetPoints(topInset: 0, bottomInset: 0), 0)
        XCTAssertEqual(plan.centreOffsetPoints(topInset: 20, bottomInset: 60), 20)
        XCTAssertEqual(plan.centreOffsetPoints(topInset: 0, bottomInset: -10), 0)
    }

    func testFlownFractionEndsAtTheAircraft() {
        let line = [
            CLLocationCoordinate2D(latitude: 0, longitude: 0),
            CLLocationCoordinate2D(latitude: 0, longitude: 1),
            CLLocationCoordinate2D(latitude: 0, longitude: 2),
        ]
        let middle = FlightMapRoute.flownFraction(
            coordinates: line, progress: [0, 0.5, 1], routeProgress: 0.75,
            aircraft: CLLocationCoordinate2D(latitude: 0, longitude: 1.5))
        XCTAssertEqual(middle, 0.75, accuracy: 0.001)
        let start = FlightMapRoute.flownFraction(
            coordinates: line, progress: nil, routeProgress: 0,
            aircraft: line[0])
        XCTAssertEqual(start, 0, accuracy: 1e-9)
        let end = FlightMapRoute.flownFraction(
            coordinates: line, progress: [0, 0.5, 1], routeProgress: 1, aircraft: line[2])
        XCTAssertEqual(end, 1, accuracy: 1e-9)
    }
}
