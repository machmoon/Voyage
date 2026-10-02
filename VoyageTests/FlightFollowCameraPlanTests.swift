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

    // MARK: Chase view

    func testPitchRisesWithAltitudeWithinMapboxRange() {
        let plan = FlightFollowCameraPlan.self
        XCTAssertEqual(plan.pitch(altitudeMeters: 0), plan.groundPitch)
        XCTAssertEqual(plan.pitch(altitudeMeters: 20_000), plan.cruisePitch)
        XCTAssertEqual(plan.pitch(altitudeMeters: plan.cruiseAltitude / 2),
                       (plan.groundPitch + plan.cruisePitch) / 2, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(plan.groundPitch, 0)
        XCTAssertLessThanOrEqual(plan.cruisePitch, 85) // Mapbox's defaultPitch clamp
        // Above the cruise distance (a demo leg the sweep bound lifted) the
        // view flattens in proportion; at or below it, nothing changes.
        XCTAssertEqual(plan.pitch(altitudeMeters: 20_000, distance: plan.cruiseDistance), plan.cruisePitch)
        XCTAssertEqual(plan.pitch(altitudeMeters: 20_000, distance: plan.cruiseDistance * 2),
                       plan.cruisePitch / 2, accuracy: 1e-9)
    }

    func testShortestRotationNeverGoesTheLongWay() {
        let plan = FlightFollowCameraPlan.self
        XCTAssertEqual(plan.shortestRotation(from: 359, to: 1), 2, accuracy: 1e-9)
        XCTAssertEqual(plan.shortestRotation(from: 1, to: 359), -2, accuracy: 1e-9)
        XCTAssertEqual(plan.shortestRotation(from: 10, to: 190), 180, accuracy: 1e-9)
        XCTAssertEqual(plan.shortestRotation(from: 720 + 30, to: -30), -60, accuracy: 1e-9)
        for a in stride(from: -720.0, through: 720, by: 37) {
            for b in stride(from: -720.0, through: 720, by: 41) {
                let d = plan.shortestRotation(from: a, to: b)
                XCTAssertGreaterThan(d, -180.000_001)
                XCTAssertLessThanOrEqual(d, 180)
            }
        }
    }

    func testBearingEasesAcrossNorthWithoutSpinning() {
        let plan = FlightFollowCameraPlan.self
        var heading = 350.0
        // Ten time constants.
        let frames = Int(plan.bearingTimeConstant * 10 * 60)
        for _ in 0..<frames {
            let next = plan.easedBearing(from: heading, to: 10, elapsed: 1.0 / 60)
            // Every frame turns a little clockwise, through north, never back.
            XCTAssertGreaterThanOrEqual(plan.shortestRotation(from: heading, to: next), 0)
            XCTAssertLessThan(abs(plan.shortestRotation(from: heading, to: next)), 1)
            XCTAssertTrue((0..<360).contains(next))
            heading = next
        }
        XCTAssertEqual(plan.shortestRotation(from: heading, to: 10), 0, accuracy: 0.01)
        XCTAssertEqual(plan.easedBearing(from: 123, to: 200, elapsed: 0), 200)
    }

    func testChaseBearingLooksAheadButStaysNearTheCourse() {
        let plan = FlightFollowCameraPlan.self
        // A gentle turn ahead is followed exactly.
        XCTAssertEqual(plan.chaseBearing(course: 90, lookAhead: 110), 110, accuracy: 1e-9)
        // A sharp one is held to 45° off the course (Mapbox's smoothing angle).
        XCTAssertEqual(plan.chaseBearing(course: 90, lookAhead: 200), 135, accuracy: 1e-9)
        XCTAssertEqual(plan.chaseBearing(course: 10, lookAhead: 300), 325, accuracy: 1e-9)
        // No look-ahead (end of the leg): the course.
        XCTAssertEqual(plan.chaseBearing(course: -20, lookAhead: nil), 340, accuracy: 1e-9)
        XCTAssertEqual(plan.lookAheadDistance(cameraDistance: 220_000), 33_000, accuracy: 1e-9)
        XCTAssertEqual(plan.lookAheadDistance(cameraDistance: 0), 1_500)
    }

    func testAircraftSitsInTheLowerThirdOfTheVisibleMap() {
        let plan = FlightFollowCameraPlan.self
        let height = 480.0, inset = 60.0
        let fraction = plan.anchorScreenFraction(viewHeight: height, bottomInset: inset)
        let y = height / 2 + fraction * height / 2
        let visible = height - inset
        XCTAssertGreaterThan(y / visible, 2.0 / 3)
        XCTAssertLessThan(y / visible, 0.8)
        // Coefficient 0, no inset: the centre (Mapbox's anchor at zero pitch).
        XCTAssertEqual(plan.anchorScreenFraction(viewHeight: height, bottomInset: 0, coefficient: 0), 0)
    }

    func testGroundAheadMatchesAPinholeCamera() {
        let plan = FlightFollowCameraPlan.self
        let d = 100_000.0, tanHalf = 0.55, f = 0.3
        // Flat camera: the screen offset maps linearly onto the ground.
        XCTAssertEqual(plan.groundAhead(distance: d, pitchDegrees: 0, screenFraction: f,
                                        halfFieldTangent: tanHalf), d * f * tanHalf, accuracy: 1e-6)
        // Pitched: trace the ray independently and compare.
        for pitch in [30.0, 45, 60] {
            let p = pitch * .pi / 180
            let camHeight = d * cos(p)
            let centreGround = d * sin(p)            // centre, measured from below the camera
            let alpha = atan(f * tanHalf)
            let rayGround = camHeight * tan(p - alpha) // where the aircraft's ray lands
            XCTAssertEqual(plan.groundAhead(distance: d, pitchDegrees: pitch, screenFraction: f,
                                            halfFieldTangent: tanHalf),
                           centreGround - rayGround, accuracy: 1e-6)
            // Tilting puts more ground between the aircraft and the centre.
            XCTAssertGreaterThan(centreGround - rayGround, d * f * tanHalf)
        }
    }
}
