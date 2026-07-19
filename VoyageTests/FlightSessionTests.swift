import XCTest
import SwiftData
@testable import Voyage

@MainActor
final class FlightSessionTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var clock: ManualClock!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: LogbookEntry.self, configurations: config)
        context = ModelContext(container)
        clock = ManualClock(now: Date(timeIntervalSince1970: 1_700_000_000))
        // Keep PA/audio quiet during unit tests.
        SettingsStore.shared.ambienceEnabled = false
        SettingsStore.shared.announcementsEnabled = false
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        clock = nil
    }

    // MARK: Phase transitions

    func testPhasesProgressWithElapsedTime() {
        let session = makeSession(duration: 600) // 10-minute synthetic leg
        session.departFirstLeg()
        XCTAssertEqual(session.stage, .inFlight)
        XCTAssertEqual(session.phase, .takeoffRoll)

        clock.advance(by: FlightSession.takeoffRollDuration)
        session.tick()
        XCTAssertEqual(session.phase, .climb)

        clock.advance(by: FlightSession.climbEndsAt - FlightSession.takeoffRollDuration)
        session.tick()
        XCTAssertEqual(session.phase, .cruise)

        // Jump to descent window (last 180s of a 600s leg).
        clock.set(session.legStartDate!.addingTimeInterval(600 - FlightSession.descentDuration + 1))
        session.tick()
        XCTAssertEqual(session.phase, .descent)

        clock.set(session.legStartDate!.addingTimeInterval(600 - FlightSession.landingDuration + 1))
        session.tick()
        XCTAssertEqual(session.phase, .landing)
    }

    func testDirectFlightCompletesAndWritesLogbook() throws {
        let session = makeSession(duration: 120)
        session.seat = "14A"
        session.intentions = ["Read chapter 3"]
        session.departFirstLeg()

        clock.advance(by: 120)
        session.tick()

        XCTAssertEqual(session.stage, .arrived)
        XCTAssertNotNil(session.logEntry)
        XCTAssertEqual(session.logEntry?.completed, true)
        XCTAssertEqual(session.logEntry?.seat, "14A")
        XCTAssertEqual(session.logEntry!.focusSeconds, 120, accuracy: 0.1)
        XCTAssertGreaterThan(session.completedMiles, 0)

        let entries = try context.fetch(FetchDescriptor<LogbookEntry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries[0].completed)
    }

    // MARK: Layover / connection

    func testConnectionEntersLayoverThenBoardsSecondLeg() {
        let session = makeConnectionSession(leg1: 90, layover: 40, leg2: 100)
        session.departFirstLeg()

        clock.advance(by: 90)
        session.tick()
        XCTAssertEqual(session.stage, .layover)
        XCTAssertEqual(session.legIndex, 0)
        XCTAssertNotNil(session.connectionDeparts)

        session.boardConnection()
        XCTAssertEqual(session.stage, .inFlight)
        XCTAssertEqual(session.legIndex, 1)

        clock.advance(by: 100)
        session.tick()
        XCTAssertEqual(session.stage, .arrived)
        XCTAssertEqual(session.logEntry?.completed, true)
        XCTAssertEqual(session.logEntry!.focusSeconds, 190, accuracy: 0.1)
    }

    func testLayoverWindowExpiryMissesConnection() {
        let session = makeConnectionSession(leg1: 60, layover: 30, leg2: 60)
        session.departFirstLeg()

        clock.advance(by: 60)
        session.tick()
        XCTAssertEqual(session.stage, .layover)

        // Past layover + final-call window.
        clock.advance(by: 30 + FlightSession.finalCallWindow + 1)
        session.tick()
        XCTAssertEqual(session.stage, .missedConnection)
        XCTAssertEqual(session.logEntry?.completed, false)
        // First leg still credited.
        XCTAssertEqual(session.completedFocusSeconds, 60, accuracy: 0.1)
        XCTAssertGreaterThan(session.completedMiles, 0)
    }

    // MARK: Grace / diversion

    func testBackgroundWithinGraceDoesNotDivert() {
        let session = makeSession(duration: 300)
        session.departFirstLeg()
        session.handleScenePhase(.background)
        XCTAssertNotNil(session.graceDeadline)

        clock.advance(by: 10)
        session.handleScenePhase(.active)
        XCTAssertEqual(session.stage, .inFlight)
        XCTAssertNil(session.graceDeadline)
    }

    func testGracePeriodExpiryDivertsViaTick() {
        let session = makeSession(duration: 300)
        session.departFirstLeg()
        session.handleScenePhase(.background)

        clock.advance(by: FlightSession.graceDuration + 0.1)
        session.tick()
        XCTAssertEqual(session.stage, .diverted)
        XCTAssertEqual(session.logEntry?.completed, false)
        XCTAssertGreaterThan(session.logEntry?.focusSeconds ?? 0, 0)
    }

    func testReturningAfterGraceDeadlineDiverts() {
        let session = makeSession(duration: 300)
        session.departFirstLeg()
        session.handleScenePhase(.background)

        clock.advance(by: FlightSession.graceDuration + 1)
        session.handleScenePhase(.active)
        XCTAssertEqual(session.stage, .diverted)
    }

    func testAbandonFlightDiverts() {
        let session = makeSession(duration: 300)
        session.departFirstLeg()
        session.abandonFlight()
        XCTAssertEqual(session.stage, .diverted)
        XCTAssertEqual(session.logEntry?.completed, false)
    }

    func testCancelBeforeDepartureLeavesNoLogEntry() throws {
        let session = makeSession(duration: 300)
        session.cancelBeforeDeparture()
        XCTAssertEqual(session.stage, .preflight)
        let entries = try context.fetch(FetchDescriptor<LogbookEntry>())
        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: Helpers

    private func makeSession(duration: TimeInterval) -> FlightSession {
        let origin = Airport.byCode("BOS")
        let destination = Airport.byCode("JFK")
        let leg = FlightLeg(
            origin: origin,
            destination: destination,
            duration: duration,
            flightNumber: "VA 214"
        )
        let itinerary = Itinerary(legs: [leg], layoverDuration: 0)
        return FlightSession(itinerary: itinerary, modelContext: context, tier: .member, clock: clock)
    }

    private func makeConnectionSession(leg1: TimeInterval, layover: TimeInterval, leg2: TimeInterval) -> FlightSession {
        let bos = Airport.byCode("BOS")
        let yyz = Airport.byCode("YYZ")
        let yqr = Airport.byCode("YQR")
        let itinerary = Itinerary(
            legs: [
                FlightLeg(origin: bos, destination: yyz, duration: leg1, flightNumber: "VA 101"),
                FlightLeg(origin: yyz, destination: yqr, duration: leg2, flightNumber: "VA 102"),
            ],
            layoverDuration: layover
        )
        return FlightSession(itinerary: itinerary, modelContext: context, tier: .gold, clock: clock)
    }
}
