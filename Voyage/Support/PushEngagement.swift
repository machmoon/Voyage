import Foundation
import os
import SwiftData
import UIKit
import UserNotifications
import OneSignalFramework

/// OneSignal push, in-app messages and segmentation tags, all optional.
///
/// Shaped on OneSignal's own demo app in OneSignal-iOS-SDK (Modified MIT,
/// tag 5.7.0): `examples/demo/App/App.swift` initialises from
/// `application(_:didFinishLaunchingWithOptions:)` through a
/// `@UIApplicationDelegateAdaptor`, and
/// `examples/demo/App/Services/OneSignalService.swift` funnels every SDK call
/// (`initialize`, `User.addTags`, `Notifications.requestPermission`,
/// `Session.addOutcome`) through one wrapper. Voyage keeps that shape and
/// deviates in three stated ways:
///
/// - No App ID, a placeholder, or the unit-test host leaves the SDK
///   unconfigured, and every call below is a no-op (the RevenueCat rule in
///   `Membership.configure`). An open-source checkout without an ID still
///   builds, runs, and never asks for anything it did not ask for before.
/// - There is one notification prompt in the app, not two. The boarding call
///   (`FlightScheduler.schedule`) always asked for permission; it now asks
///   through `requestPermission`, which is OneSignal's prompt when the SDK is
///   live. OneSignal's prompt is `UNUserNotificationCenter.requestAuthorization`
///   plus `registerForRemoteNotifications`
///   (`iOS_SDK/OneSignalSDK/OneSignalNotifications/NotificationSettings/
///   OneSignalNotificationSettings.m`, `promptForNotifications:`), so iOS
///   still shows its one system dialog, at the same moment, and nothing
///   prompts at launch.
/// - Local notifications keep working unchanged: OneSignal swizzles the
///   notification-center delegate and forwards every non-OneSignal payload to
///   the delegate the app set (`FlightScheduler`), per
///   `Categories/UNUserNotificationCenter+OneSignalNotifications.m`
///   (`onesignalUserNotificationCenter:willPresentNotification:...`).
///
/// Tags are data the app already has, derived from the logbook and the
/// scheduled departure. No name, email, location or free text leaves the
/// device: no intentions, no if-then plan, no declarations.
enum PushEngagement {
    /// Info.plist key carrying the OneSignal App ID. Its value is the
    /// `ONESIGNAL_APP_ID` build setting in `project.yml`.
    static let appIDInfoKey = "OneSignalAppID"

    /// Outcome recorded on every landing, so a campaign's report in OneSignal
    /// shows the flights it led to, not only the opens.
    static let landedOutcome = "flight_landed"

    private struct State {
        var isConfigured = false
        /// The tags last handed to the SDK, so a sync sends only changes.
        var lastSent: [String: String]?
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())
    private static let log = Logger(subsystem: "com.patrickliu.voyage", category: "push")

    static var isConfigured: Bool { state.withLock { $0.isConfigured } }

    // MARK: Pure logic

    /// The usable App ID in an Info.plist dictionary, or nil. OneSignal App
    /// IDs are UUIDs; the committed placeholder and an unexpanded
    /// `$(ONESIGNAL_APP_ID)` are not, so they mean "no ID".
    static func appID(in info: [String: Any]?) -> String? {
        guard let raw = info?[appIDInfoKey] as? String else { return nil }
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard UUID(uuidString: id) != nil else { return nil }
        return id.lowercased()
    }

    /// Every tag Voyage keeps on the OneSignal user, derived from the logbook
    /// and the scheduled departure. A nil value means "remove this tag": a
    /// flight that was boarded or cancelled must leave the segment built on it.
    ///
    /// Timestamps are Unix seconds, the form OneSignal's "time elapsed"
    /// segment filters read; counts are plain integers for its numeric
    /// comparisons.
    static func tags(entries: [LogbookEntry],
                     scheduled: ScheduledFlight?,
                     membership: String,
                     calendar: Calendar = .current) -> [String: String?] {
        let progress = MilesProgress(entries: entries)
        let landed = entries.filter(\.completed)
        var tags: [String: String?] = [
            "tier": progress.tier.rawValue.lowercased(),
            "next_tier": progress.next?.rawValue.lowercased() ?? "none",
            "miles_to_next_tier": String(Int(progress.remaining.rounded(.up))),
            "status_miles": String(Int(progress.statusMiles.rounded(.down))),
            "flights_landed": String(landed.count),
            "streak_days": String(LogbookStats.streak(entries, calendar: calendar).days),
            "voyage_first": membership,
        ]
        tags["last_landing_unix"] = landed.map(\.date).max().map { String(Int($0.timeIntervalSince1970)) }
        tags["study_hour"] = preferredStudyHour(entries: entries, scheduled: scheduled, calendar: calendar).map(String.init)
        tags["next_departure_unix"] = scheduled.map { String(Int($0.departure.timeIntervalSince1970)) }
        tags["gate_closes_unix"] = scheduled.map { String(Int($0.boardingCloses.timeIntervalSince1970)) }
        tags["next_destination"] = scheduled?.destinationCode
        return tags
    }

