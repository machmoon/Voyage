import XCTest
import SwiftData
import CoreLocation
@testable import Voyage

@MainActor
final class OpenSkiesTests: XCTestCase {

    private let sfo = Airport.byCode("SFO")

    private func departureRunway(at airport: Airport) -> RunwayProfile {
        FlightVisualEngine.selectRunway(for: airport, routeCourseDegrees: 0,
                                        weather: nil, aircraft: .boeing737800)
    }

    private func makeFlight(visited: Set<String> = []) -> OpenSkiesFlight {
        OpenSkiesFlight(origin: sfo, departureRunway: departureRunway(at: sfo),
                        aircraft: .boeing737800, visitedCodes: visited)
    }

    private func meters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    // MARK: Path from a heading

    func testPathCoversSpeedTimesTimeAlongItsHeading() {
        var path = SteeredPath(start: sfo.coordinate, courseDegrees: 90)
        path.advance(to: 60, targetBank: { _ in 0 }, speed: { _ in 100 })

        XCTAssertEqual(path.samples.count, 61)
        // The first step averages 0 and 100 m/s; every step after flies 100 m.
        XCTAssertEqual(path.last.distanceMeters, 5_950, accuracy: 0.001)
        XCTAssertEqual(meters(sfo.coordinate, path.last.coordinate), 5_950, accuracy: 15)
        XCTAssertEqual(path.last.courseDegrees, 90, accuracy: 0.000_1)
        XCTAssertEqual(GreatCircle.bearing(from: sfo.coordinate, to: path.last.coordinate), 90, accuracy: 0.1)
    }

    func testBankAndTurnRateNeverExceedTheirLimits() {
        let speed = 120.0
        var path = SteeredPath(start: sfo.coordinate, courseDegrees: 0)
        path.advance(to: 1, targetBank: { _ in 0 }, speed: { _ in speed })
        path.advance(to: 120, targetBank: { _ in 90 }, speed: { _ in speed })

        let maxTurn = SteeredPath.turnRateDegreesPerSecond(bankDegrees: SteeredPath.maximumBankDegrees,
                                                           speed: speed)
        // The coordinated-turn formula itself: g·tan(25°)/120 m/s ≈ 2.1°/s.
        XCTAssertEqual(maxTurn, 9.806_65 * tan(25 * .pi / 180) / speed * 180 / .pi, accuracy: 1e-9)
        for (a, b) in zip(path.samples, path.samples.dropFirst()) {
            XCTAssertLessThanOrEqual(abs(b.bankDegrees), SteeredPath.maximumBankDegrees + 1e-9)
            XCTAssertLessThanOrEqual(abs(b.bankDegrees - a.bankDegrees),
                                     SteeredPath.rollRateDegreesPerSecond + 1e-9)
            let turn = abs(SteeredPath.shortestAngle(from: a.courseDegrees, to: b.courseDegrees))
            XCTAssertLessThanOrEqual(turn, maxTurn + 1e-9)
        }
        // It does reach the limit and turn at it, not merely stay under.
        XCTAssertEqual(path.last.bankDegrees, SteeredPath.maximumBankDegrees, accuracy: 1e-9)
    }

    func testPathIsDeterministic() {
        func fly() -> [SteeredPath.Sample] {
            var flight = makeFlight()
            _ = flight.advance(to: 300)
            XCTAssertTrue(flight.takeControl(at: 300))
            flight.steer(bankDegrees: 15)
            _ = flight.advance(to: 420)
            flight.releaseControl()
            _ = flight.advance(to: OpenSkiesFlight.duration)
            return flight.path.samples
        }
        XCTAssertEqual(fly(), fly())
    }

    // MARK: The app's rate

