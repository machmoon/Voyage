import Foundation
import SwiftUI
import SwiftData
import os
import Observation
import CoreLocation

/// Where we are inside a single leg, derived from elapsed time.
enum LegPhase: Int, Comparable {
    case takeoffRoll   // engines to full power, runway lights streaking
    case climb         // rotation, punching through cloud layers
    case cruise        // the long middle — this is the study time
    case descent       // block-time-scaled descent toward the arrival corridor
    case landing       // flare, touchdown, and the final 30-second rollout

    static func < (lhs: LegPhase, rhs: LegPhase) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The live study session, themed as a (possibly multi-leg) flight.
/// Owns all timing, phase transitions, PA/audio cues, strict-mode
/// enforcement, and writes the logbook entry at the end.
@MainActor
@Observable
final class FlightSession {

    enum Stage: Equatable {
        case preflight          // seat / bag / boarding pass ritual
        case inFlight
        case layover            // lounge between legs of a long-haul
        case arrived            // landed at the final destination
        case diverted           // strict-mode failure
        case missedConnection   // layover boarding window expired
    }

    /// Why a session ended as diverted (not used for missed connections).
    enum DiversionReason: Equatable {
        case backgroundTimeout
        case voluntary
    }

    // MARK: Configuration

    let itinerary: Itinerary
    var seat: String = "—"
    var aircraft: AircraftProfile = .boeing737800
    var intentions: [String] = []
    let bookedAt: Date

    /// Frequent-flyer tier at booking time; drives cosmetic unlocks only.
    let tier: FlyerTier
    var isPremiumCabin: Bool { tier >= .silver }
    var hasPremiumChime: Bool { tier == .platinum }
    var hasSunsetScene: Bool { tier >= .gold }
    var hasAuroraScene: Bool { tier == .platinum }

    // MARK: Live state

    private(set) var stage: Stage = .preflight
    private(set) var legIndex: Int = 0
    private(set) var legStartDate: Date?
    private(set) var now: Date
    /// Real current weather at the current leg's endpoints.
    private(set) var originCondition: SkyCondition = .clear
    private(set) var destinationCondition: SkyCondition = .clear
    private(set) var originWeatherSnapshot: WeatherSnapshot?
    /// Weather and runway choices are frozen before the first takeoff. They
    /// never mutate while a leg is in progress, so live and replay match.
    private(set) var frozenLegEnvironments: [FlightEnvironmentSnapshot] = []
    private(set) var legTrajectories: [FlightTrajectory] = []
    /// Cached samples from those same trajectories for the live flight-map
    /// polylines. This keeps authored runway turns/approaches aligned with the
    /// marker without resampling the spline every SwiftUI update.
    private(set) var legMapSamples: [[FlightTrajectorySample]] = []
    private(set) var connectionDeparts: Date?
    private(set) var completedMiles: Double = 0
    private(set) var completedFocusSeconds: TimeInterval = 0
    private(set) var logEntry: LogbookEntry?
    /// True when the logbook entry could not be written to disk. The arrival
    /// and diversion screens say so instead of celebrating a flight that is
    /// about to vanish on the next launch.
    private(set) var logbookSaveFailed = false
    private static let logger = Logger(subsystem: "com.patrickliu.voyage", category: "session")
    /// Set when `stage == .diverted` — distinguishes user exit from background timeout.
    private(set) var diversionReason: DiversionReason?
    /// Wall-clock moment the pass was torn. The logbook's `date` records
    /// when the flight ended, so the recorder needs this separately.
    private(set) var departedAt: Date?

    /// Deadline after which backgrounding becomes a diversion.
    private(set) var graceDeadline: Date?

    /// While set, the beverage cart is at your row; nil once it moves on.
    private(set) var beverageCartUntil: Date?
    private(set) var watersTaken = 0
    // MARK: Cabin service (wellness cues)

    /// A cue currently on screen. Purely presentational: nothing in strict
    /// mode, diversion, leg completion or the logbook reads this.
    struct CabinServiceCue: Equatable {
        let pass: CabinServicePlanner.Pass
        /// When it disappears on its own if nobody touches it.
        let expiresAt: Date
    }

    private(set) var serviceCue: CabinServiceCue?
    /// Whether `finishSession` wrote the entry. False for a sub-minute
    /// false start, which the diverted screen describes but the logbook
    /// does not keep.
    private(set) var loggedToLogbook = false
    private(set) var servicePlanner = CabinServicePlanner()

    /// Cues offered and ignored on this leg, in safeeyes' sense: a count, kept
    /// so the screen can be honest, never used to prompt or to penalise.
    var serviceCuesOffered: Int { servicePlanner.passNumber }
    var serviceCuesIgnored: Int { servicePlanner.ignored }

    /// Whether cues run at all. Short flights are QA and demo captures, and
    /// `-VoyageShortFlights` compresses a 90 minute leg into seconds, so a
    /// 20 minute cadence there would either never fire or fire absurdly.
    /// Launch argument `-VoyageCabinServiceDemo` compresses the 20 minute
    /// cadence to seconds and overrides the short-flight suppression, so a UI
    /// test can photograph a cue. QA and capture only; it changes nothing in
    /// a shipped build, where the argument is never present.
    nonisolated static var cabinServiceDemoEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-VoyageCabinServiceDemo")
    }

