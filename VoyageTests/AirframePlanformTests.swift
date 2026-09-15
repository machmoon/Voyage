import XCTest
import SwiftUI
@testable import Voyage

/// The seat map's airframe geometry and the launch flyover's clock. Pure
/// geometry and arithmetic, no rendering.
final class AirframePlanformTests: XCTestCase {

    // MARK: - Wing section sweep

    func testSweepAtItsOwnLocationIsTheQuotedSweep() {
        let wing = AircraftProfile.boeing737800.planform.wing
        XCTAssertEqual(wing.tanSweep(at: wing.sweepLocation), tan(wing.sweep * .pi / 180), accuracy: 1e-12)
    }

    func testLeadingEdgeSweepMatchesTheQuarterChordGeometry() {
        // A tapered wing's leading edge sweeps more than its quarter chord by
        // exactly a quarter of the chord lost over the span.
        for profile in AircraftProfile.allCases {
            let wing = profile.planform.wing
            let expected = tan(wing.sweep * .pi / 180) + 0.25 * (wing.rootChord - wing.tipChord) / wing.span
            XCTAssertEqual(wing.tanSweep(at: 0), expected, accuracy: 1e-9, profile.name)
        }
    }

    func testChordTapersFromRootToTip() {
        let wing = AircraftProfile.airbusA320neo.planform.wing
        XCTAssertEqual(wing.chord(at: 0), wing.rootChord)
        XCTAssertEqual(wing.chord(at: wing.span), wing.tipChord)
        XCTAssertEqual(wing.chord(at: wing.span * 2), wing.tipChord, "Clamped past the tip")
    }

    func testPublishedSpansAreRoughlyRight() {
        XCTAssertEqual(AircraftProfile.boeing737800.planform.totalSpan, 34.4, accuracy: 0.5)
        XCTAssertEqual(AircraftProfile.airbusA320neo.planform.totalSpan, 35.8, accuracy: 0.5)
    }

    // MARK: - Seat map layout

    /// The seat map draws a 3-3 fuselage 286pt wide and a 1-1 fuselage 138pt
    /// wide, with one 46pt row pitch per real seat pitch.
    private func seatMapOutline(_ profile: AircraftProfile, screenWidth: CGFloat = 440) -> AirframeOutline {
        let planform = profile.planform
        let drawnWidth: CGFloat = profile == .boomOverture ? 138 : 286
        return AirframeOutline(planform: planform, midX: screenWidth / 2,
                               xScale: drawnWidth / CGFloat(planform.fuselageWidth),
                               yScale: 46 / CGFloat(AirframePlanform.seatPitch),
                               noseTipY: 0, exitY: 900, tailEndY: 2000)
    }

    func testWingsRunPastBothEdgesOfTheWidestIPhone() {
        for profile in AircraftProfile.allCases {
            let outline = seatMapOutline(profile)
            XCTAssertLessThan(outline.wing(side: -1).boundingRect.minX, 0, profile.name)
            XCTAssertGreaterThan(outline.wing(side: 1).boundingRect.maxX, 440, profile.name)
        }
    }

    func testTailplaneRunsPastTheEdgesOnNarrowbodies() {
        for profile in [AircraftProfile.boeing737800, .airbusA320neo, .voyageClassic] {
            let tail = try? XCTUnwrap(seatMapOutline(profile).horizontalTail(side: 1))
            XCTAssertGreaterThan(tail?.boundingRect.maxX ?? 0, 440, profile.name)
        }
        XCTAssertNil(seatMapOutline(.boomOverture).horizontalTail(side: 1),
                     "A tailless delta has no stabiliser")
    }

    func testWingRootSpansTheExitRows() {
        for profile in AircraftProfile.allCases {
            let root = seatMapOutline(profile).wing(side: 1).boundingRect
            // The leading edge is ahead of the exits and the root chord runs
            // several rows behind them.
            XCTAssertLessThan(root.minY, 900, profile.name)
            XCTAssertGreaterThan(root.maxY, 900 + 46 * 3, profile.name)
        }
    }

    func testNarrowbodyRootChordCoversAboutEightRows() {
        let wing = AircraftProfile.boeing737800.planform.wing
        XCTAssertEqual(wing.rootChord / AirframePlanform.seatPitch, 8, accuracy: 1.5)
    }

    // MARK: - Flyover clock

    @MainActor
    func testClockCapsEachStepSoAHitchPausesThePlane() {
        let clock = FlyoverClock()
        let start = Date(timeIntervalSinceReferenceDate: 0)
        XCTAssertEqual(clock.advance(to: start), 0)
        XCTAssertEqual(clock.advance(to: start.addingTimeInterval(1.0 / 60)), 1.0 / 60, accuracy: 1e-9)
        // A one second hitch moves the animation on by one capped step.
        let afterHitch = clock.advance(to: start.addingTimeInterval(1 + 1.0 / 60))
        XCTAssertEqual(afterHitch, 1.0 / 60 + FlyoverClock.maxStep, accuracy: 1e-9)
    }

    @MainActor
    func testClockIgnoresRepeatedAndOlderDates() {
        let clock = FlyoverClock()
        let start = Date(timeIntervalSinceReferenceDate: 0)
        _ = clock.advance(to: start)
        let frame = start.addingTimeInterval(0.02)
        let once = clock.advance(to: frame)
        XCTAssertEqual(clock.advance(to: frame), once)
        XCTAssertEqual(clock.advance(to: start), once)
    }

    func testFlyoverCeilingIsShort() {
        XCTAssertLessThanOrEqual(FlyoverClock.ceiling, 4.0)
    }
}