    func testTwentyFiveMinutesFliesTheAppsMilesPerMinute() {
        // SFO to LAX: 337 miles in 1h 25m.
        XCTAssertEqual(OpenSkiesFlight.milesPerFocusMinute, 337.0 / 85, accuracy: 0.05)
        XCTAssertEqual(OpenSkiesFlight.creditedMiles, OpenSkiesFlight.milesPerFocusMinute * 25, accuracy: 1e-9)

        var flight = makeFlight()
        _ = flight.advance(to: OpenSkiesFlight.duration)
        let flownMiles = flight.path.last.distanceMeters / 1_609.344
        // The approach stretches or squeezes its last 90 seconds to make the
        // runway, so the total is near the rate rather than exactly on it.
        XCTAssertEqual(flownMiles, OpenSkiesFlight.creditedMiles, accuracy: OpenSkiesFlight.creditedMiles * 0.08)

        // A cruise minute flies the cruise speed, and that speed is a calm
        // airliner's (roughly 175 to 310 kt), not a rocket or a glider.
        let minute = flight.path.sample(at: 660).distanceMeters - flight.path.sample(at: 600).distanceMeters
        XCTAssertEqual(minute, flight.cruiseSpeed * 60, accuracy: 0.5)
        XCTAssertGreaterThan(flight.cruiseSpeed, 90)
        XCTAssertLessThan(flight.cruiseSpeed, 160)
    }

    // MARK: Landing choice

    private func field(_ code: String, _ latitude: Double, _ longitude: Double) -> OpenSkiesField {
        OpenSkiesField(airport: Airport(code: code, city: code, name: code,
                                        latitude: latitude, longitude: longitude, accentHex: "FFFFFF"),
                       runways: [])
    }

    func testLandingChoosesTheNearestReachableFieldThatIsNotHome() {
        let home = field("AAA", 0, 0)
        let near = field("BBB", 0, 0.1)    // ~11 km east
        let far = field("CCC", 0, 0.3)     // ~33 km east
        let fields = [far, home, near]

        // Home is closer, but another field is within reach: never home.
        let overHome = CLLocationCoordinate2D(latitude: 0, longitude: 0.02)
        XCTAssertEqual(OpenSkiesFlight.landingField(from: overHome, origin: home.airport,
                                                    fields: fields, reachMeters: 20_000)?.code, "BBB")

        // Only home within reach: home, rather than an unreachable runway.
        XCTAssertEqual(OpenSkiesFlight.landingField(from: overHome, origin: home.airport,
                                                    fields: fields, reachMeters: 5_000)?.code, "AAA")

        // Between two fields the nearer one wins, even with both in reach.
        let between = CLLocationCoordinate2D(latitude: 0, longitude: 0.22)
        XCTAssertEqual(OpenSkiesFlight.landingField(from: between, origin: home.airport,
                                                    fields: fields, reachMeters: 50_000)?.code, "CCC")

        // Nothing within reach at all: still lands, at the nearest that is not home.
        let farAway = CLLocationCoordinate2D(latitude: 0, longitude: 2)
        XCTAssertEqual(OpenSkiesFlight.landingField(from: farAway, origin: home.airport,
                                                    fields: fields, reachMeters: 20_000)?.code, "CCC")
    }

    func testAutopilotHeadsForAFieldNotYetVisited() throws {
        let first = try XCTUnwrap(makeFlight().target)
        XCTAssertNotEqual(first.code, "SFO")
        let next = try XCTUnwrap(makeFlight(visited: [first.code]).target)
        XCTAssertNotEqual(next.code, first.code)
    }

    // MARK: Timeline

    func testScheduleReclaimsAtTwentyThreeMinutesAndLandsAtTwentyFive() {
        let schedule = FlightPhaseSchedule.openSkies(aircraft: .boeing737800)
        XCTAssertEqual(schedule.legEnd, 25 * 60)
        XCTAssertEqual(schedule.descentStart, 23 * 60)
        XCTAssertEqual(schedule.landingStart, 25 * 60 - 30)

        // The demo flight plays the same timeline, scaled.
        let demo = FlightPhaseSchedule.openSkies(aircraft: .boeing737800, legDuration: 60)
        XCTAssertEqual(demo.descentStart / demo.legEnd, schedule.descentStart / schedule.legEnd, accuracy: 1e-9)
    }