    /// Seconds of cruise between cues.
    nonisolated static var servicePassInterval: TimeInterval {
        cabinServiceDemoEnabled ? 6 : CabinServicePlanner.passInterval
    }

    /// Pure so the suppression rules can be tested directly. A unit test
    /// cannot set a launch argument, so the flags arrive as parameters rather
    /// than being read inside the check.
    nonisolated static func cabinServiceActive(enabled: Bool,
                                               shortFlights: Bool,
                                               demo: Bool = false) -> Bool {
        guard enabled else { return false }
        return demo || !shortFlights
    }

    private var cabinServiceActive: Bool {
        Self.cabinServiceActive(
            enabled: SettingsStore.shared.cabinServiceEnabled,
            shortFlights: Self.shortFlightsEnabled,
            demo: Self.cabinServiceDemoEnabled
        )
    }

    /// The traveller acted on the cue. Counts it and clears the card. There is
    /// deliberately no other effect.
    func acknowledgeServiceCue() {
        guard serviceCue != nil else { return }
        servicePlanner.acknowledge()
        serviceCue = nil
        Haptics.softTick()
    }

    /// Dismiss without counting it as taken. Same as letting it expire.
    func dismissServiceCue() {
        serviceCue = nil
    }

    /// Takes the card away when its time is up, or the moment the aircraft
    /// leaves cruise. A cue raised in the last seconds of cruise must not
    /// still be sitting there during descent.
    private func expireServiceCue() {
        guard let cue = serviceCue else { return }
        if now >= cue.expiresAt || phase != .cruise {
            serviceCue = nil
        }
    }

    private var timer: Timer?
    private var graceWorkItem: DispatchWorkItem?
    private var preflightWeatherTask: Task<Void, Never>?
    private var prefetchedLegEnvironments: [FlightEnvironmentSnapshot]?
    private var firedEvents: Set<Event> = []
    private let modelContext: ModelContext
    private let clock: any VoyageClock

    // MARK: Phase timing constants

    /// Launch argument `-VoyageShortFlights` compresses takeoff/climb for QA screenshots
    /// without waiting ~90s of real-time (see README).
    nonisolated static var shortFlightsEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-VoyageShortFlights")
            || ProcessInfo.processInfo.environment["VOYAGE_SHORT_FLIGHTS"] == "1"
            || demoFlightEnabled
    }

    /// Launch argument `-VoyageDemoFlight` compresses the *whole* flight, not
    /// just the climb, so a screen recording can reach the arrival flow in
    /// about a minute. QA and marketing captures only.
    ///
    /// The clamp lives here rather than in `RoutePlanner` on purpose: flattening
    /// the catalog would make every route the same length and break the home
    /// screen's shortest-flight-first ordering.
    nonisolated static var demoFlightEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-VoyageDemoFlight")
    }

    /// Leg length under `-VoyageDemoFlight`. Long enough that takeoff, cruise,
    /// descent and landing each still get screen time.
    nonisolated static let demoLegDuration: TimeInterval = 60

    /// Fallback ground-roll length for callers without a trajectory. The live
    /// window and airport world take the leg's `FlightPhaseSchedule` instead
    /// (per-aircraft 32 to 48 s real, 28 s under short flights).
    nonisolated static var takeoffRollDuration: TimeInterval { shortFlightsEnabled ? 13 : 34 }
    /// Compatibility constants for dormant procedural artwork. Live session
    /// boundaries come from the aircraft- and block-time-specific schedule.
    nonisolated static var climbEndsAt: TimeInterval { shortFlightsEnabled ? 30 : 8.5 * 60 }
    nonisolated static var descentDuration: TimeInterval { demoFlightEnabled ? 20 : 25 * 60 }
    nonisolated static var landingDuration: TimeInterval { demoFlightEnabled ? 8 : 30 }
    nonisolated static let graceDuration: TimeInterval = 30
    /// Shortest unfinished flight the logbook records. Below this a diversion
    /// is a false start and is shown but not kept.
    nonisolated static let minimumLoggedFocus: TimeInterval = 60
    nonisolated static let finalCallWindow: TimeInterval = 3 * 60

    /// Beverage service: a hydration nudge for long study flights — first
    /// pass ~25 min into cruise, then about every half hour. Short QA flights
    /// skip the cart entirely so demos aren't interrupted.
    nonisolated static var beverageFirstDelay: TimeInterval { shortFlightsEnabled ? .infinity : 25 * 60 }
    nonisolated static var beverageInterval: TimeInterval { shortFlightsEnabled ? .infinity : 30 * 60 }
    /// How long the cart lingers at your row before moving on.
    nonisolated static var beverageCartWindow: TimeInterval { shortFlightsEnabled ? 12 : 90 }
    /// Skip beverage service on hops shorter than this (cruise never gets long enough).
    nonisolated static let beverageMinimumLegDuration: TimeInterval = 45 * 60

    init(itinerary: Itinerary,
         modelContext: ModelContext,
         tier: FlyerTier,
         clock: any VoyageClock = SystemClock()) {
        self.itinerary = itinerary
        self.modelContext = modelContext
        self.tier = tier
        self.clock = clock
        let t = clock.now
        self.bookedAt = t
        self.now = t
    }

