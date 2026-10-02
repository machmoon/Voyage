import XCTest
import SwiftData
@testable import Voyage

/// A Screen Time stand-in: records what the flight asked for and reports the
/// shields as up exactly while they were raised and not lowered.
@MainActor
final class FakeAppBlocker: AppBlocking {
    var isSupported = true
    var authorization: AirplaneMode.Authorization = .approved
    var authorizationOutcome: AirplaneMode.AuthorizationFailure?
    var selectionCount = 3
    var restrictionsActive = false
    private(set) var activations = 0
    private(set) var deactivations = 0
    private(set) var safetyNets: [(flight: AirplaneModeFlight, now: Date)] = []
    private(set) var safetyNetStops = 0

    func requestAuthorization() async throws {
        if let authorizationOutcome { throw authorizationOutcome }
        authorization = .approved
    }

    func activateRestrictions() {
        activations += 1
        restrictionsActive = true
    }

    func deactivateRestrictions() {
        deactivations += 1
        restrictionsActive = false
    }

    func startSafetyNet(for flight: AirplaneModeFlight, now: Date) {
        safetyNets.append((flight, now))
    }

    func stopSafetyNet() {
        safetyNetStops += 1
    }
}

@MainActor
final class AirplaneModeTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var clock: ManualClock!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var blocker: FakeAppBlocker!
    private var airplaneMode: AirplaneMode!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: LogbookEntry.self, configurations: config)
        context = ModelContext(container)
        clock = ManualClock(now: Date(timeIntervalSince1970: 1_700_000_000))
        SettingsStore.shared.ambienceEnabled = false
        SettingsStore.shared.soundEffectsEnabled = false
        SettingsStore.shared.announcementsEnabled = false
        suiteName = "AirplaneModeTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        blocker = FakeAppBlocker()
        airplaneMode = AirplaneMode(blocker: blocker, defaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        airplaneMode = nil
        blocker = nil
        defaults = nil
        container = nil
        context = nil
        clock = nil
    }

    // MARK: Takeoff

    func testShieldsGoUpOnTakeoff() throws {
        let session = makeSession(duration: 600)
        XCTAssertFalse(blocker.restrictionsActive)
        session.departFirstLeg()

        XCTAssertEqual(blocker.activations, 1)
        XCTAssertTrue(airplaneMode.shieldsUp)
        let record = try XCTUnwrap(AirplaneModeFlightStore.load(from: defaults))
        XCTAssertEqual(record.destinationCode, "JFK")
        XCTAssertEqual(record.destinationCity, Airport.byCode("JFK").city)
        XCTAssertEqual(record.landsAt, clock.now.addingTimeInterval(600))
        XCTAssertEqual(record.safetyNetEndsAt,
                       clock.now.addingTimeInterval(600 + AirplaneModeSchedule.margin))
        XCTAssertEqual(blocker.safetyNets.count, 1)
        XCTAssertEqual(blocker.safetyNets.first?.flight, record)
    }

    func testNothingIsBlockedUntilSetUp() {
        let cases: [(String, (FakeAppBlocker, AirplaneMode) -> Void)] = [
            ("no apps chosen", { blocker, _ in blocker.selectionCount = 0 }),
            ("switched off", { _, mode in mode.isEnabled = false }),
            ("not authorized", { blocker, _ in blocker.authorization = .notDetermined }),
            ("denied", { blocker, _ in blocker.authorization = .denied }),
            ("no Screen Time in this build", { blocker, _ in blocker.isSupported = false }),
        ]
        for (name, configure) in cases {
            let blocker = FakeAppBlocker()
            let mode = AirplaneMode(blocker: blocker, defaults: defaults)
            configure(blocker, mode)
            let session = makeSession(duration: 600, airplaneMode: mode)
            session.departFirstLeg()
            XCTAssertEqual(blocker.activations, 0, name)
            XCTAssertTrue(blocker.safetyNets.isEmpty, name)
            XCTAssertNil(AirplaneModeFlightStore.load(from: defaults), name)
            mode.isEnabled = true
        }
    }

    // MARK: Layover

    func testShieldsHoldThroughALayoverAndFollowTheConnection() throws {
        let session = makeConnectionSession(leg1: 90, layover: 40, leg2: 100)
        session.departFirstLeg()
        let firstRecord = try XCTUnwrap(AirplaneModeFlightStore.load(from: defaults))
        XCTAssertEqual(firstRecord.destinationCode, "YYZ")

        clock.advance(by: 90)
        session.tick()
        XCTAssertEqual(session.stage, .layover)
        XCTAssertTrue(blocker.restrictionsActive, "shields stay up in the lounge")
        XCTAssertEqual(blocker.deactivations, 0)

        clock.advance(by: 10)
        session.boardConnection()
        XCTAssertEqual(session.stage, .inFlight)
        XCTAssertEqual(blocker.activations, 1, "a connection does not raise them again")
        XCTAssertEqual(blocker.safetyNets.count, 1, "nor re-arm the safety net")
        let connection = try XCTUnwrap(AirplaneModeFlightStore.load(from: defaults))
        XCTAssertEqual(connection.id, firstRecord.id)
        XCTAssertEqual(connection.destinationCode, "YQR")
        XCTAssertEqual(connection.landsAt, clock.now.addingTimeInterval(100))
        XCTAssertEqual(connection.safetyNetEndsAt, firstRecord.safetyNetEndsAt)

        clock.advance(by: 100)
        session.tick()
        XCTAssertEqual(session.stage, .arrived)
        XCTAssertFalse(blocker.restrictionsActive)
    }

    // MARK: Every way a flight ends

    func testShieldsComeDownOnArrival() {
        let session = makeSession(duration: 600)
        session.departFirstLeg()
        clock.advance(by: 600)
        session.tick()
        XCTAssertEqual(session.logEntry?.outcome, .arrived)
        assertShieldsDown()
    }

    func testShieldsComeDownWhenLeavingEarly() {
        let session = makeSession(duration: 600)
        session.departFirstLeg()
        clock.advance(by: 120)
        session.tick()
        session.abandonFlight()
        XCTAssertEqual(session.logEntry?.outcome, .leftEarly)
        assertShieldsDown()
    }

    func testShieldsComeDownWhenInterrupted() {
        let session = makeSession(duration: 600)
        session.departFirstLeg()
        clock.advance(by: 120)
        session.tick()
        session.handleScenePhase(.background)
        clock.advance(by: FlightSession.graceDuration + 1)
        session.tick()
        XCTAssertEqual(session.stage, .diverted)
        XCTAssertEqual(session.logEntry?.outcome, .interrupted)
        assertShieldsDown()
    }

    func testShieldsComeDownOnAMissedConnection() {
        let session = makeConnectionSession(leg1: 60, layover: 30, leg2: 60)
        session.departFirstLeg()
        clock.advance(by: 60)
        session.tick()
        XCTAssertTrue(blocker.restrictionsActive)
        clock.advance(by: 30 + FlightSession.finalCallWindow + 1)
        session.tick()
        XCTAssertEqual(session.stage, .missedConnection)
        XCTAssertEqual(session.logEntry?.outcome, .missedConnection)
        assertShieldsDown()
    }

    func testShieldsComeDownWhenOpenSkiesLands() throws {
        let session = FlightSession.openSkies(from: Airport.byCode("SFO"), visitedCodes: [],
                                              modelContext: context, tier: .silver, clock: clock,
                                              airplaneMode: airplaneMode)
        session.autoAssignSeat()
        session.departFirstLeg()
        XCTAssertTrue(blocker.restrictionsActive)
        let record = try XCTUnwrap(AirplaneModeFlightStore.load(from: defaults))
        XCTAssertNil(record.destinationCode, "Open skies has nowhere to be yet")
        XCTAssertNil(record.destinationCity)

        let start = try XCTUnwrap(session.legStartDate)
        var t: TimeInterval = 0
        while session.stage == .inFlight, t < OpenSkiesFlight.duration + 5 {
            t += 1
            clock.set(start.addingTimeInterval(t))
            session.tick()
        }
        XCTAssertEqual(session.stage, .arrived)
        assertShieldsDown()
    }

    func testCancellingAtTheGateNeverRaisesShields() {
        let session = makeSession(duration: 600)
        session.cancelBeforeDeparture()
        XCTAssertEqual(blocker.activations, 0)
        XCTAssertFalse(blocker.restrictionsActive)
    }

    private func assertShieldsDown(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(blocker.restrictionsActive, file: file, line: line)
        XCTAssertEqual(blocker.deactivations, 1, file: file, line: line)
        XCTAssertEqual(blocker.safetyNetStops, 1, file: file, line: line)
        XCTAssertFalse(airplaneMode.shieldsUp, file: file, line: line)
        XCTAssertNil(AirplaneModeFlightStore.load(from: defaults), file: file, line: line)
    }

    // MARK: Launch

    func testLaunchClearsShieldsLeftByADeadProcess() {
        blocker.restrictionsActive = true
        AirplaneModeFlightStore.save(sampleFlight(), to: defaults)
        let relaunched = AirplaneMode(blocker: blocker, defaults: defaults)
        XCTAssertTrue(relaunched.shieldsUp)

        relaunched.cleanUpAtLaunch()

        XCTAssertFalse(blocker.restrictionsActive)
        XCTAssertFalse(relaunched.shieldsUp)
        XCTAssertNil(AirplaneModeFlightStore.load(from: defaults))
        XCTAssertEqual(blocker.safetyNetStops, 1)
    }

    func testLaunchLeavesAFlightInProgressAlone() {
        blocker.restrictionsActive = true
        airplaneMode.cleanUpAtLaunch(flightInProgress: true)
        XCTAssertTrue(blocker.restrictionsActive)
        XCTAssertEqual(blocker.deactivations, 0)
    }

    func testLaunchWithNothingUpDoesNothing() {
        airplaneMode.cleanUpAtLaunch()
        XCTAssertEqual(blocker.deactivations, 0)
        XCTAssertEqual(blocker.safetyNetStops, 0)
    }

    // MARK: Authorization

    func testCancelledAuthorizationKeepsTheFeature() async {
        blocker.authorization = .notDetermined
        blocker.authorizationOutcome = .canceled
        let granted = await airplaneMode.requestAuthorization()
        XCTAssertFalse(granted)
        XCTAssertTrue(airplaneMode.isAvailable)
    }

    func testUnavailableScreenTimeHidesTheFeature() async {
        blocker.authorization = .notDetermined
        blocker.authorizationOutcome = .unavailable("no entitlement")
        let granted = await airplaneMode.requestAuthorization()
        XCTAssertFalse(granted)
        XCTAssertFalse(airplaneMode.isAvailable)
        XCTAssertEqual(airplaneMode.unavailableReason, "no entitlement")
    }

    func testOnboardingOffersThePageOnlyWhereScreenTimeExists() {
        XCTAssertEqual(OnboardingPage.pages(offersAirplaneMode: true),
                       [.hello, .takeoff, .inFlight, .airplaneMode, .privacy])
        XCTAssertEqual(OnboardingPage.pages(offersAirplaneMode: false),
                       [.hello, .takeoff, .inFlight, .privacy])
        XCTAssertFalse(AirplaneMode(blocker: UnsupportedAppBlocker(), defaults: defaults).isAvailable)
    }

    // MARK: Schedule

    func testSafetyNetEndsAtTheScheduledEndPlusTheMargin() {
        let departure = Date(timeIntervalSince1970: 1_700_000_000)
        let oneLeg = AirplaneModeSchedule.safetyNetEnd(departure: departure, legDurations: [3600],
                                                       layover: 0, finalCallWindow: 180)
        XCTAssertEqual(oneLeg, departure.addingTimeInterval(3600 + AirplaneModeSchedule.margin))

        // Two legs: both legs, the layover, and boarding's final call after it.
        let connection = AirplaneModeSchedule.safetyNetEnd(departure: departure, legDurations: [3600, 5400],
                                                           layover: 900, finalCallWindow: 180)
        XCTAssertEqual(connection,
                       departure.addingTimeInterval(3600 + 900 + 180 + 5400 + AirplaneModeSchedule.margin))
    }

    func testSafetyNetCoversTheWholeConnectingItinerary() throws {
        let session = makeConnectionSession(leg1: 90, layover: 40, leg2: 100)
        let departure = clock.now
        session.departFirstLeg()
        let record = try XCTUnwrap(AirplaneModeFlightStore.load(from: defaults))
        XCTAssertEqual(record.safetyNetEndsAt,
                       departure.addingTimeInterval(90 + 40 + FlightSession.finalCallWindow + 100
                                                    + AirplaneModeSchedule.margin))
    }

    func testIntervalOpensAtMidnightAndEndsAtTheEndTime() {
        let calendar = utcCalendar
        let now = date("2026-10-01T14:00:00Z")
        let interval = AirplaneModeSchedule.interval(until: date("2026-10-01T16:45:30Z"), now: now, calendar: calendar)
        XCTAssertEqual(interval.start, DateComponents(hour: 0, minute: 0, second: 0))
        XCTAssertEqual(interval.end, DateComponents(hour: 16, minute: 45, second: 30))
        XCTAssertFalse(interval.cappedAtMidnight)
    }

    func testIntervalPastMidnightIsCappedAndReArmsForTheRest() {
        let calendar = utcCalendar
        let end = date("2026-10-02T01:30:00Z")
        let capped = AirplaneModeSchedule.interval(until: end, now: date("2026-10-01T23:00:00Z"), calendar: calendar)
        XCTAssertEqual(capped.end, DateComponents(hour: 23, minute: 59, second: 59))
        XCTAssertTrue(capped.cappedAtMidnight)

        // The capped interval ends at 23:59:59; the re-arm covers the new day.
        let rest = AirplaneModeSchedule.rearmInterval(until: end, now: date("2026-10-01T23:59:59Z"), calendar: calendar)
        XCTAssertEqual(rest.start, DateComponents(hour: 0, minute: 0, second: 0))
        XCTAssertEqual(rest.end, DateComponents(hour: 1, minute: 30, second: 0))
        XCTAssertFalse(rest.cappedAtMidnight)
    }

    func testMonitorDecision() {
        let flight = sampleFlight()
        let name = AirplaneModeSchedule.activityName(for: flight.id)
        XCTAssertEqual(AirplaneModeSchedule.flightID(fromActivity: name), flight.id)

        XCTAssertEqual(AirplaneModeSchedule.decision(forActivity: name, flight: flight,
                                                     now: flight.safetyNetEndsAt),
                       .lowerShields)
        XCTAssertEqual(AirplaneModeSchedule.decision(forActivity: name, flight: nil, now: .now),
                       .lowerShields, "nothing in flight: a stray shield comes down")
        let later = AirplaneModeFlight(id: UUID(), destinationCode: "JFK", destinationCity: "New York",
                                       landsAt: flight.landsAt, safetyNetEndsAt: flight.safetyNetEndsAt)
        XCTAssertEqual(AirplaneModeSchedule.decision(forActivity: name, flight: later,
                                                     now: flight.safetyNetEndsAt),
                       .ignore, "a later flight owns the shields")
        XCTAssertEqual(AirplaneModeSchedule.decision(forActivity: "SomeoneElse:x", flight: flight,
                                                     now: flight.safetyNetEndsAt),
                       .ignore)
        XCTAssertEqual(AirplaneModeSchedule.decision(forActivity: name, flight: flight,
                                                     now: flight.safetyNetEndsAt.addingTimeInterval(-3600)),
                       .rearm(until: flight.safetyNetEndsAt), "capped at midnight, still flying")
    }

    func testShieldCopy() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var flight = sampleFlight()
        flight.landsAt = now.addingTimeInterval(42 * 60 - 10)
        XCTAssertEqual(AirplaneModeShieldCopy(flight: flight, now: now).subtitle,
                       "On your way to New York (JFK). Landing in 42 minutes.")
        flight.destinationCode = nil
        flight.destinationCity = nil
        flight.landsAt = now.addingTimeInterval(30)
        XCTAssertEqual(AirplaneModeShieldCopy(flight: flight, now: now).subtitle,
                       "Open skies. Landing in 1 minute.")
        XCTAssertEqual(AirplaneModeShieldCopy(flight: nil, now: now).title, "You're in flight")
        XCTAssertEqual(AirplaneModeCopy.blockedLine(count: 1), "1 app blocked during flights")
        XCTAssertEqual(AirplaneModeCopy.blockedLine(count: 7), "7 apps blocked during flights")
    }

    // MARK: Helpers

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private func sampleFlight() -> AirplaneModeFlight {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return AirplaneModeFlight(id: UUID(), destinationCode: "JFK", destinationCity: "New York",
                                  landsAt: now.addingTimeInterval(3600),
                                  safetyNetEndsAt: now.addingTimeInterval(3600 + AirplaneModeSchedule.margin))
    }

    private func makeSession(duration: TimeInterval, airplaneMode: AirplaneMode? = nil) -> FlightSession {
        let leg = FlightLeg(origin: Airport.byCode("BOS"), destination: Airport.byCode("JFK"),
                            duration: duration, flightNumber: "VOY 214")
        return FlightSession(itinerary: Itinerary(legs: [leg], layoverDuration: 0),
                             modelContext: context, tier: .member, clock: clock,
                             airplaneMode: airplaneMode ?? self.airplaneMode)
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
        return FlightSession(itinerary: itinerary, modelContext: context, tier: .gold, clock: clock,
                             airplaneMode: airplaneMode)
    }
}
