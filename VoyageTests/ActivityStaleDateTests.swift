import XCTest
import SwiftUI
import SwiftData
@testable import Voyage

/// `FlightSession.activityStaleDate` is the whole Live Activity fix that can be
/// tested off-device: ActivityKit itself needs authorization and a real system,
/// but the date we hand it is pure arithmetic over the injected clock.
///
/// What it has to get right: once the app is suspended, nothing in this process
/// runs again, so the date shipped *before* suspension is the only thing that
/// can retire the lock-screen card on time.
@MainActor
final class ActivityStaleDateTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var clock: ManualClock!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: LogbookEntry.self, configurations: config)
        context = ModelContext(container)
        clock = ManualClock(now: Date(timeIntervalSince1970: 1_700_000_000))
        SettingsStore.shared.ambienceEnabled = false
        SettingsStore.shared.announcementsEnabled = false
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        clock = nil
    }

    private func makeSession(duration: TimeInterval) -> FlightSession {
        let leg = FlightLeg(origin: Airport.byCode("BOS"),
                            destination: Airport.byCode("JFK"),
                            duration: duration,
                            flightNumber: "VOY 214")
        let itinerary = Itinerary(legs: [leg], layoverDuration: 0)
        return FlightSession(itinerary: itinerary,
                             modelContext: context,
                             tier: .member,
                             clock: clock)
    }

    func testNoStaleDateBeforeDeparture() {
        XCTAssertNil(makeSession(duration: 3600).activityStaleDate)
    }

    func testInFlightGoesStaleAtArrival() {
        let session = makeSession(duration: 3600)
        session.departFirstLeg()
        clock.advance(by: 600)
        session.tick()

        XCTAssertEqual(session.activityStaleDate,
                       session.legStartDate!.addingTimeInterval(3600))
    }

    func testBackgroundingPullsTheStaleDateInToTheGraceDeadline() {
        let session = makeSession(duration: 3600)
        session.departFirstLeg()
        let arrival = session.legStartDate!.addingTimeInterval(3600)

        session.handleScenePhase(.background)

        // This is the defect in one assertion: a suspended process can never
        // run the divert, so the card has to expire at the grace deadline
        // rather than keep counting down to a landing that will not happen.
        XCTAssertEqual(session.activityStaleDate, session.graceDeadline)
        XCTAssertEqual(session.activityStaleDate,
                       clock.now.addingTimeInterval(FlightSession.graceDuration))
        XCTAssertLessThan(session.activityStaleDate!, arrival)
    }

    func testComingBackInsideTheGracePeriodPushesTheStaleDateBackOut() {
        let session = makeSession(duration: 3600)
        session.departFirstLeg()
        let arrival = session.legStartDate!.addingTimeInterval(3600)

        session.handleScenePhase(.background)
        clock.advance(by: FlightSession.graceDuration - 5)
        session.handleScenePhase(.active)

        XCTAssertEqual(session.stage, .inFlight, "still inside the grace period")
        XCTAssertNil(session.graceDeadline)
        XCTAssertEqual(session.activityStaleDate, arrival)
    }

    func testTheStaleDateNeverOutlivesArrivalOnAShortLeg() {
        // A leg with less than the grace period left: arrival is sooner than
        // the deadline, so arrival has to win.
        let session = makeSession(duration: 3600)
        session.departFirstLeg()
        clock.set(session.legStartDate!.addingTimeInterval(3600 - 10))
        session.tick()
        session.handleScenePhase(.background)

        XCTAssertEqual(session.activityStaleDate,
                       session.legStartDate!.addingTimeInterval(3600))
        XCTAssertLessThan(session.activityStaleDate!, session.graceDeadline!)
    }

    func testAnEndedSessionIsStaleImmediately() {
        let session = makeSession(duration: 3600)
        session.departFirstLeg()
        clock.advance(by: 120)
        session.tick()
        session.abandonFlight()

        XCTAssertEqual(session.stage, .diverted)
        XCTAssertEqual(session.activityStaleDate, session.now)
    }

    func testALayoverGoesStaleWhenTheBoardingWindowCloses() throws {
        let bos = Airport.byCode("BOS")
        let yyz = Airport.byCode("YYZ")
        let yqr = Airport.byCode("YQR")
        let itinerary = Itinerary(
            legs: [
                FlightLeg(origin: bos, destination: yyz, duration: 300, flightNumber: "VOY 1"),
                FlightLeg(origin: yyz, destination: yqr, duration: 300, flightNumber: "VOY 2")
            ],
            layoverDuration: 600
        )
        let session = FlightSession(itinerary: itinerary,
                                    modelContext: context,
                                    tier: .member,
                                    clock: clock)
        session.departFirstLeg()
        clock.advance(by: 300)
        session.tick()

        XCTAssertEqual(session.stage, .layover)
        let departs = try XCTUnwrap(session.connectionDeparts)
        XCTAssertEqual(session.activityStaleDate,
                       departs.addingTimeInterval(FlightSession.finalCallWindow))
    }
}
