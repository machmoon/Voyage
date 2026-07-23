import XCTest
@testable import Voyage

/// Boundaries of the departure-curtain hold. Pure policy — no MapKit, no
/// network, no SwiftUI.
final class DepartureGateTests: XCTestCase {

    private let minimum = DepartureGate.minimumHold(shortFlights: false)   // 2.8
    private let maximum = DepartureGate.maximumHold(shortFlights: false)   // 7.0

    private func shouldDepart(
        ready: Bool,
        elapsed: TimeInterval,
        waitsForMap: Bool = true,
        minimum: TimeInterval? = nil,
        maximum: TimeInterval? = nil
    ) -> Bool {
        DepartureGate.shouldDepart(
            mapHasRenderedFrame: ready,
            elapsed: elapsed,
            minimum: minimum ?? self.minimum,
            maximum: maximum ?? self.maximum,
            waitsForMap: waitsForMap
        )
    }

    // MARK: - Minimum floor

    func testHoldsBelowMinimumEvenWhenMapIsAlreadyReady() {
        XCTAssertFalse(shouldDepart(ready: true, elapsed: 0))
        XCTAssertFalse(shouldDepart(ready: true, elapsed: minimum - 0.01))
    }

    func testHoldsBelowMinimumWhenNotWaitingForMap() {
        XCTAssertFalse(shouldDepart(ready: false, elapsed: minimum - 0.01, waitsForMap: false))
    }

    func testDepartsExactlyAtMinimumWhenMapIsReady() {
        XCTAssertTrue(shouldDepart(ready: true, elapsed: minimum))
    }

    // MARK: - Waiting window

    func testWaitsPastMinimumWhileMapIsNotReady() {
        XCTAssertFalse(shouldDepart(ready: false, elapsed: minimum))
        XCTAssertFalse(shouldDepart(ready: false, elapsed: maximum - 0.01))
    }

    func testDepartsMidWindowTheInstantTheMapReportsIn() {
        let midpoint = (minimum + maximum) / 2
        XCTAssertFalse(shouldDepart(ready: false, elapsed: midpoint))
        XCTAssertTrue(shouldDepart(ready: true, elapsed: midpoint))
    }

    // MARK: - Ceiling: the app always departs

    func testDepartsAtMaximumWithNoMapSignalAtAll() {
        XCTAssertTrue(shouldDepart(ready: false, elapsed: maximum))
        XCTAssertTrue(shouldDepart(ready: false, elapsed: maximum + 60))
    }

    func testInvertedBoundsStillDepart() {
        // Defensive: a mis-set ceiling below the floor must not deadlock.
        XCTAssertTrue(shouldDepart(ready: false, elapsed: 5, minimum: 4, maximum: 1))
    }

    // MARK: - Fall-through paths behave exactly like the old fixed timing

    func testNotWaitingForMapDepartsAtMinimumRegardlessOfSignal() {
        XCTAssertTrue(shouldDepart(ready: false, elapsed: minimum, waitsForMap: false))
        XCTAssertTrue(shouldDepart(ready: false, elapsed: minimum + 0.5, waitsForMap: false))
    }

    // MARK: - waitsForMap policy

    func testIllustratedModeNeverWaits() {
        XCTAssertFalse(
            DepartureGate.waitsForMap(
                worldMode: .illustrated, streamedSceneryAllowed: true, isOnline: true
            )
        )
    }

    func testOfflineNeverWaits() {
        XCTAssertFalse(
            DepartureGate.waitsForMap(
                worldMode: .real, streamedSceneryAllowed: true, isOnline: false
            )
        )
    }

    func testForcedOfflineSceneryProcessNeverWaits() {
        XCTAssertFalse(
            DepartureGate.waitsForMap(
                worldMode: .real, streamedSceneryAllowed: false, isOnline: true
            )
        )
    }

    func testRealModeOnlineWaits() {
        XCTAssertTrue(
            DepartureGate.waitsForMap(
                worldMode: .real, streamedSceneryAllowed: true, isOnline: true
            )
        )
    }

    // MARK: - QA short-flight path stays prompt

    func testShortFlightsStayWellInsideUITestBudgets() {
        let quickMin = DepartureGate.minimumHold(shortFlights: true)
        let quickMax = DepartureGate.maximumHold(shortFlights: true)
        XCTAssertEqual(quickMin, 1.6, accuracy: 0.001)
        XCTAssertLessThan(quickMin, minimum)
        XCTAssertLessThan(quickMax, maximum)
        // The screenshot tour samples the in-flight window ~2s after the tear
        // and the SFO tour allows 12s; the compressed ceiling must clear both.
        XCTAssertLessThanOrEqual(quickMax, 3.0)
    }

    func testMinimumIsAlwaysBelowMaximum() {
        for short in [true, false] {
            XCTAssertLessThan(
                DepartureGate.minimumHold(shortFlights: short),
                DepartureGate.maximumHold(shortFlights: short)
            )
        }
    }

    // MARK: - Readiness signal lifecycle

    @MainActor
    func testReadinessResetsForANewBooking() {
        let readiness = DepartureReadiness()
        XCTAssertFalse(readiness.mapHasRenderedFrame)
        readiness.markMapRendered()
        XCTAssertTrue(readiness.mapHasRenderedFrame)
        readiness.resetForNewBooking()
        XCTAssertFalse(readiness.mapHasRenderedFrame)
    }
}
