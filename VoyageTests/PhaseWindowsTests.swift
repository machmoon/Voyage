import XCTest
import SwiftData
@testable import Voyage

/// The contract for `FlightSession.phaseWindows(duration:)`.
///
/// The invariant every case here checks is
/// `0 < takeoffEnd < climbEnd < descentStart < landingStart < duration`,
/// strictly. Non-strict is not good enough: two boundaries landing on the same
/// instant deletes the window between them, and a leg that renders climb for
/// its entire length is what that failure looks like on screen.
final class PhaseWindowsTests: XCTestCase {

    private func assertOrdered(_ duration: TimeInterval,
                               file: StaticString = #filePath,
                               line: UInt = #line) {
        let w = FlightSession.phaseWindows(duration: duration)
        let label = "duration \(duration): \(w)"
        XCTAssertGreaterThan(w.takeoffEnd, 0, label, file: file, line: line)
        XCTAssertGreaterThan(w.climbEnd, w.takeoffEnd, label, file: file, line: line)
        XCTAssertGreaterThan(w.descentStart, w.climbEnd, label, file: file, line: line)
        XCTAssertGreaterThan(w.landingStart, w.descentStart, label, file: file, line: line)
        XCTAssertGreaterThan(duration, w.landingStart, label, file: file, line: line)
    }

    // MARK: The invariant

    func testShortLegsKeepEveryPhaseWindowOpen() {
        // 60 s is the `-VoyageDemoFlight` clamp, the length a marketing capture
        // and the arrival screenshot tour actually fly.
        for duration in [1.0, 2.0, 5.0, 10.0, 30.0, 45.0, 60.0, 90.0, 120.0] {
            assertOrdered(duration)
        }
    }

    func testOrdinaryLegsKeepEveryPhaseWindowOpen() {
        for duration in stride(from: 150.0, through: 8 * 3600, by: 137.0) {
            assertOrdered(duration)
        }
    }

    func testEveryRealRouteLegKeepsEveryPhaseWindowOpen() {
        for origin in Airport.all {
            for destination in Airport.all where destination != origin {
                for leg in RoutePlanner.itinerary(from: origin, to: destination).legs {
                    assertOrdered(leg.duration)
                }
            }
        }
    }

    // MARK: Real flights are untouched

    func testARealBlockTimeGetsTheUnscaledConstants() {
        // BOS–SFO, 405 minutes. Comfortably long enough that the constants fit,
        // so the schedule must be exactly the constants and nothing else.
        let duration = 405.0 * 60
        let w = FlightSession.phaseWindows(duration: duration)
        XCTAssertEqual(w.takeoffEnd, FlightSession.takeoffRollDuration, accuracy: 1e-9)
        XCTAssertEqual(w.climbEnd, FlightSession.climbEndsAt, accuracy: 1e-9)
        XCTAssertEqual(w.descentStart, duration - FlightSession.descentDuration, accuracy: 1e-9)
        XCTAssertEqual(w.landingStart, duration - FlightSession.landingDuration, accuracy: 1e-9)
    }

    func testTheShortestRealRouteStillGetsTheUnscaledConstants() {
        // BOS–JFK, 80 minutes, the shortest leg in the catalog. If scaling ever
        // reached a shipped route this is the one it would reach first.
        let duration = 80.0 * 60
        let w = FlightSession.phaseWindows(duration: duration)
        XCTAssertEqual(w.climbEnd, FlightSession.climbEndsAt, accuracy: 1e-9)
        XCTAssertEqual(w.landingStart, duration - FlightSession.landingDuration, accuracy: 1e-9)
    }

    // MARK: Proportions

    func testCruiseKeepsAMeaningfulShareOfEveryLeg() {
        for duration in [1.0, 30.0, 60.0, 300.0, 3600.0] {
            let w = FlightSession.phaseWindows(duration: duration)
            let cruise = w.descentStart - w.climbEnd
            XCTAssertGreaterThanOrEqual(cruise / duration, 0.11,
                                        "duration \(duration) leaves only \(cruise)s of cruise")
        }
    }

    func testZeroDurationIsHandledWithoutAnInvertedSchedule() {
        let w = FlightSession.phaseWindows(duration: 0)
        XCTAssertLessThanOrEqual(w.takeoffEnd, w.climbEnd)
        XCTAssertLessThanOrEqual(w.climbEnd, w.descentStart)
        XCTAssertLessThanOrEqual(w.descentStart, w.landingStart)
    }
}

/// The same contract observed through a running session, since the windows only
/// matter if `phase` actually visits all five values. Driven by `ManualClock`,
/// so no real time passes.
@MainActor
final class ShortLegPhaseProgressionTests: XCTestCase {

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
                            flightNumber: "VOY 100")
        let itinerary = Itinerary(legs: [leg], layoverDuration: 0)
        return FlightSession(itinerary: itinerary,
                             modelContext: context,
                             tier: .member,
                             clock: clock)
    }

    /// A 60 s leg is what `-VoyageDemoFlight` flies. Every phase has to appear,
    /// or the demo recording is one long climb.
    func testASixtySecondLegVisitsEveryPhase() {
        let session = makeSession(duration: 60)
        session.departFirstLeg()

        var seen: [LegPhase] = []
        for step in stride(from: 0.0, through: 59.5, by: 0.25) {
            clock.set(session.legStartDate!.addingTimeInterval(step))
            session.tick()
            if seen.last != session.phase { seen.append(session.phase) }
        }

        XCTAssertEqual(seen, [.takeoffRoll, .climb, .cruise, .descent, .landing],
                       "a 60s leg must run the whole schedule, in order, once each")
    }

    func testATenSecondLegStillVisitsEveryPhase() {
        let session = makeSession(duration: 10)
        session.departFirstLeg()

        var seen: Set<LegPhase> = []
        for step in stride(from: 0.0, through: 9.9, by: 0.05) {
            clock.set(session.legStartDate!.addingTimeInterval(step))
            session.tick()
            seen.insert(session.phase)
        }
        XCTAssertEqual(seen.count, 5, "saw \(seen)")
    }
}
