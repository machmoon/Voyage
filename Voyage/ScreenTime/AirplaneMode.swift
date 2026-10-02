import Foundation
import Observation
import os

/// The Screen Time calls Airplane Mode makes, behind a seam so the flight
/// logic can be tested with a fake and so a build without the Family Controls
/// entitlement compiles none of it.
///
/// The real implementation, `ScreenTimeAppBlocker`, exists only when
/// `VOYAGE_SCREEN_TIME_YES` is set (Debug today, see project.yml). Everywhere
/// else, including the unit-test host, the app gets `UnsupportedAppBlocker`,
/// and Airplane Mode hides itself.
@MainActor
protocol AppBlocking: AnyObject {
    /// The build carries the Screen Time capability at all.
    var isSupported: Bool { get }
    var authorization: AirplaneMode.Authorization { get }
    /// Asks for `.individual` Screen Time authorization. Throws
    /// `AirplaneMode.AuthorizationFailure`.
    func requestAuthorization() async throws
    /// Apps, categories and websites in the saved selection.
    var selectionCount: Int { get }
    /// Whether any shield is up right now, read from the store.
    var restrictionsActive: Bool { get }
    func activateRestrictions()
    func deactivateRestrictions()
    /// Starts the DeviceActivity interval that lowers the shields at
    /// `flight.safetyNetEndsAt` if the app cannot.
    func startSafetyNet(for flight: AirplaneModeFlight, now: Date)
    func stopSafetyNet()
}

/// What a build without Screen Time gets: nothing is supported, nothing is
/// ever raised, and every call is a no-op.
@MainActor
final class UnsupportedAppBlocker: AppBlocking {
    var isSupported: Bool { false }
    var authorization: AirplaneMode.Authorization { .notDetermined }
    func requestAuthorization() async throws {
        throw AirplaneMode.AuthorizationFailure.unavailable("Screen Time is not part of this build.")
    }
    var selectionCount: Int { 0 }
    var restrictionsActive: Bool { false }
    func activateRestrictions() {}
    func deactivateRestrictions() {}
    func startSafetyNet(for flight: AirplaneModeFlight, now: Date) {}
    func stopSafetyNet() {}
}

/// Airplane Mode: during a flight, the apps and websites the traveler picked
/// are blocked with Screen Time shields. It is not the system's airplane
/// mode; Wi-Fi and cellular stay on. FocusFlight names its Screen Time
/// blocking the same way.
///
/// The lifecycle is three calls from `FlightSession`: `takeoff` when the
/// first leg starts (shields up, safety net armed), `connection` when a later
/// leg starts (the shield's destination and landing time move on; the shields
/// stay up through the layover), and `land` from `finishSession`, which every
/// outcome passes through. `cleanUpAtLaunch` catches the one case those
/// cannot: a process that died with the shields up.
///
/// Shaped on Foqos (awaseem/foqos at 4f6864c, MIT): `RequestAuthorizer`
/// (`Foqos/Utils/RequestAuthorizer.swift`) for authorization, `AppBlockerUtil`
/// for the shields, `DeviceActivityCenterUtil.startStrategyTimerActivity`
/// for a one-off interval the monitor extension ends. Foqos keeps those as
/// separate `ObservableObject`s and statics; Voyage folds the app-side state
/// into one `@MainActor @Observable` model, the shape `Membership` already
/// uses, and puts the Screen Time calls behind `AppBlocking`.
@MainActor @Observable
final class AirplaneMode {
    static let shared = AirplaneMode(blocker: AirplaneMode.makeBlocker())

    enum Authorization: Equatable {
        case notDetermined
        case approved
        case denied
    }

    enum AuthorizationFailure: Error, Equatable {
        /// The traveler said no. The feature stays; they can try again.
        case canceled
        /// Screen Time cannot be used here (no entitlement, restricted
        /// device, unsupported simulator). The feature hides itself.
        case unavailable(String)
    }

    @ObservationIgnored private let blocker: any AppBlocking
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let log = Logger(subsystem: "com.patrickliu.voyage", category: "airplaneMode")

    /// Set when authorization failed for a reason that will not go away by
    /// asking again. Lasts for this launch only, so an OS update or a
    /// restriction lifted in Settings brings the feature back.
    private(set) var unavailableReason: String?
    private(set) var authorization: Authorization
    private(set) var selectionCount: Int
    /// Mirrors the store, so the in-flight indicator can observe it.
    private(set) var shieldsUp: Bool

