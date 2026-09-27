import XCTest
@testable import Voyage

/// The trip replay's camera policy. Pure — no MapKit, no clock.
final class ReplayCameraPlanTests: XCTestCase {

    // MARK: Follow altitude

    func testSlowAircraftKeepsTheCloseFollowCamera() {
        // A short hop: 60 km of ground a second is well under half a screenful
        // at 320 km, so the camera stays at its closest.
        let distance = ReplayCameraPlan.followDistance(
            groundSpeed: 60_000, screenfulPerDistance: 1, fitDistance: 2_000_000)
        XCTAssertEqual(distance, ReplayCameraPlan.minimumFollowDistance)
    }

    func testFastAircraftClimbsSoTheSweepStaysBounded() {
        // BOS–LAX in five seconds: ~840 km of ground a second.
        let k = 1.1
        let distance = ReplayCameraPlan.followDistance(
            groundSpeed: 840_000, screenfulPerDistance: k, fitDistance: 10_000_000)
        let screenfulsPerSecond = 840_000 / (distance * k)
        XCTAssertEqual(screenfulsPerSecond, ReplayCameraPlan.maxScreenfulsPerSecond, accuracy: 0.000_1)
        XCTAssertGreaterThan(distance, ReplayCameraPlan.minimumFollowDistance)
    }

    func testFollowNeverFliesAboveTheWholeLeg() {
        let distance = ReplayCameraPlan.followDistance(
            groundSpeed: 5_000_000, screenfulPerDistance: 1, fitDistance: 3_000_000)
        XCTAssertEqual(distance, 3_000_000)
    }

    func testDegenerateInputsFallBackToTheCloseCamera() {
        XCTAssertEqual(ReplayCameraPlan.followDistance(groundSpeed: 0, screenfulPerDistance: 1, fitDistance: 1e7),
                       ReplayCameraPlan.minimumFollowDistance)
        XCTAssertEqual(ReplayCameraPlan.followDistance(groundSpeed: .nan, screenfulPerDistance: 1, fitDistance: 1e7),
                       ReplayCameraPlan.minimumFollowDistance)
        XCTAssertEqual(ReplayCameraPlan.followDistance(groundSpeed: 1e5, screenfulPerDistance: 0, fitDistance: 1e7),
                       ReplayCameraPlan.minimumFollowDistance)
    }

    func testDistanceEasesTowardTheTargetWithoutOvershoot() {
        var distance = 400_000.0
        var previous = distance
        for _ in 0..<60 {
            distance = ReplayCameraPlan.easedDistance(from: distance, to: 1_600_000, elapsed: 1.0 / 60)
            XCTAssertGreaterThan(distance, previous)
            XCTAssertLessThanOrEqual(distance, 1_600_000)
            previous = distance
        }
        // One second is well past the 0.6 s time constant: most of the way there.
        XCTAssertGreaterThan(distance, 1_200_000)
        XCTAssertEqual(ReplayCameraPlan.easedDistance(from: distance, to: 1_600_000, elapsed: 0), distance)
    }

    // MARK: Glides

    func testGlideStartsAndEndsOnItsFramings() {
        let glide = ReplayCameraPlan.Glide(startSpan: 100, endSpan: 40, distance: 900)
        let start = glide.sample(0)
        XCTAssertEqual(start.travelled, 0, accuracy: 0.000_1)
        XCTAssertEqual(start.span, 100, accuracy: 0.000_1)
        let end = glide.sample(1)
        XCTAssertEqual(end.travelled, 1)
        XCTAssertEqual(end.span, 40)
        // Just short of the end, the path has already converged on it.
        let nearEnd = glide.sample(0.999)
        XCTAssertEqual(nearEnd.travelled, 1, accuracy: 0.01)
        XCTAssertEqual(nearEnd.span, 40, accuracy: 1)
    }