    func testAutopilotTakesTheAirplaneBackAtTwentyThreeMinutes() {
        var flight = makeFlight()
        _ = flight.advance(to: 20)
        XCTAssertFalse(flight.takeControl(at: 20), "still on the runway")

        _ = flight.advance(to: 120)
        XCTAssertTrue(flight.takeControl(at: 120))
        flight.steer(bankDegrees: 10)
        let beforeReclaim = flight.advance(to: 23 * 60 - 1)
        XCTAssertEqual(flight.control, .pilot)
        XCTAssertTrue(beforeReclaim.isEmpty)

        let atReclaim = flight.advance(to: 23 * 60 + 1)
        XCTAssertEqual(flight.control, .approach)
        guard case .clearedToLand(let field)? = atReclaim.first else {
            return XCTFail("expected a landing clearance at 23:00, got \(atReclaim)")
        }
        XCTAssertEqual(flight.landing?.field, field)
        XCTAssertFalse(flight.takeControl(at: 23 * 60 + 5), "cleared to land: not the traveller's to take")
        flight.steer(bankDegrees: -25)
        XCTAssertEqual(flight.pilotBank, 0)
    }

    func testApproachCrossesTheThresholdExactlyWhenTheRolloutBegins() throws {
        // Fly by hand somewhere awkward, so the clearance has work to do.
        var flight = makeFlight()
        _ = flight.advance(to: 120)
        XCTAssertTrue(flight.takeControl(at: 120))
        flight.steer(bankDegrees: -18)
        _ = flight.advance(to: OpenSkiesFlight.duration)

        let landing = try XCTUnwrap(flight.landing)
        let touchdown = flight.path.sample(at: flight.schedule.landingStart)
        let threshold = landing.runway.threshold
        XCTAssertLessThan(meters(touchdown.coordinate, threshold.coordinate), 1,
                          "on the threshold at 24:30")
        XCTAssertEqual(flight.path.last.speedMetersPerSecond, 0, accuracy: 1e-9, "stopped at 25:00")
        XCTAssertLessThan(meters(flight.path.sample(at: OpenSkiesFlight.duration).coordinate,
                                 landing.field.coordinate), 5_000, "and still at the airport")
    }

    func testLettingGoForTenSecondsEngagesTheAutopilot() {
        var flight = makeFlight()
        _ = flight.advance(to: 300)
        XCTAssertTrue(flight.takeControl(at: 300))
        flight.steer(bankDegrees: 0)
        XCTAssertTrue(flight.advance(to: 309).isEmpty)
        XCTAssertEqual(flight.control, .pilot)
        XCTAssertEqual(flight.advance(to: 311), [.autopilotEngaged])
        XCTAssertEqual(flight.control, .autopilot)
    }

    func testTiltDeadBandMatchesDoom() {
        XCTAssertEqual(TiltSteering.deadBandAdjust(0.05, deadBand: 0.08), 0)
        XCTAssertEqual(TiltSteering.deadBandAdjust(0.08, deadBand: 0.08), 0, accuracy: 1e-12)
        XCTAssertEqual(TiltSteering.deadBandAdjust(0.54, deadBand: 0.08), 0.5, accuracy: 1e-12)
        XCTAssertEqual(TiltSteering.deadBandAdjust(-2, deadBand: 0.08), -1)
    }
}