    /// The local hour this traveler most often departs, from the last 30
    /// departures plus the one scheduled now; the most recent hour wins a tie.
    /// Nil with no history, so no one is put in a study-time segment by guess.
    static func preferredStudyHour(entries: [LogbookEntry],
                                   scheduled: ScheduledFlight?,
                                   calendar: Calendar = .current) -> Int? {
        var departures = entries
            .map { $0.departedAt ?? $0.date }
            .sorted(by: >)
            .prefix(30)
            .map { $0 }
        if let scheduled { departures.insert(scheduled.departure, at: 0) }
        guard !departures.isEmpty else { return nil }
        var counts: [Int: Int] = [:]
        for date in departures { counts[calendar.component(.hour, from: date), default: 0] += 1 }
        let best = counts.values.max() ?? 0
        // `departures` is newest first, so the first hour with the top count
        // is the most recent one.
        return departures.lazy.map { calendar.component(.hour, from: $0) }.first { counts[$0] == best }
    }

    /// What to send given what was sent last: tags to add or change, and tag
    /// keys to remove. The first sync (`previous == nil`) removes every
    /// absent key, clearing whatever an earlier install left on the server.
    static func diff(previous: [String: String]?,
                     next: [String: String?]) -> (set: [String: String], remove: [String]) {
        var set: [String: String] = [:]
        var remove: [String] = []
        for (key, value) in next {
            if let value {
                if previous?[key] != value { set[key] = value }
            } else if previous == nil || previous?[key] != nil {
                remove.append(key)
            }
        }
        return (set, remove.sorted())
    }

    // MARK: SDK

    /// Initialises OneSignal once, from `application(_:didFinishLaunchingWithOptions:)`.
    /// Never prompts: permission is asked where it always was, at scheduling.
    static func configure(launchOptions: [UIApplication.LaunchOptionsKey: Any]?,
                          bundle: Bundle = .main,
                          processInfo: ProcessInfo = .processInfo) {
        guard !isConfigured else { return }
        guard processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        guard let id = appID(in: bundle.infoDictionary) else {
            log.notice("No OneSignal App ID in Info.plist; push campaigns are off for this build.")
            return
        }
        #if DEBUG
        OneSignal.Debug.setLogLevel(.LL_WARN)
        #endif
        OneSignal.initialize(id, withLaunchOptions: launchOptions)
        state.withLock { $0.isConfigured = true }
    }

    /// The app's one notification prompt. OneSignal's when the SDK is live
    /// (so the push subscription is registered with APNs in the same step),
    /// the system's otherwise. The completion runs whether or not iOS shows a
    /// dialog, which the boarding call relies on to schedule itself.
    static func requestPermission(_ completion: @escaping (Bool) -> Void) {
        if isConfigured {
            OneSignal.Notifications.requestPermission({ accepted in completion(accepted) },
                                                      fallbackToSettings: false)
        } else {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                completion(granted)
            }
        }
    }

    /// Recomputes the tags and sends what changed. Called when the app comes
    /// forward, when a flight changes stage, and when a departure is scheduled
    /// or cleared; a no-op without the SDK.
    @MainActor
    static func sync(context: ModelContext, scheduled: ScheduledFlight?) {
        guard isConfigured else { return }
        let entries = (try? context.fetch(FetchDescriptor<LogbookEntry>())) ?? []
        let membership: String
        switch Membership.shared.status {
        case .firstClass: membership = "member"
        case .economy: membership = "economy"
        case .unknown: membership = "unknown"
        }
        let next = tags(entries: entries, scheduled: scheduled, membership: membership)
        let previous = state.withLock { $0.lastSent }
        let change = diff(previous: previous, next: next)
        if !change.set.isEmpty { OneSignal.User.addTags(change.set) }
        if !change.remove.isEmpty { OneSignal.User.removeTags(change.remove) }
        state.withLock { $0.lastSent = next.compactMapValues { $0 } }
    }

    /// Records the `flight_landed` outcome, attributed by OneSignal to a
    /// notification opened in its attribution window.
    static func recordLanding() {
        guard isConfigured else { return }
        OneSignal.Session.addOutcome(landedOutcome)
    }
}

/// OneSignal initialises from the app delegate, as in its demo app
/// (`examples/demo/App/App.swift`, `AppDelegate`).
final class VoyageAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        PushEngagement.configure(launchOptions: launchOptions)
        return true
    }
}
