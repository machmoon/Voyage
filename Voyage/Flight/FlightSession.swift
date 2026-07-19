import Foundation
import SwiftUI
import SwiftData
import Observation

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
    let bookedAt = Date()
    let isPremiumCabin: Bool

    // MARK: Live state

    private(set) var stage: Stage = .preflight
    private(set) var legIndex: Int = 0
    private(set) var legStartDate: Date?
    private(set) var now = Date()
    private(set) var destinationCondition: SkyCondition = .clear
    private(set) var connectionDeparts: Date?
    private(set) var completedMiles: Double = 0
    private(set) var logEntry: LogbookEntry?

    /// Deadline after which backgrounding becomes a diversion.
    private(set) var graceDeadline: Date?

    private var timer: Timer?
    private var graceWorkItem: DispatchWorkItem?
    private var firedEvents: Set<Event> = []
    private let modelContext: ModelContext

    // MARK: Phase timing constants

    static let takeoffRollDuration: TimeInterval = 18
    static let climbEndsAt: TimeInterval = 90
    static let descentDuration: TimeInterval = 180
    static let landingDuration: TimeInterval = 15
    static let graceDuration: TimeInterval = 30
    static let finalCallWindow: TimeInterval = 3 * 60

    init(itinerary: Itinerary, modelContext: ModelContext, isPremiumCabin: Bool) {
        self.itinerary = itinerary
        self.modelContext = modelContext
        self.isPremiumCabin = isPremiumCabin
    }

    // MARK: Derived timing

    var currentLeg: FlightLeg { itinerary.legs[legIndex] }

    var legElapsed: TimeInterval {
        guard let start = legStartDate else { return 0 }
        return max(0, now.timeIntervalSince(start))
    }

    var legRemaining: TimeInterval { max(0, currentLeg.duration - legElapsed) }
    var legProgress: Double { min(1, legElapsed / currentLeg.duration) }

    /// Remaining focus time across all legs (excludes layover).
    var totalRemaining: TimeInterval {
        let future = itinerary.legs.dropFirst(legIndex + 1).reduce(0) { $0 + $1.duration }
        return legRemaining + future
    }

    var phase: LegPhase {
        let e = legElapsed
        let d = currentLeg.duration
        if e < Self.takeoffRollDuration { return .takeoffRoll }
        if e < Self.climbEndsAt { return .climb }
        if e < d - Self.descentDuration { return .cruise }
        if e < d - Self.landingDuration { return .descent }
        return .landing
    }

    /// Flavor altitude for the flight-info pill.
    var altitudeFeet: Int {
        let cruiseAlt = 36_000.0
        switch phase {
        case .takeoffRoll:
            return 0
        case .climb:
            let t = (legElapsed - Self.takeoffRollDuration) / (Self.climbEndsAt - Self.takeoffRollDuration)
            return Int((t * t) * cruiseAlt / 100) * 100
        case .cruise:
            let wobble = sin(legElapsed / 47) * 240
            return Int((cruiseAlt + wobble) / 100) * 100
        case .descent:
            let intoDescent = legElapsed - (currentLeg.duration - Self.descentDuration)
            let t = intoDescent / (Self.descentDuration - Self.landingDuration)
            return max(1_500, Int((1 - t) * cruiseAlt / 100) * 100)
        case .landing:
            let intoLanding = legElapsed - (currentLeg.duration - Self.landingDuration)
            let t = intoLanding / Self.landingDuration
            return max(0, Int((1 - t) * 1_500 / 50) * 50)
        }
    }

    /// Flavor ground speed for the flight-info pill.
    var groundSpeedMph: Int {
        switch phase {
        case .takeoffRoll: return Int(legElapsed / Self.takeoffRollDuration * 170)
        case .climb: return 170 + Int((legElapsed - Self.takeoffRollDuration) / (Self.climbEndsAt - Self.takeoffRollDuration) * 370)
        case .cruise: return 540 + Int(sin(legElapsed / 31) * 12)
        case .descent: return 540 - Int((1 - legRemaining / Self.descentDuration) * 380)
        case .landing: return max(0, Int(legRemaining / Self.landingDuration * 150))
        }
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
        Task { [weak self] in
            guard let self else { return }
            let condition = await WeatherService.destinationCondition(for: itinerary.destination)
            self.destinationCondition = condition
        }
        startLeg()
    }

    /// Called from the layover lounge to board the connecting leg.
    func boardConnection() {
        guard stage == .layover, legIndex + 1 < itinerary.legs.count else { return }
        legIndex += 1
        startLeg()
    }

    private func startLeg() {
        stage = .inFlight
        legStartDate = .now
        now = .now
        firedEvents = []
        CabinAudioEngine.shared.startAmbience(profile: .taxi)
        Announcer.shared.announce(
            .welcomeAboard(
                flightNumber: currentLeg.flightNumber,
                city: currentLeg.destination.city,
                durationText: spokenDuration(currentLeg.duration)
            ),
            premiumChime: isPremiumCabin
        )
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

    private func tick() {
        now = .now
        switch stage {
        case .inFlight:
            fireDueEvents()
            if legElapsed >= currentLeg.duration {
                completeLeg()
            }
        case .layover:
            if isFinalCall {
                fire(.finalCall) {
                    Haptics.warning()
                    Announcer.shared.announce(.finalBoardingCall(city: itinerary.destination.city),
                                              premiumChime: isPremiumCabin)
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

        if e >= 4 {
            fire(.takeoffPower) {
                CabinAudioEngine.shared.setProfile(.takeoffRoll)
                Haptics.softTick()
            }
        }
        if e >= Self.takeoffRollDuration {
            fire(.rotate) {
                CabinAudioEngine.shared.setProfile(.climb)
                Haptics.tap()
            }
        }
        if e >= Self.takeoffRollDuration + 14 {
            fire(.gearUp) {
                CabinAudioEngine.shared.playThunk()
                Haptics.gearThunk()
            }
        }
        if e >= Self.climbEndsAt {
            fire(.cruiseReached) {
                CabinAudioEngine.shared.setProfile(.cruise)
                CabinAudioEngine.shared.playChime(premium: isPremiumCabin)
            }
        }
        if e >= d / 2 {
            fire(.midpoint) {
                Announcer.shared.announce(
                    .midpoint(city: currentLeg.destination.city, altitude: altitudeFeet),
                    premiumChime: isPremiumCabin
                )
            }
        }
        if e >= d - Self.descentDuration {
            fire(.descentStart) {
                CabinAudioEngine.shared.setProfile(.descent)
                Announcer.shared.announce(
                    .descent(city: currentLeg.destination.city,
                             weather: destinationCondition.spokenDescription),
                    premiumChime: isPremiumCabin
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
                Haptics.touchdown()
            }
        }
    }

    // MARK: Leg completion

    private func completeLeg() {
        completedMiles += currentLeg.distanceMiles

        if legIndex == itinerary.legs.count - 1 {
            stage = .arrived
            CabinAudioEngine.shared.setProfile(.taxi)
            let timeText = Date.now.formatted(date: .omitted, time: .shortened)
            Announcer.shared.announce(
                .landed(city: itinerary.destination.city, localTimeText: timeText),
                premiumChime: isPremiumCabin
            )
            finishSession(completed: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                CabinAudioEngine.shared.stopAmbience()
            }
        } else {
            stage = .layover
            connectionDeparts = now.addingTimeInterval(itinerary.layoverDuration)
            let minutes = Int(itinerary.layoverDuration / 60)
            Announcer.shared.announce(
                .layover(city: currentLeg.destination.city, minutes: minutes),
                premiumChime: isPremiumCabin
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
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
            let deadline = Date.now.addingTimeInterval(Self.graceDuration)
            graceDeadline = deadline
            // If ambience keeps the process alive, this fires even in background.
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.stage == .inFlight,
                          let d = self.graceDeadline, Date.now >= d else { return }
                    self.divert()
                }
            }
            graceWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.graceDuration + 0.5, execute: work)

        case .active:
            graceWorkItem?.cancel()
            graceWorkItem = nil
            if stage == .inFlight, let deadline = graceDeadline, Date.now > deadline {
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

        let priorLegsFocus = itinerary.legs.prefix(legIndex).reduce(0) { $0 + $1.duration }
        let focusSeconds = completed
            ? itinerary.totalFocusDuration
            : priorLegsFocus + legElapsed

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
