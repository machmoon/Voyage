import XCTest
@testable import Voyage

/// Boundaries of the cold-start globe cover's hold. Pure policy — no MapKit, no
/// network, no SwiftUI.
final class StartupGlobeGateTests: XCTestCase {

    // MARK: - Hold is finite (offline-safe: the cover always resolves)

    func testHoldIsPositiveAndBounded() {
        // The cover must actually cover something, and must never be infinite —
        // an offline launch that never streams a tile still has to reveal the
        // deterministic globe. A finite, positive hold guarantees both.
        XCTAssertGreaterThan(StartupGlobeGate.holdDuration, 0)
        XCTAssertLessThan(StartupGlobeGate.holdDuration, 3.0)
        XCTAssertTrue(StartupGlobeGate.holdDuration.isFinite)
    }

    // MARK: - Reduce Motion

    func testReduceMotionDisablesTheCrossfadeButKeepsTheHold() {
        // Under Reduce Motion the dissolve is instant, but the hold that swallows
        // the black frames is unchanged — so accessibility still gets no flash.
        XCTAssertEqual(StartupGlobeGate.fadeDuration(reduceMotion: true), 0)
        XCTAssertGreaterThan(StartupGlobeGate.fadeDuration(reduceMotion: false), 0)
    }

    // MARK: - Play only on the first globe of the session

    func testCoverPlaysOnTheFirstGlobeAndIsSuppressedAfterward() {
        XCTAssertTrue(StartupGlobeGate.shouldPlayCover(hasShownGlobeThisSession: false))
        XCTAssertFalse(StartupGlobeGate.shouldPlayCover(hasShownGlobeThisSession: true))
    }

    // MARK: - Coordinator lifecycle

    @MainActor
    func testCoordinatorRemembersAGlobeHasBeenShown() {
        let coordinator = StartupGlobeCoordinator()
        XCTAssertFalse(coordinator.hasShownGlobe)
        // First globe plays; every globe after it in the session is suppressed.
        XCTAssertTrue(StartupGlobeGate.shouldPlayCover(hasShownGlobeThisSession: coordinator.hasShownGlobe))
        coordinator.markGlobeShown()
        XCTAssertTrue(coordinator.hasShownGlobe)
        XCTAssertFalse(StartupGlobeGate.shouldPlayCover(hasShownGlobeThisSession: coordinator.hasShownGlobe))
    }
}