    /// The traveler's on/off switch. On by default: choosing apps is the
    /// opt-in, and nothing is blocked until something is chosen.
    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }

    private static let enabledKey = "voyage.airplaneMode.enabled"

    init(blocker: any AppBlocking, defaults: UserDefaults = VoyageAppGroup.defaults) {
        self.blocker = blocker
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        authorization = blocker.authorization
        selectionCount = blocker.selectionCount
        shieldsUp = blocker.restrictionsActive
    }

    /// The Screen Time build, outside the unit-test host. Tests construct
    /// their own `AirplaneMode` with a fake, and every existing test keeps
    /// running against the no-op blocker, as `Membership` stays unconfigured
    /// under XCTest.
    private static func makeBlocker() -> any AppBlocking {
        #if VOYAGE_SCREEN_TIME_YES
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            return ScreenTimeAppBlocker()
        }
        #endif
        return UnsupportedAppBlocker()
    }

    // MARK: Setup

    /// Whether Settings and onboarding offer Airplane Mode at all.
    var isAvailable: Bool { blocker.isSupported && unavailableReason == nil }

    /// Whether a flight taking off now would block anything.
    var isReady: Bool {
        isAvailable && isEnabled && authorization == .approved && selectionCount > 0
    }

    /// Re-reads authorization, the selection and the store. Call on appear:
    /// Screen Time access can be revoked in Settings while Voyage is closed.
    func refresh() {
        authorization = blocker.authorization
        selectionCount = blocker.selectionCount
        shieldsUp = blocker.restrictionsActive
    }

    /// Returns true when the picker may be shown. Asks only when needed, so
    /// "Choose apps" goes straight to the picker after the first time.
    @discardableResult
    func requestAuthorization() async -> Bool {
        if blocker.authorization == .approved {
            authorization = .approved
            return true
        }
        do {
            try await blocker.requestAuthorization()
            authorization = blocker.authorization == .denied ? .denied : .approved
            return authorization == .approved
        } catch AuthorizationFailure.canceled {
            authorization = blocker.authorization
            return false
        } catch {
            let reason: String
            if case AuthorizationFailure.unavailable(let detail) = error {
                reason = detail
            } else {
                reason = error.localizedDescription
            }
            log.error("Screen Time authorization unavailable: \(reason, privacy: .public)")
            unavailableReason = reason
            return false
        }
    }

    /// The picker saved a new selection.
    func selectionDidChange() {
        selectionCount = blocker.selectionCount
    }

    // MARK: Flight lifecycle

    /// First leg's takeoff. Raises the shields and arms the safety net, or
    /// does nothing when Airplane Mode is not set up.
    func takeoff(_ flight: AirplaneModeFlight, now: Date) {
        refresh()
        guard isReady else { return }
        AirplaneModeFlightStore.save(flight, to: defaults)
        blocker.activateRestrictions()
        blocker.startSafetyNet(for: flight, now: now)
        shieldsUp = blocker.restrictionsActive
        log.info("shields up until \(flight.safetyNetEndsAt, privacy: .public)")
    }

    /// A connecting leg took off. The shields stayed up through the
    /// layover; only what the shield screen says changes.
    func connection(destinationCode: String?, destinationCity: String?, landsAt: Date) {
        guard var flight = AirplaneModeFlightStore.load(from: defaults) else { return }
        flight.destinationCode = destinationCode
        flight.destinationCity = destinationCity
        flight.landsAt = landsAt
        AirplaneModeFlightStore.save(flight, to: defaults)
    }

    /// The flight ended, however it ended. Safe to call when nothing is up.
    func land() {
        let hadFlight = AirplaneModeFlightStore.load(from: defaults) != nil
        guard hadFlight || blocker.restrictionsActive || shieldsUp else { return }
        blocker.deactivateRestrictions()
        blocker.stopSafetyNet()
        AirplaneModeFlightStore.clear(from: defaults)
        shieldsUp = false
        log.info("shields down")
    }

    /// At launch no flight can be in progress (a flight lives in memory, and
    /// `InterruptedFlightRecovery` logs one the process lost), so shields
    /// still up then were left by a process that died mid-flight. Lower them.
    func cleanUpAtLaunch(flightInProgress: Bool = false) {
        guard !flightInProgress else { return }
        land()
    }
}
