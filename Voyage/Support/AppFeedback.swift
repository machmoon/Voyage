import Foundation

/// Two ways a traveler can talk back: the App Store review sheet (asked at most
/// once per version, and only of people who have actually flown) and a written
/// note that becomes a GitHub issue they post themselves.
///
/// Everything here is a pure function of an injected `UserDefaults` + `Date` so
/// the gate can be tested without waiting seven days or polluting the real
/// defaults suite.
@MainActor
enum AppFeedback {

    // MARK: Storage

    private enum Key {
        static let firstLaunch = "feedback.firstLaunchDate"
        static let completedFlights = "feedback.completedFlightCount"
        static let reviewRequestedVersion = "feedback.reviewRequestedVersion"
    }

    /// iOS silently drops `requestReview` after roughly three prompts a year, so
    /// every spend has to land on someone who already likes the app.
    static let minimumDaysSinceFirstLaunch = 7
    static let minimumCompletedFlights = 3

    // MARK: Signals

    /// Records the install date once and never moves it, so the seven-day clock
    /// survives updates. Cheap enough to call on every launch.
    static func stampFirstLaunchIfNeeded(defaults: UserDefaults = .standard, now: Date = .now) {
        guard defaults.object(forKey: Key.firstLaunch) == nil else { return }
        defaults.set(now, forKey: Key.firstLaunch)
    }

    /// Only flights that reach the logbook count — a diversion or a missed
    /// connection is the worst possible moment to ask for five stars.
    static func recordCompletedFlight(defaults: UserDefaults = .standard) {
        defaults.set(completedFlightCount(defaults: defaults) + 1, forKey: Key.completedFlights)
    }

    static func completedFlightCount(defaults: UserDefaults = .standard) -> Int {
        defaults.integer(forKey: Key.completedFlights)
    }

    // MARK: Review gate

    static func shouldRequestReview(
        defaults: UserDefaults = .standard,
        version: String = appVersion,
        now: Date = .now,
        underTestHarness: Bool = isRunningUnderTestLaunchArguments
    ) -> Bool {
        // A prompt during a UI test run would block the test on a system alert.
        guard !underTestHarness else { return false }
        guard let firstLaunch = defaults.object(forKey: Key.firstLaunch) as? Date else { return false }

        let daysInstalled = now.timeIntervalSince(firstLaunch) / 86_400
        guard daysInstalled >= Double(minimumDaysSinceFirstLaunch) else { return false }
        guard completedFlightCount(defaults: defaults) >= minimumCompletedFlights else { return false }
        return defaults.string(forKey: Key.reviewRequestedVersion) != version
    }

    /// One ask per shipped version, whether or not iOS actually drew the sheet —
    /// `requestReview` never reports back, so the only safe assumption is that
    /// it did.
    static func markReviewRequested(defaults: UserDefaults = .standard, version: String = appVersion) {
        defaults.set(version, forKey: Key.reviewRequestedVersion)
    }

    /// Voyage's own launch flags all start with `-Voyage`; unlike onboarding's
    /// deliberate allow-list, erring toward silence here costs nothing.
    nonisolated static var isRunningUnderTestLaunchArguments: Bool {
        let info = ProcessInfo.processInfo
        if info.environment["XCTestConfigurationFilePath"] != nil { return true }
        return info.arguments.contains { $0.hasPrefix("-Voyage") }
    }

    // MARK: Written feedback

    enum FeedbackKind: String, CaseIterable, Identifiable {
        case broke, idea, loved

        var id: String { rawValue }

        /// Cabin voice, not bug-tracker voice.
        var title: String {
            switch self {
            case .broke: return "Something broke"
            case .idea: return "I have an idea"
            case .loved: return "Something I loved"
            }
        }

        var prompt: String {
            switch self {
            case .broke: return "What happened, and what were you doing when it did?"
            case .idea: return "What would you like Voyage to do?"
            case .loved: return "What worked? It helps to know what to protect."
            }
        }

        /// GitHub labels the maintainer already sorts by.
        var issueLabel: String {
            switch self {
            case .broke: return "bug"
            case .idea: return "enhancement"
            case .loved: return "feedback"
            }
        }

        var issueTitlePrefix: String {
            switch self {
            case .broke: return "Bug"
            case .idea: return "Idea"
            case .loved: return "Praise"
            }
        }
    }

    static let repository = "machmoon/Voyage"

    nonisolated static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    nonisolated static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    /// Hardware identifier ("iPhone16,2"). Under the simulator `uname` reports
    /// the host arch, so the simulated model is read from the environment first.
    nonisolated static var deviceModel: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(simulated) (Simulator)"
        }
        var info = utsname()
        uname(&info)
        // `machine` is a fixed-size C array, which Swift surfaces as a tuple of
        // CChar; mirroring it avoids an exclusivity violation on the raw pointer.
        let machine = Mirror(reflecting: info.machine).children
            .compactMap { $0.value as? CChar }
            .prefix { $0 != 0 }
            .map { String(UnicodeScalar(UInt8($0))) }
            .joined()
        return machine.isEmpty ? "unknown" : machine
    }

    /// The footer every issue carries so a report doesn't need a follow-up
    /// round trip to find out what it was filed against.
    static func environmentFooter(
        version: String = appVersion,
        build: String = buildNumber,
        systemVersion: String,
        device: String = deviceModel
    ) -> String {
        """
        ---
        Voyage \(version) (\(build))
        iOS \(systemVersion)
        \(device)
        """
    }

    static func issueBody(message: String, environment: String) -> String {
        let note = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return note.isEmpty ? environment : "\(note)\n\n\(environment)"
    }

    /// Builds a prefilled "new issue" URL. Voyage never posts on anyone's
    /// behalf — no token ships in the app — so the browser opens GitHub with the
    /// form filled in and the traveler presses Submit under their own account.
    static func issueURL(kind: FeedbackKind, message: String, environment: String) -> URL? {
        let title = "\(kind.issueTitlePrefix): \(summaryLine(from: message, fallback: kind.title))"
        let query = [
            "title=\(escaped(title))",
            "body=\(escaped(issueBody(message: message, environment: environment)))",
            "labels=\(escaped(kind.issueLabel))"
        ].joined(separator: "&")
        return URL(string: "https://github.com/\(repository)/issues/new?\(query)")
    }

    /// First line of the note, clipped, so the issue list stays skimmable.
    private static func summaryLine(from message: String, fallback: String) -> String {
        let firstLine = message
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !firstLine.isEmpty else { return fallback }
        return firstLine.count <= 72 ? firstLine : String(firstLine.prefix(69)) + "…"
    }

    /// RFC 3986 unreserved set only. `CharacterSet.urlQueryAllowed` leaves `&`,
    /// `=` and `+` intact, which would truncate a body at the first ampersand.
    private static let unreserved = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func escaped(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }
}