#if DEBUG
    /// Builds a session already parked at the gate (`.arrived`) so the
    /// passport-stamp payoff can be driven directly for QA screenshots,
    /// bypassing the full descent. Never reachable in release builds.
    static func debugArrived(modelContext: ModelContext) -> FlightSession {
        let sfo = Airport.all.first { $0.code == "SFO" } ?? Airport.all[0]
        let jfk = Airport.all.first { $0.code == "JFK" } ?? Airport.all[1]
        let itinerary = RoutePlanner.itinerary(from: jfk, to: sfo)
        let session = FlightSession(itinerary: itinerary,
                                    modelContext: modelContext,
                                    tier: .gold)
        session.seat = "C10"
        session.intentions = ["Finish problem set 4", "Read chapter 9"]
        session.completedMiles = itinerary.legs.reduce(0) { $0 + $1.distanceMiles }
        session.completedFocusSeconds = itinerary.totalFocusDuration
        session.watersTaken = 2
        session.stage = .arrived
        let entry = LogbookEntry(
            date: session.now,
            originCode: itinerary.origin.code,
            destinationCode: itinerary.destination.code,
            connectionCode: itinerary.connection?.code,
            flightNumber: itinerary.primaryFlightNumber,
            seat: session.seat,
            miles: session.completedMiles,
            focusSeconds: itinerary.totalFocusDuration,
            completed: true,
            intentions: session.intentions,
            intentionsCompleted: Array(repeating: false, count: session.intentions.count),
            aircraft: session.aircraft,
            weatherSnapshot: nil,
            departureProfile: session.departureProfile,
            worldRevision: FlightVisualEngine.trajectoryRevision,
            routeSamples: [],
            departureCorridorID: nil,
            arrivalCorridorID: nil,
            environmentSnapshots: nil,
            trajectoryLegSamples: nil
        )
        session.logEntry = entry
        return session
    }
