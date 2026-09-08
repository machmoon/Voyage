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
        SettingsStore.shared.soundEffectsEnabled = false
        SettingsStore.shared.announcementsEnabled = false
        SettingsStore.shared.cabinServiceEnabled = true
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
        let schedule = session.phaseSchedule

        // Date stores sub-second boundaries as binary floating point; step a
        // tiny amount past the exact edge to assert the new phase.
        clock.advance(by: schedule.takeoffEnd + 0.05)
        session.tick()
        XCTAssertEqual(session.phase, .climb)

        clock.advance(by: schedule.climbEnd - schedule.takeoffEnd)
        session.tick()
        XCTAssertEqual(session.phase, .cruise)

        clock.set(session.legStartDate!.addingTimeInterval(schedule.descentStart + 1))
        session.tick()
        XCTAssertEqual(session.phase, .descent)

        clock.set(session.legStartDate!.addingTimeInterval(schedule.landingStart + 1))
        session.tick()
        XCTAssertEqual(session.phase, .landing)
    }

    func testPhaseElapsedUsesInjectedClock() {
        let session = makeSession(duration: 600)
        session.departFirstLeg()

        clock.advance(by: 7)
        session.tick()
        XCTAssertEqual(session.phaseElapsed, 7, accuracy: 0.001)

        clock.set(session.legStartDate!.addingTimeInterval(session.phaseSchedule.takeoffEnd + 3))
        session.tick()
        XCTAssertEqual(session.phase, .climb)
        XCTAssertEqual(session.phaseElapsed, 3, accuracy: 0.001)
    }

    func testRotationCueFiresWhenTrajectoryBeginsRotation() throws {
        let session = makeSession(duration: 6 * 60 * 60)
        session.departFirstLeg()

        let schedule = session.phaseSchedule
        let legStart = try XCTUnwrap(session.legStartDate)
        XCTAssertGreaterThan(schedule.rotationStart, 0)
        XCTAssertLessThan(schedule.rotationStart, schedule.takeoffEnd)

        clock.set(legStart.addingTimeInterval(schedule.rotationStart - 0.05))
        session.tick()
        XCTAssertFalse(session.didFireRotationCue)

        clock.set(legStart.addingTimeInterval(schedule.rotationStart + 0.05))
        session.tick()
        XCTAssertTrue(session.didFireRotationCue)
        XCTAssertEqual(session.phase, .takeoffRoll)
    }

    func testSixHourMapSamplesIncludeRunwayAndEveryPhaseBoundary() throws {
        let session = makeSession(duration: 6 * 60 * 60)
        session.seat = "14A"
        session.departFirstLeg()

        let samples = try XCTUnwrap(session.legMapSamples.first)
        let schedule = session.phaseSchedule
        let boundaries = [
            0,
            schedule.rotationStart,
            schedule.takeoffEnd,
            schedule.climbEnd,
            schedule.descentStart,
            schedule.landingStart,
            schedule.legDuration,
        ]

        for boundary in boundaries {
            XCTAssertTrue(
                samples.contains { abs($0.elapsed - boundary) < 0.001 },
                "Expected a cached trajectory sample at \(boundary) seconds"
            )
        }

        XCTAssertGreaterThanOrEqual(
            samples.filter { $0.elapsed <= schedule.takeoffEnd + 0.001 }.count,
            20,
            "A long cruise must not starve the runway roll of map/replay detail"
        )
        XCTAssertGreaterThanOrEqual(
            samples.filter { $0.elapsed >= schedule.landingStart - 0.001 }.count,
            20,
            "A long cruise must not starve approach and rollout of replay detail"
        )
    }

    func testDirectFlightCompletesAndWritesLogbook() throws {
        let session = makeSession(duration: 120)
        session.seat = "14A"
        session.intentions = ["Read chapter 3"]
        session.departFirstLeg()
        XCTAssertEqual(session.legMapSamples.count, 1)
        XCTAssertEqual(
            session.legMapSamples[0],
            try XCTUnwrap(session.currentTrajectory).replaySamples(count: 192, seat: session.seat)
        )

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
        XCTAssertEqual(entries[0].trajectoryRevision, FlightVisualEngine.trajectoryRevision)
        XCTAssertNotNil(entries[0].departureCorridorID)
        XCTAssertNotNil(entries[0].arrivalCorridorID)
        XCTAssertEqual(entries[0].environmentSnapshots.count, 1)
        XCTAssertEqual(entries[0].trajectoryLegSamples.count, 1)
        XCTAssertEqual(entries[0].trajectoryLegSamples[0], session.legMapSamples[0])
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
        XCTAssertEqual(session.diversionReason, .voluntary)
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

    // MARK: Beverage service

    func testBeverageCartAppearsDuringCruiseAndTakingWaterDismissesIt() {
        let session = makeSession(duration: 3600)
        session.departFirstLeg()

        clock.advance(by: session.phaseSchedule.climbEnd + FlightSession.beverageFirstDelay)
        session.tick()
        XCTAssertNotNil(session.beverageCartUntil)
        XCTAssertEqual(session.watersTaken, 0)

        session.takeWater()
        XCTAssertEqual(session.watersTaken, 1)
        XCTAssertNil(session.beverageCartUntil)

        // Taking again with no cart present does nothing.
        session.takeWater()
        XCTAssertEqual(session.watersTaken, 1)
    }

    func testBeverageCartMovesOnIfIgnoredThenReturnsNextService() {
        let session = makeSession(duration: 7200)
        session.departFirstLeg()

        clock.advance(by: session.phaseSchedule.climbEnd + FlightSession.beverageFirstDelay)
        session.tick()
        XCTAssertNotNil(session.beverageCartUntil)

        clock.advance(by: FlightSession.beverageCartWindow + 1)
        session.tick()
        XCTAssertNil(session.beverageCartUntil)
        XCTAssertEqual(session.watersTaken, 0)

        clock.advance(by: FlightSession.beverageInterval)
        session.tick()
        XCTAssertNotNil(session.beverageCartUntil)
    }

    func testNoBeverageServiceOnceDescentBegins() {
        let session = makeSession(duration: 3600)
        session.departFirstLeg()
        // Jump straight into descent — cart stays stowed even though the
        // clock is past the usual first-service time.
        clock.advance(by: session.phaseSchedule.descentStart + 1)
        session.tick()
        XCTAssertEqual(session.phase, .descent)
        XCTAssertNil(session.beverageCartUntil)
    }

    func testNoBeverageOnShortStudyHops() {
        // Under the 45-minute minimum — hydration nudge is for long flights.
        let session = makeSession(duration: 40 * 60)
        session.departFirstLeg()
        clock.advance(by: session.phaseSchedule.climbEnd + FlightSession.beverageFirstDelay)
        session.tick()
        XCTAssertNil(session.beverageCartUntil)
    }

    func testBeverageServiceRespectsCabinServiceSetting() {
        SettingsStore.shared.cabinServiceEnabled = false
        defer { SettingsStore.shared.cabinServiceEnabled = true }

        let session = makeSession(duration: 3600)
        session.departFirstLeg()
        clock.advance(by: session.phaseSchedule.climbEnd + FlightSession.beverageFirstDelay)
        session.tick()
        XCTAssertNil(session.beverageCartUntil)
    }

    private func makeSession(duration: TimeInterval) -> FlightSession {
        let origin = Airport.byCode("BOS")
        let destination = Airport.byCode("JFK")
        let leg = FlightLeg(
            origin: origin,
            destination: destination,
            duration: duration,
            flightNumber: "VOY 214"
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
                FlightLeg(origin: bos, destination: yyz, duration: leg1, flightNumber: "VOY 101"),
                FlightLeg(origin: yyz, destination: yqr, duration: leg2, flightNumber: "VOY 102"),
            ],
            layoverDuration: layover
        )
        return FlightSession(itinerary: itinerary, modelContext: context, tier: .gold, clock: clock)
    }
}
