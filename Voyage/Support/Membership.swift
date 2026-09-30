import Foundation
import Observation
import os
import RevenueCat
import UserNotifications

/// Voyage First: the optional membership sold through RevenueCat (called
/// "First Class" in code from before the name was settled; every
/// user-facing string says Voyage First).
///
/// Shaped on RevenueCat's own SwiftUI samples in purchases-ios (MIT, tag
/// 5.91.0): `Examples/SampleCat/SampleCat/UserViewModel.swift` for the
/// `@MainActor @Observable` model that configures the SDK and follows
/// `Purchases.shared.customerInfoStream`, and
/// `Examples/MagicWeatherSwiftUI/.../MagicWeatherApp.swift` for configuring
/// once at launch with `.storeKit2`. Two deliberate deviations:
///
/// - The samples configure unconditionally and `Purchases.shared` traps when it
///   has not been configured. Here a missing or placeholder key, and the unit
///   test host, leave the SDK unconfigured and every call below becomes a no-op.
///   An open-source checkout without a key must still build and run.
/// - The samples reduce entitlement state to a `Bool`. Voyage keeps three
///   states, because "we could not ask" is not "you did not pay": `.unknown`
///   never locks anything the free app already does, and a failed refresh
///   never demotes a member who was already known to be First Class.
///
/// Free stays free. No existing feature reads this type; premium features and
/// paywall triggers go through `requireFirstClass(from:paywall:)` (see
/// `FirstClassPaywall.swift` and the Membership section of CLAUDE.md).
@MainActor @Observable
final class Membership {
    static let shared = Membership()

    /// The RevenueCat entitlement First Class unlocks.
    nonisolated static let entitlementID = "voyage_first"
    /// Info.plist key carrying the public SDK key. Its value is the
    /// `REVENUECAT_API_KEY` build setting in `project.yml`.
    nonisolated static let apiKeyInfoKey = "RevenueCatAPIKey"

    enum Status: Equatable {
        /// Not known yet: no key, offline with no cached customer, or the first
        /// answer has not arrived. Treated like economy for new premium
        /// features, and never used to lock an existing one.
        case unknown
        case economy
        case firstClass
    }

    /// What a premium feature should do when it is asked for.
    enum Access: Equatable {
        /// First Class is active: go ahead.
        case granted
        /// Not a member (or not known yet) and the SDK is live: show the paywall.
        case offerPaywall
        /// No SDK (no key, or the unit-test host): nothing can be sold, so the
        /// feature simply stays closed and nothing is presented.
        case unavailable
    }

    private(set) var status: Status = .unknown
    /// Set by `-VoyageFirstMember` / `-VoyageFirstFree` for UI captures, the
    /// way `-VoyageEnforceLoyalty` pins loyalty. A forced status ignores the SDK.
    @ObservationIgnored private var forced: Status?
    /// True once `Purchases.configure` has run in this process. Every view
    /// that would touch `Purchases.shared` (paywall, Customer Center) checks it.
    private(set) var isConfigured: Bool

    var isFirstClass: Bool { status == .firstClass }

    @ObservationIgnored private var customerInfoTask: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.patrickliu.voyage", category: "membership")

    /// `configured` exists for tests, which exercise the state logic without
    /// ever configuring the SDK.
    init(configured: Bool = false) {
        isConfigured = configured
    }

    // MARK: Pure logic

    /// The usable public SDK key in an Info.plist dictionary, or nil.
    ///
    /// RevenueCat's public keys are prefixed `appl_` (App Store) or `test_`
    /// (Test Store). Anything else, including the committed placeholder and an
    /// unexpanded `$(REVENUECAT_API_KEY)`, means "no key" rather than a
    /// configure call that fails on every request.
    nonisolated static func apiKey(in info: [String: Any]?) -> String? {
        guard let raw = info?[apiKeyInfoKey] as? String else { return nil }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("appl_") || key.hasPrefix("test_") else { return nil }
        guard key.count > 5, !key.contains("$(") else { return nil }
        return key
    }

    /// Folds a new answer into the current status. `entitlementActive` is nil
    /// when the answer is missing (a failed fetch). A missing answer never
    /// demotes a known member; it only leaves an unknown status unknown.
    nonisolated static func status(after current: Status, entitlementActive: Bool?) -> Status {
        switch entitlementActive {
        case .some(true): return .firstClass
        case .some(false): return .economy
        case .none: return current
        }
    }

    nonisolated static func access(status: Status, isConfigured: Bool) -> Access {
        if status == .firstClass { return .granted }
        return isConfigured ? .offerPaywall : .unavailable
    }

    // MARK: State