/// The whole flight through `FlightSession`, on the injected clock.
@MainActor
final class OpenSkiesSessionTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var clock: ManualClock!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: LogbookEntry.self, configurations: config)
        context = ModelContext(container)
        clock = ManualClock(now: Date(timeIntervalSince1970: 1_700_000_000))
        SettingsStore.shared.ambienceEnabled = false
        SettingsStore.shared.soundEffectsEnabled = false
        SettingsStore.shared.announcementsEnabled = false
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        clock = nil
    }

    private func makeSession() -> FlightSession {
        FlightSession.openSkies(from: Airport.byCode("SFO"), visitedCodes: [],
                                modelContext: context, tier: .silver, clock: clock)
    }

    private func fly(_ session: FlightSession, to elapsed: TimeInterval) {
        let start = session.legStartDate!
        var t = session.legElapsed
        while t < elapsed {
            t = min(elapsed, t + 1)
            clock.set(start.addingTimeInterval(t))
            session.tick()
        }
    }

    func testLandsWhereverItEndedUpExactlyAtTwentyFiveMinutes() throws {
        let session = makeSession()
        session.autoAssignSeat()
        session.departFirstLeg()
        XCTAssertEqual(session.countdownDestinationLine, "Open skies")
        XCTAssertEqual(session.itinerary.destination.code, "—")

        fly(session, to: 10 * 60)
        XCTAssertTrue(session.canTakeOpenSkiesControl)
        session.toggleOpenSkiesControl()
        XCTAssertEqual(session.openSkies?.control, .pilot)
        XCTAssertEqual(session.openSkiesNotice?.text, "You have control.")
        session.steerOpenSkies(bankDegrees: 12)

        fly(session, to: 23 * 60 + 2)
        XCTAssertEqual(session.openSkies?.control, .approach)
        let field = try XCTUnwrap(session.openSkies?.landing?.field)
        XCTAssertNotEqual(field.code, "SFO")
        XCTAssertEqual(session.itinerary.destination, field.airport)
        XCTAssertEqual(session.countdownDestinationLine, "to \(field.airport.city)")
        XCTAssertEqual(session.openSkiesNotice?.text, "ATC: cleared to land at \(field.airport.city).")

        // The approach is one segment that crosses the threshold at 24:30
        // and rolls out to a stop at 25:00.
        let approach = try XCTUnwrap(session.openSkies?.landing?.approach)
        XCTAssertEqual(approach.startTime, 23 * 60, accuracy: 1)
        XCTAssertEqual(approach.endTime, 25 * 60 - 30)
        XCTAssertEqual(approach.end, session.openSkies?.landing?.runway.threshold)

        fly(session, to: 25 * 60 - 1)
        XCTAssertEqual(session.stage, .inFlight)
        fly(session, to: 25 * 60 + 0.5)
        XCTAssertEqual(session.stage, .arrived)

        // Down at its runway, and logged as flown.
        let finalPosition = session.currentCoordinate
        let runway = try XCTUnwrap(session.openSkies?.landing?.runway)
        XCTAssertLessThan(CLLocation(latitude: finalPosition.latitude, longitude: finalPosition.longitude)
            .distance(from: CLLocation(latitude: runway.threshold.latitude,
                                       longitude: runway.threshold.longitude)), 3_000,
            "touched down at the threshold and rolled out along the runway")
        let entry = try XCTUnwrap(session.logEntry)
        XCTAssertTrue(entry.isOpenSkies)
        XCTAssertEqual(entry.originCode, "SFO")
        XCTAssertEqual(entry.destinationCode, field.code)
        XCTAssertEqual(entry.miles, OpenSkiesFlight.creditedMiles, accuracy: 0.001)
        XCTAssertEqual(entry.focusSeconds, 25 * 60)
        XCTAssertEqual(Airport.byCode(entry.destinationCode), field.airport)
        let track = try XCTUnwrap(entry.trajectoryLegSamples.first)
        XCTAssertGreaterThan(track.count, 100)
        XCTAssertLessThan(CLLocation(latitude: track.last!.latitude, longitude: track.last!.longitude)
            .distance(from: field.location), 15_000, "the replay validator's endpoint tolerance")
    }

    func testStoppingEarlyFollowsTheDiversionRules() throws {
        let session = makeSession()
        session.departFirstLeg()
        fly(session, to: 8 * 60)
        session.abandonFlight()

        XCTAssertEqual(session.stage, .diverted)
        let entry = try XCTUnwrap(session.logEntry)
        XCTAssertTrue(entry.isOpenSkies)
        XCTAssertFalse(entry.completed)
        XCTAssertEqual(entry.miles, 0, "a single leg that did not land earns no miles")
        XCTAssertEqual(entry.focusSeconds, 8 * 60, accuracy: 1)
        XCTAssertNotEqual(entry.destinationCode, "—")
        XCTAssertNotEqual(entry.destinationCode, "SFO")
        XCTAssertNotNil(Airport.find(entry.destinationCode))
    }
}