    func testLongGlideZoomsOutMidFlight() {
        // Nine screenfuls away: van Wijk's path climbs above both ends.
        let glide = ReplayCameraPlan.Glide(startSpan: 100, endSpan: 100, distance: 900)
        let middle = glide.sample(0.5)
        XCTAssertGreaterThan(middle.span, 100)
        XCTAssertEqual(middle.travelled, 0.5, accuracy: 0.05)
    }

    func testGlideProgressIsMonotonic() {
        let glide = ReplayCameraPlan.Glide(startSpan: 250, endSpan: 60, distance: 1_400)
        var last = -1.0
        for step in 0...100 {
            let travelled = glide.sample(Double(step) / 100).travelled
            XCTAssertGreaterThanOrEqual(travelled, last)
            last = travelled
        }
    }

    func testZoomOnlyGlideStaysPut() {
        let glide = ReplayCameraPlan.Glide(startSpan: 100, endSpan: 25, distance: 0)
        XCTAssertEqual(glide.sample(0.5).travelled, 0.5)
        XCTAssertEqual(glide.sample(0.5).span, 50, accuracy: 0.5)   // halfway in zoom levels
        XCTAssertEqual(glide.sample(1).span, 25)
    }

    func testGlideDurationIsKeptShort() {
        let range = ReplayCameraPlan.glideDurationRange
        let tiny = ReplayCameraPlan.Glide(startSpan: 100, endSpan: 100, distance: 1)
        let huge = ReplayCameraPlan.Glide(startSpan: 100, endSpan: 100, distance: 1_000_000)
        XCTAssertEqual(tiny.duration, range.lowerBound)
        XCTAssertEqual(huge.duration, range.upperBound)
    }

    func testOnlyARealJumpIsFlown() {
        XCTAssertFalse(ReplayCameraPlan.needsGlide(jump: 10, screenful: 100))
        XCTAssertFalse(ReplayCameraPlan.needsGlide(jump: 50, screenful: 100))
        XCTAssertTrue(ReplayCameraPlan.needsGlide(jump: 51, screenful: 100))
        XCTAssertFalse(ReplayCameraPlan.needsGlide(jump: 51, screenful: 0))
    }

    // MARK: Route prefetch

    func testWarmStopsCoverTheLegWithOverlap() {
        let stops = ReplayCameraPlan.warmStops(legScreenfuls: 2.5)
        XCTAssertEqual(stops.first, 0)
        XCTAssertEqual(stops.last, 1)
        // 2.5 screenfuls at ≤ 0.8 apart: four gaps.
        XCTAssertEqual(stops.count, 5)
        for (a, b) in zip(stops, stops.dropFirst()) {
            XCTAssertLessThanOrEqual((b - a) * 2.5, ReplayCameraPlan.warmStepScreenfuls + 0.000_1)
        }
    }

    func testShortLegNeedsOnlyItsEnds() {
        XCTAssertEqual(ReplayCameraPlan.warmStops(legScreenfuls: 0.3), [0, 1])
    }

    func testDegenerateLegWarmsItsStart() {
        XCTAssertEqual(ReplayCameraPlan.warmStops(legScreenfuls: 0), [0])
        XCTAssertEqual(ReplayCameraPlan.warmStops(legScreenfuls: .infinity), [0])
    }

    // MARK: Start gate

    func testPlaybackWaitsForAFullRender() {
        XCTAssertFalse(ReplayCameraPlan.playbackMayStart(tiles: .loading, ceilingPassed: false))
        XCTAssertTrue(ReplayCameraPlan.playbackMayStart(tiles: .ready, ceilingPassed: false))
    }

    func testPlaybackNeverWaitsForever() {
        XCTAssertTrue(ReplayCameraPlan.playbackMayStart(tiles: .loading, ceilingPassed: true))
    }

    func testFailedMapStillPlays() {
        XCTAssertTrue(ReplayCameraPlan.playbackMayStart(tiles: .failed, ceilingPassed: false))
    }
}