    nonisolated static func forcedStatus(arguments: [String]) -> Status? {
        if arguments.contains("-VoyageFirstMember") { return .firstClass }
        if arguments.contains("-VoyageFirstFree") { return .economy }
        return nil
    }

    func record(entitlementActive: Bool?) {
        if let forced { if status != forced { status = forced }; return }
        let next = Self.status(after: status, entitlementActive: entitlementActive)
        if next != status { status = next }
    }

    func apply(_ customerInfo: CustomerInfo) {
        let entitlement = customerInfo.entitlements[Self.entitlementID]
        record(entitlementActive: entitlement?.isActive == true)
        TrialReminder.update(isTrial: entitlement?.isActive == true && entitlement?.periodType == .trial,
                             willRenew: entitlement?.willRenew ?? false,
                             expiresAt: entitlement?.expirationDate)
    }

    /// Whether a premium feature may open, logged with the caller's name so a
    /// trigger can be traced. The SwiftUI wrapper that also raises the paywall
    /// is `requireFirstClass(from:paywall:)`.
    func access(from source: String) -> Access {
        let access = Self.access(status: status, isConfigured: isConfigured)
        log.info("First Class requested from \(source, privacy: .public): \(String(describing: access), privacy: .public)")
        return access
    }

    // MARK: SDK

    /// Restore purchases, for the Settings button non-members see. A no-op
    /// without the SDK. Returns whether Voyage First is active afterwards.
    @discardableResult
    func restore() async -> Bool {
        guard isConfigured else { return false }
        do {
            apply(try await Purchases.shared.restorePurchases())
        } catch {
            log.error("Restore failed: \(error.localizedDescription, privacy: .public)")
        }
        return isFirstClass
    }

    /// Configures RevenueCat once, at launch. Never throws and never blocks:
    /// with no key, or under XCTest (the `XCTestConfigurationFilePath` guard
    /// `WeatherService` and `AppFeedback` use), it logs and returns, and the
    /// app runs exactly as it did before RevenueCat.
    func configure(bundle: Bundle = .main, processInfo: ProcessInfo = .processInfo) {
        guard !isConfigured, !Purchases.isConfigured else { return }
        guard processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        if let forced = Self.forcedStatus(arguments: processInfo.arguments) {
            self.forced = forced
            status = forced
        }
        guard let key = Self.apiKey(in: bundle.infoDictionary) else {
            log.notice("No RevenueCat key in Info.plist; First Class is off for this build.")
            return
        }
        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        Purchases.configure(
            with: Configuration.Builder(withAPIKey: key)
                .with(storeKitVersion: .storeKit2)
                .build()
        )
        isConfigured = true
        // The stream yields the cached CustomerInfo first (if any), then every
        // change: purchases, restores, renewals, expiry. Offline with no cache
        // it yields nothing and the status stays `.unknown`.
        customerInfoTask = Task { @MainActor [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                self?.apply(info)
            }
        }
    }
}

/// Where the paywall may appear. RevenueCat's placement guidance is to hold
/// back in low-consideration states; for Voyage that is anywhere a flight is
/// under way, where a paywall would also break the focus the app exists to
/// protect. So: at booking (preflight: the seat map) and after landing, and
/// never in flight, in the lounge, or on a diversion or missed-connection
/// screen. Home (no session) is fine.
enum FirstClassPaywallGate {
    static func canPresent(stage: FlightSession.Stage?) -> Bool {
        switch stage {
        case .none, .preflight, .arrived: return true
        case .inFlight, .layover, .diverted, .missedConnection: return false
        }
    }
}

/// The trial reminder the Flight Manual promises: while a Voyage First free
/// trial is active and set to renew, a local notification is scheduled two
/// days before it ends; anything else (cancelled, converted, expired)
/// removes it. It never asks for notification permission itself: the
/// scheduler already did, and a denied permission is reported in Home.
enum TrialReminder {
    static let identifier = "voyage-first-trial-reminder"
    static let lead: TimeInterval = 2 * 86_400

    /// When the reminder should fire, or nil for none.
    static func fireDate(isTrial: Bool, willRenew: Bool, expiresAt: Date?, now: Date = .now) -> Date? {
        guard isTrial, willRenew, let expiresAt else { return nil }
        let date = expiresAt.addingTimeInterval(-lead)
        return date > now ? date : nil
    }

    static func update(isTrial: Bool, willRenew: Bool, expiresAt: Date?) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard let date = fireDate(isTrial: isTrial, willRenew: willRenew, expiresAt: expiresAt) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Your Voyage First trial ends in 2 days"
        content.body = "Keep it and nothing changes. To cancel: Settings, Voyage First, Manage."
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }
}
