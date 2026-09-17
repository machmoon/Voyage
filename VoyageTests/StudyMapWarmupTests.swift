import XCTest
@testable import Voyage

/// Boundaries of the in-flight map warm-up. Pure policy — no MapKit, no
/// network, no SwiftUI.
final class StudyMapWarmupTests: XCTestCase {

    private let start = StudyMapWarmup.warmStartDelay(shortFlights: false)      // 1.5
    private let warm = StudyMapWarmup.warmDuration(shortFlights: false)         // 20
    private let keepAlive = StudyMapWarmup.keepAliveAfterLeaving(shortFlights: false) // 120

    private func shouldMount(
        showing: Bool = false,
        opened: Bool = false,
        inFlight: TimeInterval? = nil,
        leftMap: TimeInterval? = nil,
        useful: Bool = true
    ) -> Bool {
        StudyMapWarmup.shouldMountMap(
            isShowingMap: showing,
            hasOpenedMap: opened,
            secondsSinceInFlightBegan: inFlight,
            secondsSinceLeftMap: leftMap,
            warmingIsUseful: useful
        )
    }

    // MARK: The map the user is looking at is always mounted

    func testVisibleMapIsAlwaysMounted() {
        XCTAssertTrue(shouldMount(showing: true, inFlight: nil))
        // Even offline, and even long after every warm window has closed.
        XCTAssertTrue(shouldMount(showing: true, opened: true, inFlight: 7_200, useful: false))
    }

    // MARK: Warm window before first use

    func testNothingIsMountedBeforeTheWarmWindowOpens() {
        XCTAssertFalse(shouldMount(inFlight: 0))
        XCTAssertFalse(shouldMount(inFlight: start - 0.01))
    }

    func testWarmMountOpensAtTheDelayAndClosesAfterTheWarmDuration() {
        XCTAssertTrue(shouldMount(inFlight: start))
        XCTAssertTrue(shouldMount(inFlight: start + warm - 0.01))
        XCTAssertFalse(shouldMount(inFlight: start + warm))
    }

    func testCruiseCarriesNoLiveMapOnceTheWarmWindowHasClosed() {
        // The whole point of not simply leaving it mounted for the session.
        XCTAssertFalse(shouldMount(inFlight: 3_600))
        XCTAssertFalse(shouldMount(opened: true, inFlight: 3_600, leftMap: 3_000))
    }

    func testWarmPassIsOneShotAndDoesNotRepeatAfterFirstOpen() {
        XCTAssertTrue(shouldMount(opened: false, inFlight: start + 1))
        XCTAssertFalse(shouldMount(opened: true, inFlight: start + 1))
    }

    // MARK: Keep-alive after switching away

    func testKeepAliveHoldsTheMapBrieflyAfterLeaving() {
        XCTAssertTrue(shouldMount(opened: true, inFlight: 600, leftMap: 0))
        XCTAssertTrue(shouldMount(opened: true, inFlight: 600, leftMap: keepAlive - 0.01))
        XCTAssertFalse(shouldMount(opened: true, inFlight: 600, leftMap: keepAlive))
    }

    // MARK: Never warm on a signal that cannot arrive

    func testOfflineSkipsWarmingEntirely() {
        XCTAssertFalse(shouldMount(inFlight: start + 1, useful: false))
    }

    func testForcedOfflineSceneryProcessSkipsWarming() {
        XCTAssertFalse(
            StudyMapWarmup.warmingIsUseful(streamedSceneryAllowed: false, isOnline: true)
        )
        XCTAssertFalse(
            StudyMapWarmup.warmingIsUseful(streamedSceneryAllowed: true, isOnline: false)
        )
        XCTAssertTrue(
            StudyMapWarmup.warmingIsUseful(streamedSceneryAllowed: true, isOnline: true)
        )
    }

    func testOfflineStillMountsOnDemandSoBehaviourMatchesTheOldMountOnSwitch() {
        XCTAssertTrue(shouldMount(showing: true, useful: false))
    }

    // MARK: Tile cover

    private func covered(_ tiles: WorldSceneryLoadState, online: Bool = true, ceiling: Bool = false) -> Bool {
        StudyMapWarmup.showsTileCover(tiles: tiles, isOnline: online, ceilingPassed: ceiling)
    }

    func testLoadingMapStaysCoveredUntilTheCeiling() {
        XCTAssertTrue(covered(.loading))
        XCTAssertFalse(covered(.loading, ceiling: true))
    }

    func testFullyRenderedMapIsRevealedAtOnce() {
        XCTAssertFalse(covered(.ready))
        XCTAssertFalse(covered(.ready, online: false))
    }

    func testFailedOrOfflineMapIsNeverRevealedAsBareGrid() {
        XCTAssertTrue(covered(.failed, ceiling: true))
        XCTAssertTrue(covered(.loading, online: false, ceiling: true))
    }

    // MARK: QA short flights stay compressed

    func testShortFlightsCompressEveryWindow() {
        XCTAssertLessThan(
            StudyMapWarmup.warmStartDelay(shortFlights: true),
            StudyMapWarmup.warmStartDelay(shortFlights: false)
        )
        XCTAssertLessThan(
            StudyMapWarmup.warmDuration(shortFlights: true),
            StudyMapWarmup.warmDuration(shortFlights: false)
        )
        XCTAssertLessThan(
            StudyMapWarmup.keepAliveAfterLeaving(shortFlights: true),
            StudyMapWarmup.keepAliveAfterLeaving(shortFlights: false)
        )
    }

    func testShortFlightWarmWindowIsOpenWhenTheScreenshotTourReachesTheMap() {
        // The tour tears the pass, samples the window for ~11s, then taps Map.
        // The map must have been warmed (or be mountable on demand) by then.
        let short = true
        let openAt = StudyMapWarmup.warmStartDelay(shortFlights: short)
        XCTAssertLessThan(openAt, 1.0)
        XCTAssertTrue(
            StudyMapWarmup.shouldMountMap(
                isShowingMap: true,
                hasOpenedMap: false,
                secondsSinceInFlightBegan: 11,
                secondsSinceLeftMap: nil,
                warmingIsUseful: false,
                shortFlights: short
            )
        )
    }
}
