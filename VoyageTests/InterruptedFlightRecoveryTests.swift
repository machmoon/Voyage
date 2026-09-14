import XCTest
import SwiftData
@testable import Voyage

/// A flight the process did not survive must still reach the logbook.
@MainActor
final class InterruptedFlightRecoveryTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var defaults: UserDefaults!
    private var clock: ManualClock!

    override func setUp() async throws {
        try await super.setUp()
        SettingsStore.shared.ambienceEnabled = false
        SettingsStore.shared.announcementsEnabled = false
        container = try ModelContainer(
            for: LogbookEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
        defaults = UserDefaults(suiteName: "InterruptedFlightRecoveryTests")!
        defaults.removePersistentDomain(forName: "InterruptedFlightRecoveryTests")
        clock = ManualClock(now: Date(timeIntervalSince1970: 1_700_000_000))
        InterruptedFlightRecovery.clear()
    }

    override func tearDown() async throws {
        InterruptedFlightRecovery.clear()
        defaults.removePersistentDomain(forName: "InterruptedFlightRecoveryTests")
        try await super.tearDown()
    }

    private func record(legDuration: TimeInterval = 3_600) -> InFlightRecord {
        InFlightRecord(
            originCode: "SFO", destinationCode: "LAX", connectionCode: nil,
            flightNumber: "VOY 424", seat: "C7", intentions: ["Chapter 4"],
            departedAt: clock.now,
            completedFocusSeconds: 0, completedMiles: 0,
            legStartedAt: clock.now, legDuration: legDuration,
            scheduledSeconds: legDuration
        )
    }

    func testNothingPendingWritesNothing() throws {
        XCTAssertNil(InterruptedFlightRecovery.recover(into: context, defaults: defaults))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LogbookEntry>()), 0)
    }

    func testPendingRecordBecomesDivertedEntryAndClears() throws {
        InterruptedFlightRecovery.save(record(), defaults: defaults)

        let later = clock.now.addingTimeInterval(20 * 60)
        let entry = try XCTUnwrap(InterruptedFlightRecovery.recover(into: context, now: later, defaults: defaults))

        XCTAssertEqual(entry.originCode, "SFO")
        XCTAssertEqual(entry.destinationCode, "LAX")
        XCTAssertEqual(entry.outcome, .interrupted)
        XCTAssertFalse(entry.completed)
        XCTAssertEqual(entry.focusSeconds, 20 * 60, accuracy: 1)
        XCTAssertEqual(entry.intentions, ["Chapter 4"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LogbookEntry>()), 1)
        XCTAssertNil(InterruptedFlightRecovery.pending(defaults: defaults), "Recovery is one-shot")
    }

    func testAFlightKilledInsideItsFirstMinuteIsNotLogged() throws {
        InterruptedFlightRecovery.save(record(), defaults: defaults)
        let soon = clock.now.addingTimeInterval(40)
        XCTAssertNil(InterruptedFlightRecovery.recover(into: context, now: soon, defaults: defaults),
                     "A false start has nothing worth a logbook row or an alert")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LogbookEntry>()), 0)
        XCTAssertNil(InterruptedFlightRecovery.pending(defaults: defaults), "The record is still cleared")
    }

    func testFocusIsCappedAtTheLegLength() throws {
        InterruptedFlightRecovery.save(record(legDuration: 600), defaults: defaults)
        let muchLater = clock.now.addingTimeInterval(3 * 24 * 3_600)
        let entry = try XCTUnwrap(InterruptedFlightRecovery.recover(into: context, now: muchLater, defaults: defaults))
        XCTAssertEqual(entry.focusSeconds, 600, accuracy: 1)
        XCTAssertEqual(entry.date, clock.now.addingTimeInterval(600),
                       "The entry is dated when the leg would have ended, not when the app came back")
    }

    func testSessionWritesRecordOnDepartureAndClearsOnLanding() {
        let itinerary = RoutePlanner.itinerary(from: Airport.byCode("SFO"), to: Airport.byCode("LAX"))
        let session = FlightSession(itinerary: itinerary, modelContext: context, tier: .member, clock: clock)
        XCTAssertNil(InterruptedFlightRecovery.pending())

        session.departFirstLeg()
        let pending = InterruptedFlightRecovery.pending()
        XCTAssertEqual(pending?.originCode, "SFO")
        XCTAssertEqual(pending?.destinationCode, "LAX")
        XCTAssertEqual(pending?.scheduledSeconds, itinerary.totalFocusDuration)

        clock.advance(by: itinerary.totalFocusDuration + 1)
        session.tick()
        XCTAssertEqual(session.stage, .arrived)
        XCTAssertNil(InterruptedFlightRecovery.pending(), "A finished flight leaves nothing to recover")
        XCTAssertFalse(session.logbookSaveFailed)
    }

    func testDiversionAlsoClearsTheRecord() {
        let itinerary = RoutePlanner.itinerary(from: Airport.byCode("SFO"), to: Airport.byCode("LAX"))
        let session = FlightSession(itinerary: itinerary, modelContext: context, tier: .member, clock: clock)
        session.departFirstLeg()
        XCTAssertNotNil(InterruptedFlightRecovery.pending())
        session.divert()
        XCTAssertNil(InterruptedFlightRecovery.pending())
    }
}
