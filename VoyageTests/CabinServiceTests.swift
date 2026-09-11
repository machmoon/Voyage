import XCTest
import SwiftData
@testable import Voyage

/// The wellness cues, and above all the cases where they stay quiet.
///
/// The suppression tests are the point of this file. A cue that fires during
/// descent, or during a QA capture, or after the traveller has switched it
/// off, is worse than no feature at all.
@MainActor
final class CabinServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var clock: ManualClock!

    /// A leg long enough to hold several 20 minute passes.
    private let longLeg: TimeInterval = 7200
    /// A leg sized so pass 1 lands 30 seconds before descent begins, which is
    /// the only way to exercise a cue that is still on screen at the handover.
    private let tightLeg: TimeInterval = 2376

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: LogbookEntry.self, configurations: config)
        context = ModelContext(container)
        clock = ManualClock(now: Date(timeIntervalSince1970: 1_700_000_000))
        SettingsStore.shared.ambienceEnabled = false
        SettingsStore.shared.announcementsEnabled = false
        SettingsStore.shared.cabinServiceEnabled = true
    }

    override func tearDown() async throws {
        SettingsStore.shared.cabinServiceEnabled = true
        container = nil
        context = nil
        clock = nil
    }

    // MARK: Cadence

    /// stretchly's `breakNumber % (breakInterval + 1) === 0`, with their
    /// interval of 3 replaced by 2 so the long cue lands on the hour.
    func testEveryThirdPassIsTheStretch() {
        let kinds = (1...7).map { CabinServicePlanner.kind(forPass: $0) }
        XCTAssertEqual(kinds, [.eyeRest, .eyeRest, .stretch,
                               .eyeRest, .eyeRest, .stretch,
                               .eyeRest])
    }

    func testPassZeroIsNeverAStretch() {
        XCTAssertEqual(CabinServicePlanner.kind(forPass: 0), .eyeRest)
    }

    /// The eye-rest spacing is the 20 in 20-20-20, and the stretch lands on
    /// the hour. If either number drifts, the clinical claim in the copy and
    /// the settings footer stops being true.
    func testCadenceMatchesTheStatedGuidance() {
        XCTAssertEqual(CabinServicePlanner.passInterval, 20 * 60)
        XCTAssertEqual(CabinServicePlanner.eyeRestSeconds, 20)
        let stretchAt = CabinServicePlanner.due(pass: 3, cruiseBeginsAt: 0)
        XCTAssertEqual(stretchAt, 3600, "The stretch cue should land one hour into cruise")
    }

    func testIgnoredIsOfferedMinusTaken() {
        var planner = CabinServicePlanner()
        _ = planner.offer()
        _ = planner.offer()
        _ = planner.offer()
        planner.acknowledge()
        XCTAssertEqual(planner.passNumber, 3)
        XCTAssertEqual(planner.taken, 1)
        XCTAssertEqual(planner.ignored, 2)
    }

    func testAcknowledgeCannotExceedWhatWasOffered() {
        var planner = CabinServicePlanner()
        _ = planner.offer()
        planner.acknowledge()
        planner.acknowledge()
        XCTAssertEqual(planner.taken, 1)
        XCTAssertEqual(planner.ignored, 0)
    }

    // MARK: Suppression

    func testSuppressionRules() {
        XCTAssertTrue(FlightSession.cabinServiceActive(enabled: true, shortFlights: false))
        XCTAssertFalse(FlightSession.cabinServiceActive(enabled: false, shortFlights: false),
                       "The setting must win")
        XCTAssertFalse(FlightSession.cabinServiceActive(enabled: true, shortFlights: true),
                       "Short flights are QA and demo captures and must never be interrupted")
        XCTAssertFalse(FlightSession.cabinServiceActive(enabled: false, shortFlights: true))
    }

    /// The capture flag lifts the short-flight suppression, and nothing else.
    /// It must never override the traveller's setting.
    func testTheCaptureFlagCannotOverrideTheSetting() {
        XCTAssertTrue(FlightSession.cabinServiceActive(enabled: true, shortFlights: true, demo: true),
                      "The capture flag exists precisely to show a cue on a short flight")
        XCTAssertFalse(FlightSession.cabinServiceActive(enabled: false, shortFlights: true, demo: true),
                       "Off is off, even for a screenshot")
        XCTAssertFalse(FlightSession.cabinServiceActive(enabled: false, shortFlights: false, demo: true))
    }

    /// The compressed cadence is a capture flag, so a normal run must be on
    /// the real 20 minute interval.
    func testTheShippedCadenceIsTheRealOne() {
        XCTAssertFalse(FlightSession.cabinServiceDemoEnabled,
                       "Unit tests must not be running with the capture flag")
        XCTAssertEqual(FlightSession.servicePassInterval, CabinServicePlanner.passInterval)
    }

    func testNoCueWhenTheSettingIsOff() {
        SettingsStore.shared.cabinServiceEnabled = false
        let session = makeSession(duration: longLeg)
        session.departFirstLeg()

        advance(session, to: session.cruiseBeginsAt + CabinServicePlanner.passInterval + 5)
        XCTAssertNil(session.serviceCue)
        XCTAssertEqual(session.serviceCuesOffered, 0)
    }

    func testNoCueDuringClimb() {
        let session = makeSession(duration: longLeg)
        session.departFirstLeg()

        advance(session, to: session.cruiseBeginsAt - 1)
        XCTAssertEqual(session.phase, .climb)
        XCTAssertNil(session.serviceCue)
        XCTAssertEqual(session.serviceCuesOffered, 0)
    }

    /// The first cue is 20 minutes into cruise, not 20 minutes into the flight.
    func testFirstCueWaitsTwentyMinutesIntoCruise() {
        let session = makeSession(duration: longLeg)
        session.departFirstLeg()

        advance(session, to: session.cruiseBeginsAt + CabinServicePlanner.passInterval - 1)
        XCTAssertNil(session.serviceCue, "Not due yet")

        advance(session, to: session.cruiseBeginsAt + CabinServicePlanner.passInterval + 1)
        XCTAssertEqual(session.serviceCue?.pass, .eyeRest)
        XCTAssertEqual(session.serviceCuesOffered, 1)
    }

    func testNeverInterruptsDescentOrLanding() {
        let session = makeSession(duration: tightLeg)
        session.departFirstLeg()

        // Straight past the moment pass 1 was due, into descent.
        advance(session, to: session.phaseSchedule.descentStart + 20)
        XCTAssertEqual(session.phase, .descent)
        XCTAssertNil(session.serviceCue)
        XCTAssertEqual(session.serviceCuesOffered, 0, "A missed cue is skipped, never deferred into descent")

        advance(session, to: session.phaseSchedule.landingStart + 1)
        XCTAssertEqual(session.phase, .landing)
        XCTAssertNil(session.serviceCue)
        XCTAssertEqual(session.serviceCuesOffered, 0)
    }

    /// A cue raised in the last seconds of cruise must not still be sitting
    /// there once the aircraft is descending, even though its 90 second
    /// lifetime has not run out.
    func testCueOnScreenIsClearedWhenDescentBegins() {
        let session = makeSession(duration: tightLeg)
        session.departFirstLeg()

        let dueAt = session.cruiseBeginsAt + CabinServicePlanner.passInterval
        advance(session, to: dueAt + 1)
        XCTAssertNotNil(session.serviceCue, "Precondition: a cue is up during cruise")
        XCTAssertLessThan(dueAt + 1, session.phaseSchedule.descentStart)

        advance(session, to: session.phaseSchedule.descentStart + 5)
        XCTAssertEqual(session.phase, .descent)
        XCTAssertNil(session.serviceCue, "The card must not survive into descent")
    }

    // MARK: Ignoring costs nothing

    func testAnIgnoredCueExpiresOnItsOwnAndIsCounted() {
        let session = makeSession(duration: longLeg)
        session.departFirstLeg()

        let dueAt = session.cruiseBeginsAt + CabinServicePlanner.passInterval
        advance(session, to: dueAt + 1)
        XCTAssertNotNil(session.serviceCue)

        advance(session, to: dueAt + CabinServicePlanner.cueDuration + 1)
        XCTAssertNil(session.serviceCue, "It goes away by itself")
        XCTAssertEqual(session.serviceCuesOffered, 1)
        XCTAssertEqual(session.serviceCuesIgnored, 1)
    }

    func testAcknowledgingCountsAsTaken() {
        let session = makeSession(duration: longLeg)
        session.departFirstLeg()

        advance(session, to: session.cruiseBeginsAt + CabinServicePlanner.passInterval + 1)
        session.acknowledgeServiceCue()
        XCTAssertNil(session.serviceCue)
        XCTAssertEqual(session.serviceCuesIgnored, 0)
    }

    func testDismissingIsTheSameAsIgnoring() {
        let session = makeSession(duration: longLeg)
        session.departFirstLeg()

        advance(session, to: session.cruiseBeginsAt + CabinServicePlanner.passInterval + 1)
        session.dismissServiceCue()
        XCTAssertNil(session.serviceCue)
        XCTAssertEqual(session.serviceCuesIgnored, 1)
    }

    /// The load-bearing promise: a traveller who ignores every cue has done
    /// nothing wrong. The flight lands, the miles are the same, the logbook
    /// records an arrival.
    func testIgnoringEveryCueDoesNotAffectTheOutcome() throws {
        let session = makeSession(duration: longLeg)
        session.departFirstLeg()

        // Fly the whole leg in 5 minute steps, never touching a cue.
        var t: TimeInterval = 0
        while t < longLeg {
            t = min(longLeg, t + 300)
            advance(session, to: t)
        }

        XCTAssertEqual(session.stage, .arrived)
        XCTAssertGreaterThan(session.serviceCuesIgnored, 0, "Precondition: cues were in fact ignored")
        let entry = try XCTUnwrap(session.logEntry)
        XCTAssertEqual(entry.outcome, .arrived)
        XCTAssertEqual(entry.miles, session.itinerary.legs[0].distanceMiles, accuracy: 0.001)
    }

    // MARK: Leg boundary and layover

    func testTheLayoverResetsTheCadence() {
        let session = makeConnectionSession(leg1: longLeg, layover: 600, leg2: longLeg)
        session.departFirstLeg()

        advance(session, to: session.cruiseBeginsAt + CabinServicePlanner.passInterval + 1)
        XCTAssertEqual(session.serviceCuesOffered, 1, "Precondition: a cue was offered on leg 1")

        // Finish leg 1 and enter the lounge.
        advance(session, to: longLeg)
        XCTAssertEqual(session.stage, .layover)

        session.boardConnection()
        XCTAssertEqual(session.stage, .inFlight)
        XCTAssertEqual(session.serviceCuesOffered, 0, "The lounge is itself the break")
        XCTAssertEqual(session.serviceCuesIgnored, 0)
        XCTAssertNil(session.serviceCue)
    }

    func testCueDoesNotSurviveIntoTheLounge() {
        let session = makeConnectionSession(leg1: tightLeg, layover: 600, leg2: tightLeg)
        session.departFirstLeg()

        advance(session, to: session.cruiseBeginsAt + CabinServicePlanner.passInterval + 1)
        XCTAssertNotNil(session.serviceCue)

        advance(session, to: tightLeg)
        XCTAssertEqual(session.stage, .layover)
        XCTAssertNil(session.serviceCue)
    }

    /// Leg 2 runs the cadence from its own cruise, not from the start of the
    /// itinerary.
    func testSecondLegOffersItsOwnFirstCue() {
        let session = makeConnectionSession(leg1: longLeg, layover: 600, leg2: longLeg)
        session.departFirstLeg()
        advance(session, to: longLeg)
        session.boardConnection()

        let legStart = try! XCTUnwrap(session.legStartDate)
        clock.set(legStart.addingTimeInterval(session.cruiseBeginsAt + CabinServicePlanner.passInterval - 1))
        session.tick()
        XCTAssertNil(session.serviceCue)

        clock.set(legStart.addingTimeInterval(session.cruiseBeginsAt + CabinServicePlanner.passInterval + 1))
        session.tick()
        XCTAssertEqual(session.serviceCue?.pass, .eyeRest, "Leg 2 starts the cadence over")
        XCTAssertEqual(session.serviceCuesOffered, 1)
    }

    // MARK: Copy

    /// Same mechanical voice check the recorder tests use.
    func testCopyKeepsTheVoice() {
        let passes: [CabinServicePlanner.Pass] = [.eyeRest, .stretch]
        let strings = passes.flatMap { [$0.eyebrow, $0.headline, $0.detail, $0.action] }

        for s in strings {
            XCTAssertFalse(s.contains("!"), "No exclamation marks: \(s)")
            XCTAssertFalse(s.contains("—"), "No em-dashes: \(s)")
            XCTAssertFalse(s.contains(" - "), "No dash-as-pause: \(s)")
        }

        // Scolding, nagging, and gamified verbs. The July copy pass on this
        // repo removed "Stay hydrated / You've been flying a while" for
        // exactly these reasons.
        let banned = ["should", "need to", "don't forget", "remember to", "make sure",
                      "streak", "score", "points", "earn", "reward", "unlock",
                      "keep it up", "well done", "good job", "healthy", "unhealthy"]
        for s in strings {
            let lower = s.lowercased()
            for word in banned {
                XCTAssertFalse(lower.contains(word), "Banned phrase \"\(word)\" in: \(s)")
            }
        }
    }

    /// The detail text has to say out loud that ignoring it is free, because
    /// that is the promise the whole design rests on.
    func testTheStretchCueSaysIgnoringItIsFree() {
        let detail = CabinServicePlanner.Pass.stretch.detail.lowercased()
        XCTAssertTrue(detail.contains("nothing is logged"), detail)
    }

    func testTheTwoPassesDoNotShareCopy() {
        XCTAssertNotEqual(CabinServicePlanner.Pass.eyeRest.headline,
                          CabinServicePlanner.Pass.stretch.headline)
        XCTAssertNotEqual(CabinServicePlanner.Pass.eyeRest.eyebrow,
                          CabinServicePlanner.Pass.stretch.eyebrow)
    }

    // MARK: Helpers

    /// Steps the clock to `elapsed` seconds into the current leg and ticks.
    private func advance(_ session: FlightSession, to elapsed: TimeInterval) {
        guard let start = session.legStartDate else { return XCTFail("Leg not started") }
        clock.set(start.addingTimeInterval(elapsed))
        session.tick()
    }

    private func makeSession(duration: TimeInterval) -> FlightSession {
        let leg = FlightLeg(
            origin: Airport.byCode("BOS"),
            destination: Airport.byCode("JFK"),
            duration: duration,
            flightNumber: "VOY 214"
        )
        return FlightSession(itinerary: Itinerary(legs: [leg], layoverDuration: 0),
                             modelContext: context, tier: .member, clock: clock)
    }

    private func makeConnectionSession(leg1: TimeInterval, layover: TimeInterval, leg2: TimeInterval) -> FlightSession {
        let itinerary = Itinerary(
            legs: [
                FlightLeg(origin: Airport.byCode("BOS"), destination: Airport.byCode("YYZ"),
                          duration: leg1, flightNumber: "VOY 101"),
                FlightLeg(origin: Airport.byCode("YYZ"), destination: Airport.byCode("YQR"),
                          duration: leg2, flightNumber: "VOY 102"),
            ],
            layoverDuration: layover
        )
        return FlightSession(itinerary: itinerary, modelContext: context, tier: .gold, clock: clock)
    }
}
