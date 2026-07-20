import Foundation
import SwiftUI
import SwiftData
import Observation
import CoreLocation

/// Where we are inside a single leg, derived from elapsed time.
enum LegPhase: Int, Comparable {
    case takeoffRoll   // engines to full power, runway lights streaking
    case climb         // rotation, punching through cloud layers
    case cruise        // the long middle — this is the study time
    case descent       // final ~3 minutes
    case landing       // flare, touchdown, rollout (last ~15 s)

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

    // MARK: Configuration

    let itinerary: Itinerary
    var seat: String = "—"
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
    private(set) var connectionDeparts: Date?
    private(set) var completedMiles: Double = 0
    private(set) var completedFocusSeconds: TimeInterval = 0
    private(set) var logEntry: LogbookEntry?

    /// Deadline after which backgrounding becomes a diversion.
    private(set) var graceDeadline: Date?

    private var timer: Timer?
    private var graceWorkItem: DispatchWorkItem?
    private var firedEvents: Set<Event> = []
    private let modelContext: ModelContext
    private let clock: any VoyageClock

    // MARK: Phase timing constants

    /// Launch argument `-VoyageShortFlights` compresses takeoff/climb for QA screenshots
    /// without waiting ~90s of real-time (see README).
    nonisolated static var shortFlightsEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-VoyageShortFlights")
    }

    nonisolated static var takeoffRollDuration: TimeInterval { shortFlightsEnabled ? 3 : 18 }
    /// Elapsed seconds when climb ends and cruise begins (includes the takeoff roll).
    nonisolated static var climbEndsAt: TimeInterval { shortFlightsEnabled ? 8 : 90 }
    nonisolated static let descentDuration: TimeInterval = 180
    nonisolated static let landingDuration: TimeInterval = 15
    nonisolated static let graceDuration: TimeInterval = 30
    nonisolated static let finalCallWindow: TimeInterval = 3 * 60

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

    var legRemaining: TimeInterval { max(0, currentLeg.duration - legElapsed) }
    var legProgress: Double {
        let d = currentLeg.duration
        guard d > 0 else { return 0 }
        return min(1, legElapsed / d)
    }

    /// Remaining focus time across all legs (excludes layover).
    var totalRemaining: TimeInterval {
        let future = itinerary.legs.dropFirst(legIndex + 1).reduce(0) { $0 + $1.duration }
        return legRemaining + future
    }

    var phase: LegPhase {
        let e = legElapsed
        let d = currentLeg.duration
        guard d > 0 else { return .cruise }

        // Clamp phase windows so short synthetic legs (unit tests / demos)
        // still progress without inverted cruise/descent intervals.
        let takeoffEnd = min(Self.takeoffRollDuration, d * 0.15)
        let climbEnd = min(Self.climbEndsAt, max(takeoffEnd + 0.01, d * 0.35))
        let landingStart = max(climbEnd, d - Self.landingDuration)
        let descentStart = max(climbEnd, min(landingStart, d - min(Self.descentDuration, d * 0.45)))

        if e < takeoffEnd { return .takeoffRoll }
        if e < climbEnd { return .climb }
        if e < descentStart { return .cruise }
        if e < landingStart { return .descent }
        return .landing
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

    /// Flavor altitude for the flight-info pill.
    var altitudeFeet: Int {
        let cruiseAlt = 36_000.0
        let climbSpan = max(0.001, Self.climbEndsAt - Self.takeoffRollDuration)
        let descentSpan = max(0.001, Self.descentDuration - Self.landingDuration)
        switch phase {
        case .takeoffRoll:
            return 0
        case .climb:
            let t = min(1, max(0, (legElapsed - Self.takeoffRollDuration) / climbSpan))
            return Int((t * t) * cruiseAlt / 100) * 100
        case .cruise:
            let wobble = sin(legElapsed / 47) * 240
            return Int((cruiseAlt + wobble) / 100) * 100
        case .descent:
            let intoDescent = max(0, legElapsed - (currentLeg.duration - Self.descentDuration))
            let t = min(1, intoDescent / descentSpan)
            return max(1_500, Int((1 - t) * cruiseAlt / 100) * 100)
        case .landing:
            let intoLanding = max(0, legElapsed - (currentLeg.duration - Self.landingDuration))
            let t = min(1, intoLanding / max(0.001, Self.landingDuration))
            return max(0, Int((1 - t) * 1_500 / 50) * 50)
        }
    }

    /// Flavor ground speed for the flight-info pill.
    var groundSpeedMph: Int {
        let climbSpan = max(0.001, Self.climbEndsAt - Self.takeoffRollDuration)
        let takeoff = max(0.001, Self.takeoffRollDuration)
        let descent = max(0.001, Self.descentDuration)
        let landing = max(0.001, Self.landingDuration)
        switch phase {
        case .takeoffRoll: return Int(min(1, legElapsed / takeoff) * 170)
        case .climb: return 170 + Int(min(1, max(0, (legElapsed - Self.takeoffRollDuration) / climbSpan)) * 370)
        case .cruise: return 540 + Int(sin(legElapsed / 31) * 12)
        case .descent: return 540 - Int((1 - min(1, legRemaining / descent)) * 380)
        case .landing: return max(0, Int(min(1, legRemaining / landing) * 150))
        }
    }

    /// Weather the window scene should show right now: departure conditions
    /// low on climb-out, arrival conditions once the descent begins.
    var windowCondition: SkyCondition {
        switch phase {
        case .takeoffRoll, .climb: return originCondition
        case .cruise, .descent, .landing: return destinationCondition
        }
    }

    /// Seats over the wing get the wing in their window view.
    /// Rows 5–8 of the 2–2 cabin sit over the wing box.
    /// (Seat labels are letter-first, e.g. "C10".)
    var hasWingView: Bool {
        guard let row = Int(seat.filter(\.isNumber)) else { return false }
        return (5...8).contains(row)
    }

    /// Live great-circle position along the current leg, for the map view.
    var currentCoordinate: CLLocationCoordinate2D {
        GreatCircle.point(from: currentLeg.origin.coordinate,
                          to: currentLeg.destination.coordinate,
                          fraction: legProgress)
    }

    /// Current true course toward the destination, degrees from north.
    var currentCourse: Double {
        GreatCircle.bearing(from: currentCoordinate,
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

    // MARK: Flow control

    /// Called when the boarding pass is ripped: the flight begins.
    func departFirstLeg() {
        guard stage == .preflight else { return }
        startTimer()
        startLeg()
    }

    /// Real weather at both ends of the current leg: departure conditions
    /// theme takeoff/climb, arrival conditions theme descent/landing.
    private func fetchLegWeather() {
        let leg = currentLeg
        Task { [weak self] in
            let origin = await WeatherService.condition(for: leg.origin)
            self?.originCondition = origin
        }
        Task { [weak self] in
            let destination = await WeatherService.condition(for: leg.destination)
            self?.destinationCondition = destination
        }
    }

    /// Called from the layover lounge to board the connecting leg.
    func boardConnection() {
        guard stage == .layover, legIndex + 1 < itinerary.legs.count else { return }
        legIndex += 1
        startLeg()
    }

    private func startLeg() {
        stage = .inFlight
        let t = clock.now
        legStartDate = t
        now = t
        firedEvents = []
        fetchLegWeather()
        // Ambience after a beat so a just-played rip one-shot never races
        // engine start / graph rebuild on the same turn as stage transition.
        CabinAudioEngine.shared.startAmbience(profile: .taxi)
        Task { @MainActor [weak self] in
            guard let self, self.stage == .inFlight else { return }
            try? await Task.sleep(for: .milliseconds(200))
            guard self.stage == .inFlight else { return }
            Announcer.shared.announce(
                .welcomeAboard(
                    flightNumber: self.currentLeg.flightNumber,
                    city: self.currentLeg.destination.city,
                    durationText: self.spokenDuration(self.currentLeg.duration)
                ),
                premiumChime: self.hasPremiumChime
            )
        }
    }

    // MARK: Tick

    private func startTimer() {
        timer?.invalidate()
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
            if legElapsed >= currentLeg.duration {
                completeLeg()
            }
        case .layover:
            if isFinalCall {
                fire(.finalCall) {
                    Haptics.warning()
                    Announcer.shared.announce(.finalBoardingCall(city: itinerary.destination.city),
                                              premiumChime: hasPremiumChime)
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
    }

    private func fire(_ event: Event, _ action: () -> Void) {
        guard !firedEvents.contains(event) else { return }
        firedEvents.insert(event)
        action()
    }

    private func fireDueEvents() {
        let e = legElapsed
        let d = currentLeg.duration

        let takeoffCue = Self.shortFlightsEnabled ? 0.8 : 4.0
        let gearUpDelay = Self.shortFlightsEnabled ? 1.5 : 14.0

        if e >= takeoffCue {
            fire(.takeoffPower) {
                CabinAudioEngine.shared.setProfile(.takeoffRoll)
                CabinAudioEngine.shared.playTakeoffSpool()
                Haptics.softTick()
            }
        }
        if e >= Self.takeoffRollDuration {
            fire(.rotate) {
                CabinAudioEngine.shared.setProfile(.climb)
                Haptics.tap()
            }
        }
        if e >= Self.takeoffRollDuration + gearUpDelay {
            fire(.gearUp) {
                CabinAudioEngine.shared.playThunk()
                Haptics.gearThunk()
            }
        }
        if e >= Self.climbEndsAt {
            fire(.cruiseReached) {
                CabinAudioEngine.shared.setProfile(.cruise)
                CabinAudioEngine.shared.playChime(premium: hasPremiumChime)
            }
        }
        if e >= d / 2 {
            fire(.midpoint) {
                Announcer.shared.announce(
                    .midpoint(city: currentLeg.destination.city, altitude: altitudeFeet),
                    premiumChime: hasPremiumChime
                )
            }
        }
        if e >= d - Self.descentDuration {
            fire(.descentStart) {
                CabinAudioEngine.shared.setProfile(.descent)
                Announcer.shared.announce(
                    .descent(city: currentLeg.destination.city,
                             weather: destinationCondition.spokenDescription),
                    premiumChime: hasPremiumChime
                )
            }
        }
        if e >= d - 60 {
            fire(.gearDown) {
                CabinAudioEngine.shared.playThunk()
                Haptics.gearThunk()
            }
        }
        if e >= d - Self.landingDuration {
            fire(.touchdown) {
                CabinAudioEngine.shared.setProfile(.landingRoll)
                CabinAudioEngine.shared.playTouchdown()
                Haptics.touchdown()
            }
        }
    }

    // MARK: Leg completion

    private func completeLeg() {
        completedMiles += currentLeg.distanceMiles
        completedFocusSeconds += currentLeg.duration

        if legIndex == itinerary.legs.count - 1 {
            stage = .arrived
            CabinAudioEngine.shared.setProfile(.taxi)
            let timeText = clock.now.formatted(date: .omitted, time: .shortened)
            Announcer.shared.announce(
                .landed(city: itinerary.destination.city, localTimeText: timeText),
                premiumChime: hasPremiumChime
            )
            finishSession(completed: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                // Only stop if we haven't started another leg/session ambience.
                guard self?.stage == .arrived || self == nil else { return }
                CabinAudioEngine.shared.stopAmbience()
            }
        } else {
            stage = .layover
            connectionDeparts = now.addingTimeInterval(itinerary.layoverDuration)
            let minutes = Int(itinerary.layoverDuration / 60)
            Announcer.shared.announce(
                .layover(city: currentLeg.destination.city, minutes: minutes),
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
        finishSession(completed: false)
    }

    // MARK: Strict enforcement

    func handleScenePhase(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .background:
            guard stage == .inFlight else { return }
            let deadline = clock.now.addingTimeInterval(Self.graceDuration)
            graceDeadline = deadline
            // Real-time backup: if ambience keeps the process alive, this fires
            // even in background. Tests rely on `tick()` + the injected clock.
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.stage == .inFlight,
                          let d = self.graceDeadline, self.clock.now >= d else { return }
                    self.divert()
                }
            }
            graceWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.graceDuration + 0.5, execute: work)

        case .active:
            graceWorkItem?.cancel()
            graceWorkItem = nil
            if stage == .inFlight, let deadline = graceDeadline, clock.now > deadline {
                divert()
            } else {
                graceDeadline = nil
            }

        default:
            break
        }
    }

    func divert() {
        guard stage == .inFlight else { return }
        stage = .diverted
        stopEverything()
        finishSession(completed: false)
    }

    /// User bails out intentionally from the in-flight screen.
    func abandonFlight() {
        divert()
    }

    private func stopEverything() {
        Announcer.shared.stop()
        CabinAudioEngine.shared.stopAmbience()
        graceWorkItem?.cancel()
        graceWorkItem = nil
    }

    // MARK: Logbook

    private func finishSession(completed: Bool) {
        timer?.invalidate()
        timer = nil

        // Diverted mid-leg still credits the partial leg; a missed connection
        // credits exactly the legs that landed (layover time isn't focus).
        let partialLeg = stage == .diverted ? min(legElapsed, currentLeg.duration) : 0
        let focusSeconds = completed
            ? itinerary.totalFocusDuration
            : completedFocusSeconds + partialLeg

        let entry = LogbookEntry(
            originCode: itinerary.origin.code,
            destinationCode: itinerary.destination.code,
            connectionCode: itinerary.connection?.code,
            flightNumber: itinerary.primaryFlightNumber,
            seat: seat,
            miles: completedMiles,
            focusSeconds: min(focusSeconds, itinerary.totalFocusDuration),
            completed: completed,
            intentions: intentions,
            intentionsCompleted: Array(repeating: false, count: intentions.count)
        )
        modelContext.insert(entry)
        try? modelContext.save()
        logEntry = entry
    }

    /// Called if the user dismisses the ritual before ripping the pass.
    func cancelBeforeDeparture() {
        timer?.invalidate()
        timer = nil
        stopEverything()
    }

    private func spokenDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 && m > 0 { return "\(h) hours and \(m) minutes" }
        if h > 0 { return h == 1 ? "1 hour" : "\(h) hours" }
        return "\(m) minutes"
    }
}