#endif

    // MARK: Derived timing

    var currentLeg: FlightLeg {
        let legs = itinerary.legs
        precondition(!legs.isEmpty, "Itinerary must have at least one leg")
        return legs[min(max(0, legIndex), legs.count - 1)]
    }

    var legElapsed: TimeInterval {
        guard let start = legStartDate else { return 0 }
        return max(0, now.timeIntervalSince(start))
    }

    /// Block time for the leg as flown. `-VoyageDemoFlight` squeezes it; the
    /// catalog keeps the real number either way.
    var legDuration: TimeInterval {
        Self.demoFlightEnabled ? Self.demoLegDuration : currentLeg.duration
    }

    /// Lounge break between legs, squeezed alongside the legs under the demo
    /// flag so a recording does not stall for fifteen minutes at the gate.
    var layoverDuration: TimeInterval {
        Self.demoFlightEnabled ? 20 : itinerary.layoverDuration
    }

    /// The leg handed to the visual engine, so the drawn flight and the session
    /// clock agree on how long the flight is.
    private func flownLeg(_ leg: FlightLeg) -> FlightLeg {
        guard Self.demoFlightEnabled else { return leg }
        return FlightLeg(origin: leg.origin, destination: leg.destination,
                         duration: Self.demoLegDuration, flightNumber: leg.flightNumber)
    }

    var legRemaining: TimeInterval { max(0, legDuration - legElapsed) }
    var legProgress: Double {
        currentVisualState?.routeProgress ?? {
            let d = legDuration
            guard d > 0 else { return 0 }
            return min(1, legElapsed / d)
        }()
    }

    var currentTrajectory: FlightTrajectory? {
        guard legTrajectories.indices.contains(legIndex) else { return nil }
        return legTrajectories[legIndex]
    }

    var phaseSchedule: FlightPhaseSchedule {
        currentTrajectory?.schedule ?? FlightPhaseSchedule.make(
            legDuration: legDuration,
            aircraft: aircraft,
            shortFlights: Self.shortFlightsEnabled
        )
    }

    var currentVisualState: FlightVisualState? {
        currentTrajectory?.state(at: legElapsed, seat: seat)
    }

    /// Remaining focus time across all legs (excludes layover).
    var totalRemaining: TimeInterval {
        let future = itinerary.legs.dropFirst(legIndex + 1).reduce(0) { $0 + $1.duration }
        return legRemaining + future
    }

    /// Elapsed seconds at which cruise begins on this leg, using the same
    /// clamps `phase` uses. Cabin service cues are measured from here so a cue
    /// can never be scheduled into the climb.
    var cruiseBeginsAt: TimeInterval { phaseSchedule.climbEnd }

    var phase: LegPhase {
        phaseSchedule.phase(at: legElapsed)
    }

    /// Elapsed time within the current visual phase. Renderers use this instead
    /// of starting their own wall clocks, so replay and ManualClock tests see
    /// exactly the same animation frame as a live session.
    var phaseElapsed: TimeInterval {
        let schedule = phaseSchedule
        switch phase {
        case .takeoffRoll: return legElapsed
        case .climb: return max(0, legElapsed - schedule.takeoffEnd)
        case .cruise: return max(0, legElapsed - schedule.climbEnd)
        case .descent: return max(0, legElapsed - schedule.descentStart)
        case .landing: return max(0, legElapsed - schedule.landingStart)
        }
    }

    /// The ambience bed matching the current phase (used when the user
    /// re-enables sound mid-flight).
    var ambienceProfile: CabinAudioEngine.Profile {
        switch phase {
        case .takeoffRoll: return .takeoffRoll
        case .climb: return .climb
        case .cruise: return .cruise
        case .descent: return .descent
        case .landing: return .landingRoll
        }
    }

    /// Altitude sampled from the same geospatial trajectory as the window and
    /// flight map. Airport elevation is therefore preserved on the runway.
    var altitudeFeet: Int {
        guard let feet = currentVisualState?.aircraft.altitudeFeet else { return 0 }
        return max(0, Int((feet / 50).rounded()) * 50)
    }

    /// True trajectory ground speed for the flight-info pill and cues.
    var groundSpeedMph: Int {
        if let metersPerSecond = currentVisualState?.aircraft.groundSpeedMetersPerSecond {
            return max(0, Int((metersPerSecond * 2.236_936).rounded()))
        }
        return 0
    }

    /// Weather for the window: departure conditions while climbing out,
    /// calm clear sky at cruise (above the weather), arrival conditions
    /// only once we tip over for descent — never sunny→rainy→sunny mid-leg.
    var windowCondition: SkyCondition {
        currentVisualState?.environment.weather(at: legProgress)?.condition
            ?? (phase < .descent ? originCondition : destinationCondition)
    }

    /// Seats over the wing get the wing in their window view.
    /// Rows 5–8 of the 2–2 cabin sit over the wing box.
    /// (Seat labels are letter-first, e.g. "C10".)
    var hasWingView: Bool {
        guard let row = Int(seat.filter(\.isNumber)) else { return false }
        return (5...8).contains(row)
    }

    var windowSide: WindowSide { WindowSide(seat: seat) }
    var departureProfile: DepartureProfile {
        let firstLeg = itinerary.legs[0]
        let weather = frozenLegEnvironments.first?.departureWeather ?? originWeatherSnapshot
        return AirportWorldCatalog.departureProfile(for: firstLeg.origin, weather: weather)
    }

    /// Live great-circle position along the current leg, for the map view.
    var currentCoordinate: CLLocationCoordinate2D {
        currentVisualState?.aircraft.coordinate
            ?? GreatCircle.point(from: currentLeg.origin.coordinate,
                                 to: currentLeg.destination.coordinate,
                                 fraction: legProgress)
    }

    /// Current true course toward the destination, degrees from north.
    var currentCourse: Double {
        currentVisualState?.aircraft.courseDegrees
            ?? GreatCircle.bearing(from: currentCoordinate,
                                   to: currentLeg.destination.coordinate)
    }

    var layoverRemaining: TimeInterval {
        guard let departs = connectionDeparts else { return 0 }
        return max(0, departs.timeIntervalSince(now))
    }

    /// Once the connection "departs", a short final-call window remains.
    var finalCallRemaining: TimeInterval {
        guard let departs = connectionDeparts else { return 0 }
        return max(0, departs.addingTimeInterval(Self.finalCallWindow).timeIntervalSince(now))
    }

    var isFinalCall: Bool {
        stage == .layover && layoverRemaining == 0 && finalCallRemaining > 0
    }

    /// The instant the lock-screen card stops telling the truth, assuming this
    /// process never gets to post another update.
    ///
    /// That assumption is the point. Voyage has no background modes, so once
    /// the system suspends us neither the 0.5 s tick nor the grace-period work
    /// item runs: backgrounding past the grace deadline is a diversion that
    /// nothing is awake to perform, and without this the lock screen would keep
    /// showing a live flight for hours. Handing the deadline to ActivityKit as
    /// a stale date moves the decision to the system, which is awake.
    ///
    /// Derived from `now`, so it follows the injected clock like everything
    /// else here.
    var activityStaleDate: Date? {
        switch stage {
        case .preflight:
            return nil
        case .inFlight:
            let arrival = now.addingTimeInterval(legRemaining)
            // Backgrounded: the session dies at the grace deadline, which is
            // sooner than arrival.
            guard let grace = graceDeadline else { return arrival }
            return min(arrival, grace)
        case .layover:
            guard let departs = connectionDeparts else { return nil }
            return departs.addingTimeInterval(Self.finalCallWindow)
        case .arrived, .diverted, .missedConnection:
            return now
        }
    }

    // MARK: Flow control

    /// Starts bounded weather prefetch while the passenger completes boarding.
    /// Departure never waits for the network: `departFirstLeg` atomically uses
    /// completed snapshots or deterministic clear fallbacks.
    func prepareRealWorldTwin() {
        guard stage == .preflight else { return }
        preflightWeatherTask?.cancel()
        let legs = itinerary.legs
        let frozenAt = clock.now
        preflightWeatherTask = Task { [weak self] in
            let environments = await withTaskGroup(
                of: (Int, FlightEnvironmentSnapshot).self,
                returning: [FlightEnvironmentSnapshot].self
            ) { group in
                for (index, leg) in legs.enumerated() {
                    group.addTask {
                        let environment = await WeatherService.freezeEnvironment(
                            for: leg,
                            frozenAt: frozenAt
                        )
                        return (index, environment)
                    }
                }
                var values: [(Int, FlightEnvironmentSnapshot)] = []
                for await value in group { values.append(value) }
                return values.sorted { $0.0 < $1.0 }.map(\.1)
            }
            guard !Task.isCancelled, let self, self.stage == .preflight,
                  environments.count == legs.count else { return }
            self.prefetchedLegEnvironments = environments
            self.originWeatherSnapshot = environments.first?.departureWeather
            self.originCondition = environments.first?.departureWeather?.condition ?? .clear
            self.destinationCondition = environments.last?.arrivalWeather?.condition ?? .clear
        }
    }

    /// Called when the boarding pass is ripped: the flight begins.
    func departFirstLeg() {
        guard stage == .preflight else { return }
        freezeVisualPlanIfNeeded()
        departedAt = clock.now
        // Remember the seat once the pass is torn, not when it was picked:
        // a seat chosen and then abandoned at the gate is not a preference.
        if seat != "—" {
            SettingsStore.shared.rememberSeat(seat, on: aircraft)
        }
        // Which timing the leg is really flying under. Reading this from the
        // simulator log is how a stale app instance without launch arguments
        // was caught driving a recording (`log show --info --predicate
        // 'subsystem == "com.patrickliu.voyage"'`).
        Self.logger.info("departing: leg \(self.legDuration, privacy: .public)s short=\(Self.shortFlightsEnabled, privacy: .public) demo=\(Self.demoFlightEnabled, privacy: .public)")
        startTimer()
        startLeg()
        writeInFlightRecord()
        FocusIntegration.shared.onDepart(session: self)
    }

    /// Called from the layover lounge to board the connecting leg.
    func boardConnection() {
        guard stage == .layover, legIndex + 1 < itinerary.legs.count else { return }
        legIndex += 1
        startLeg()
        writeInFlightRecord()
    }

    /// Enough to log this flight if the process dies before `finishSession`.
    private func writeInFlightRecord() {
        guard let departedAt, let legStartDate else { return }
        InterruptedFlightRecovery.save(InFlightRecord(
            originCode: itinerary.origin.code,
            destinationCode: itinerary.destination.code,
            connectionCode: itinerary.connection?.code,
            flightNumber: itinerary.primaryFlightNumber,
            seat: seat,
            intentions: intentions,
            departedAt: departedAt,
            completedFocusSeconds: completedFocusSeconds,
            completedMiles: completedMiles,
            legStartedAt: legStartDate,
            legDuration: legDuration,
            scheduledSeconds: itinerary.totalFocusDuration
        ))
    }

    private func startLeg() {
        freezeVisualPlanIfNeeded()
        stage = .inFlight
        let t = clock.now
        legStartDate = t
        now = t
        firedEvents = []
        if frozenLegEnvironments.indices.contains(legIndex) {
            let environment = frozenLegEnvironments[legIndex]
            originWeatherSnapshot = environment.departureWeather
            originCondition = environment.departureWeather?.condition ?? .clear
            destinationCondition = environment.arrivalWeather?.condition ?? .clear
        }
        // The lounge between legs is itself a break: you stand, you leave the
        // seat, you look at something further away than a screen. So the
        // cadence starts over rather than carrying a debt across the layover.
        servicePlanner.reset()
        serviceCue = nil
        FlightActivityController.shared.start(session: self)
        // The passenger enters the scene already lined up for departure, so
        // the first sound bed is runway acceleration rather than taxiing.
        CabinAudioEngine.shared.startAmbience(profile: .takeoffRoll)
        Task { @MainActor [weak self] in
            guard let self, self.stage == .inFlight else { return }
            try? await Task.sleep(for: .milliseconds(200))
            guard self.stage == .inFlight else { return }
            Announcer.shared.announce(.welcomeAboard, premiumChime: self.hasPremiumChime)
        }
    }

    /// Select every runway and corridor exactly once before the first roll.
    /// Later weather or settings changes cannot alter an in-progress flight.
    private func freezeVisualPlanIfNeeded() {
        guard legTrajectories.isEmpty else { return }
        preflightWeatherTask?.cancel()
        preflightWeatherTask = nil

        let frozenAt = clock.now
        let environments: [FlightEnvironmentSnapshot]
        if let prefetchedLegEnvironments,
           prefetchedLegEnvironments.count == itinerary.legs.count {
            environments = prefetchedLegEnvironments
        } else {
            environments = itinerary.legs.map {
                FlightEnvironmentSnapshot.fallback(for: $0, frozenAt: frozenAt)
            }
        }
        self.prefetchedLegEnvironments = nil
        self.frozenLegEnvironments = environments
        self.legTrajectories = zip(itinerary.legs, environments).map { leg, environment in
            FlightVisualEngine.trajectory(
                for: flownLeg(leg),
                aircraft: aircraft,
                environment: environment,
                shortFlights: Self.shortFlightsEnabled
            )
        }
        self.legMapSamples = legTrajectories.map {
            $0.replaySamples(count: 192, seat: seat)
        }

        originWeatherSnapshot = environments.first?.departureWeather
        originCondition = environments.first?.departureWeather?.condition ?? .clear
        destinationCondition = environments.first?.arrivalWeather?.condition ?? .clear
    }

    // MARK: Tick

    private func startTimer() {
        timer?.invalidate()
        // Session events remain deliberately low-frequency. The window owns a
        // display-linked visual timebase and samples the same injected clock at
        // 60/30 fps, so this timer does not determine rendering smoothness.
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Advances session logic using the injected clock. Tests call this after
    /// mutating a `ManualClock`; production uses the 0.5s Timer.
    func tick() {
        now = clock.now
        switch stage {
        case .inFlight:
            // Honor grace deadline even if the DispatchWorkItem was delayed —
            // keeps strict mode correct under clock injection and background audio.
            if let deadline = graceDeadline, now >= deadline {
                divert()
                return
            }
            fireDueEvents()
            // The cart moves on if ignored, and never lingers into descent.
            if let until = beverageCartUntil, now >= until || phase >= .descent {
                beverageCartUntil = nil
            }
            expireServiceCue()
            if legElapsed >= legDuration {
                completeLeg()
            }
        case .layover:
            if isFinalCall {
                fire(.finalCall) {
                    Haptics.warning()
                    Announcer.shared.announce(
                        .finalBoardingCall(city: currentLeg.destination.city),
                        premiumChime: hasPremiumChime
                    )
                    FlightNotifications.postFinalCallNotification(for: self)
                }
            }
            if let departs = connectionDeparts,
               now > departs.addingTimeInterval(Self.finalCallWindow) {
                missConnection()
            }
        default:
            break
        }
    }

    private enum Event: Hashable {
        case takeoffPower, rotate, gearUp, cruiseReached, midpoint
        case descentStart, gearDown, touchdown, finalCall
        case beverageService(Int)
        /// Indexed so the cue can repeat while `fire` keeps its fire-once
        /// guarantee per pass.
        case cabinService(Int)
    }

    /// Exposes deterministic cue state to the session tests without leaking
    /// the private event vocabulary into the rest of the app.
    var didFireRotationCue: Bool { firedEvents.contains(.rotate) }

    private func fire(_ event: Event, _ action: () -> Void) {
        guard !firedEvents.contains(event) else { return }
        firedEvents.insert(event)
        action()
        // Keep the lock-screen state aligned after each deterministic cue.
        FlightActivityController.shared.update(session: self)
    }

    private func fireDueEvents() {
        let e = legElapsed
        let d = legDuration
        let schedule = phaseSchedule

        let takeoffCue = Self.shortFlightsEnabled ? 0.8 : min(4.0, schedule.takeoffDuration * 0.14)
        let gearUpDelay = Self.shortFlightsEnabled ? 1.5 : 14.0

        if e >= takeoffCue {
            fire(.takeoffPower) {
                CabinAudioEngine.shared.setProfile(.takeoffRoll)
                CabinAudioEngine.shared.playTakeoffSpool()
                Haptics.softTick()
            }
        }
        if e >= schedule.rotationStart {
            fire(.rotate) {
                CabinAudioEngine.shared.setProfile(.climb)
                Haptics.tap()
            }
        }
        if e >= schedule.takeoffEnd + gearUpDelay {
            fire(.gearUp) {
                CabinAudioEngine.shared.playThunk()
                Haptics.gearThunk()
            }
        }
        if e >= schedule.climbEnd {
            fire(.cruiseReached) {
                CabinAudioEngine.shared.setProfile(.cruise)
                // Level off: the seatbelt sign goes out.
                CabinAudioEngine.shared.playSeatbeltSign()
            }
        }
        // Beverage cart: long-haul hydration nudge only — never on short
        // hops or QA compressed flights, and never once descent is close.
        if phase == .cruise,
           currentLeg.duration >= Self.beverageMinimumLegDuration,
           Self.beverageFirstDelay.isFinite,
           legRemaining > schedule.descentDuration + schedule.landingDuration + 120,
           SettingsStore.shared.cabinServiceEnabled {
            let firstService = schedule.climbEnd + Self.beverageFirstDelay
            if e >= firstService {
                let index = Int((e - firstService) / Self.beverageInterval)
                fire(.beverageService(index)) { startBeverageService() }
            }
        }
        if e >= d / 2 {
            fire(.midpoint) {
                Announcer.shared.announce(
                    .midpoint(city: currentLeg.destination.city),
                    premiumChime: hasPremiumChime
                )
            }
        }
        if e >= schedule.descentStart {
            fire(.descentStart) {
                CabinAudioEngine.shared.setProfile(.descent)
                // The seatbelt sign is the cue passengers actually recognize;
                // it lands before the announcement rather than under it.
                CabinAudioEngine.shared.playSeatbeltSign()
                Announcer.shared.announce(
                    .descent(city: currentLeg.destination.city),
                    premiumChime: hasPremiumChime
                )
            }
        }
        if e >= max(schedule.descentStart, schedule.landingStart - 60) {
            fire(.gearDown) {
                CabinAudioEngine.shared.playThunk()
                Haptics.gearThunk()
            }
        }
        if e >= schedule.landingStart {
            fire(.touchdown) {
                CabinAudioEngine.shared.setProfile(.landingRoll)
                CabinAudioEngine.shared.playTouchdown()
                Haptics.touchdown()
            }
        }

        fireDueServiceCue(elapsed: e)
    }

    /// Offers the next wellness cue if one is due and the cabin is in a state
    /// where an interruption is legitimate.
    ///
    /// Deliberately visual plus haptic only. It never calls `Announcer` or
    /// `CabinAudioEngine`: building the audio graph is a live crash risk, and
    /// a cue the traveller is free to ignore has no business being the thing
    /// that constructs it. Haptics are already a no-op on a device without
    /// the engine.
    private func fireDueServiceCue(elapsed e: TimeInterval) {
        guard cabinServiceActive else { return }
        // Descent and landing are never interrupted. `phase` is derived, so
        // this is the whole guard: the cue simply has no window outside cruise.
        guard phase == .cruise else { return }

        let next = servicePlanner.passNumber + 1
        let dueAt = CabinServicePlanner.due(pass: next,
                                            cruiseBeginsAt: cruiseBeginsAt,
                                            interval: Self.servicePassInterval)
        guard e >= dueAt else { return }

        fire(.cabinService(next)) {
            let pass = servicePlanner.offer()
            serviceCue = CabinServiceCue(
                pass: pass,
                expiresAt: now.addingTimeInterval(CabinServicePlanner.cueDuration)
            )
            Haptics.softTick()
        }
    }

    // MARK: Beverage service

    private func startBeverageService() {
        beverageCartUntil = now.addingTimeInterval(Self.beverageCartWindow)
        Haptics.softTick()
        if SettingsStore.shared.announcementsEnabled {
            Announcer.shared.announce(.beverageService, premiumChime: hasPremiumChime)
        } else if SettingsStore.shared.ambienceEnabled {
            // No PA, but the cart still dings on its way down the aisle.
            CabinAudioEngine.shared.playChime(premium: hasPremiumChime)
        }
    }

    /// The user takes a water from the cart.
    func takeWater() {
        guard beverageCartUntil != nil else { return }
        watersTaken += 1
        beverageCartUntil = nil
        Haptics.success()
    }

    // MARK: Leg completion

    private func completeLeg() {
        completedMiles += currentLeg.distanceMiles
        completedFocusSeconds += legDuration
        beverageCartUntil = nil

        if legIndex == itinerary.legs.count - 1 {
            stage = .arrived
            FlightActivityController.shared.end(session: self)
            CabinAudioEngine.shared.setProfile(.taxi)
            // Seatbelt sign off at the gate — the sound that releases a cabin.
            CabinAudioEngine.shared.playSeatbeltSign()
            Announcer.shared.announce(
                .landed(city: itinerary.destination.city),
                premiumChime: hasPremiumChime
            )
            finishSession(outcome: .arrived)
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                // Only stop if we haven't started another leg/session ambience.
                guard self?.stage == .arrived || self == nil else { return }
                CabinAudioEngine.shared.stopAmbience()
            }
        } else {
            stage = .layover
            connectionDeparts = now.addingTimeInterval(layoverDuration)
            FlightActivityController.shared.update(session: self)
            Announcer.shared.announce(
                .layover(city: currentLeg.destination.city),
                premiumChime: hasPremiumChime
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                guard self?.stage == .layover || self == nil else { return }
                CabinAudioEngine.shared.stopAmbience()
            }
        }
    }

    private func missConnection() {
        guard stage == .layover else { return }
        stage = .missedConnection
        stopEverything()
        finishSession(outcome: .missedConnection)
    }

    // MARK: Strict enforcement

    func handleScenePhase(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .background:
            guard stage == .inFlight else { return }
            let deadline = clock.now.addingTimeInterval(Self.graceDuration)
            graceDeadline = deadline
            // Best-effort timer until suspension; ActivityKit carries the expiry.
            // Tests rely on `tick()` and the injected clock.
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.stage == .inFlight,
                          let d = self.graceDeadline, self.clock.now >= d else { return }
                    self.divert()
                }
            }
            graceWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.graceDuration + 0.5, execute: work)
            // Push the grace deadline to ActivityKit as a stale date *before*
            // we are suspended. This is the only message the lock screen will
            // get, so it has to carry the expiry with it.
            FlightActivityController.shared.update(session: self)

        case .active:
            graceWorkItem?.cancel()
            graceWorkItem = nil
            if stage == .inFlight, let deadline = graceDeadline, clock.now > deadline {
                divert()
            } else {
                graceDeadline = nil
                FlightActivityController.shared.update(session: self)
            }

        default:
            break
        }
    }

    func divert(reason: DiversionReason = .backgroundTimeout) {
        guard stage == .inFlight else { return }
        diversionReason = reason
        stage = .diverted
        stopEverything()
        finishSession(outcome: reason == .voluntary ? .leftEarly : .interrupted)
    }

    /// User bails out intentionally from the in-flight screen. Recorded
    /// apart from a strict-mode interruption: leaving on purpose and
    /// being pulled away are different facts.
    func abandonFlight() {
        divert(reason: .voluntary)
    }

    private func stopEverything() {
        serviceCue = nil
        beverageCartUntil = nil
        Announcer.shared.stop()
        CabinAudioEngine.shared.stopAmbience()
        FlightActivityController.shared.end(session: self)
        graceWorkItem?.cancel()
        graceWorkItem = nil
    }

    // MARK: Logbook

    private func finishSession(outcome: FlightOutcome) {
        let completed = outcome.didArrive
        timer?.invalidate()
        timer = nil
        preflightWeatherTask?.cancel()
        preflightWeatherTask = nil

        // Diverted mid-leg still credits the partial leg; a missed connection
        // credits exactly the legs that landed (layover time isn't focus).
        let partialLeg = stage == .diverted ? min(legElapsed, legDuration) : 0
        let focusSeconds = completed
            ? itinerary.totalFocusDuration
            : completedFocusSeconds + partialLeg

        // Persist the exact phase-aware samples used by the live map. This
        // preserves dense runway/corridor geometry and exact phase boundaries
        // in replay instead of creating a second, coarser uniform trace.
        let trajectoryLegSamples = legMapSamples.isEmpty
            ? legTrajectories.map { $0.replaySamples(count: 192, seat: seat) }
            : legMapSamples
        let entry = LogbookEntry(
            date: now,
            originCode: itinerary.origin.code,
            destinationCode: itinerary.destination.code,
            connectionCode: itinerary.connection?.code,
            flightNumber: itinerary.primaryFlightNumber,
            seat: seat,
            miles: completedMiles,
            focusSeconds: min(focusSeconds, itinerary.totalFocusDuration),
            completed: completed,
            intentions: intentions,
            intentionsCompleted: Array(repeating: false, count: intentions.count),
            aircraft: aircraft,
            weatherSnapshot: originWeatherSnapshot,
            departureProfile: departureProfile,
            worldRevision: FlightVisualEngine.trajectoryRevision,
            routeSamples: replayRouteSamples(from: trajectoryLegSamples),
            departureCorridorID: legTrajectories.first?.departureCorridor.id,
            arrivalCorridorID: legTrajectories.last?.arrivalCorridor.id,
            environmentSnapshots: frozenLegEnvironments.isEmpty ? nil : frozenLegEnvironments,
            trajectoryLegSamples: trajectoryLegSamples.isEmpty ? nil : trajectoryLegSamples,
            scheduledSeconds: itinerary.totalFocusDuration,
            departedAt: departedAt,
            outcome: outcome
        )
        // A flight that ended within its first minute is a false start, not
        // a trip: the diverted screen still shows it, the logbook does not.
        // Tearing a pass and backing out immediately used to leave rows of
        // "DIVERTED · 0m" at the top of the logbook.
        loggedToLogbook = completed || entry.focusSeconds >= Self.minimumLoggedFocus
        if loggedToLogbook {
            modelContext.insert(entry)
            do {
                try modelContext.save()
            } catch {
                logbookSaveFailed = true
                Self.logger.error("Logbook save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        InterruptedFlightRecovery.clear()
        logEntry = entry
        // Only a flight that actually landed counts toward the review ask.
        if completed { AppFeedback.recordCompletedFlight() }
        FocusIntegration.shared.onSessionEnded(session: self, completed: completed)
    }

    /// Called if the user dismisses the ritual before ripping the pass.
    func cancelBeforeDeparture() {
        timer?.invalidate()
        timer = nil
        preflightWeatherTask?.cancel()
        preflightWeatherTask = nil
        stopEverything()
    }

    private func replayRouteSamples(
        from legSamples: [[FlightTrajectorySample]]
    ) -> [ReplayRouteSample] {
        guard legSamples.count == itinerary.legs.count, !legSamples.isEmpty else {
            return ReplayRouteRecorder.samples(for: itinerary)
        }
        let total = max(1, itinerary.totalFocusDuration)
        var elapsedBeforeLeg: TimeInterval = 0
        var samples: [ReplayRouteSample] = []
        for (index, values) in legSamples.enumerated() {
            let legDuration = itinerary.legs[index].duration
            for (sampleIndex, sample) in values.enumerated() {
                // Adjacent legs share an endpoint; store it once.
                if index > 0 && sampleIndex == 0 { continue }
                let progress = min(1, max(0, (elapsedBeforeLeg + sample.elapsed) / total))
                samples.append(
                    ReplayRouteSample(
                        latitude: sample.latitude,
                        longitude: sample.longitude,
                        progress: progress
                    )
                )
            }
            elapsedBeforeLeg += legDuration
        }
        return samples
    }
}
