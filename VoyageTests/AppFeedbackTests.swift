import XCTest
@testable import Voyage

@MainActor
final class AppFeedbackTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    /// A throwaway suite per test — the gate must never be exercised against
    /// the traveler's real defaults.
    override func setUp() {
        super.setUp()
        suiteName = "AppFeedbackTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: Review gate
    //
    // These pass `underTestHarness: false` because the test process itself is
    // always suppressed; the suppression is asserted on its own below.

    func testFirstLaunchIsStampedOnceAndNeverMoves() {
        let install = Date(timeIntervalSince1970: 1_000_000)
        AppFeedback.stampFirstLaunchIfNeeded(defaults: defaults, now: install)
        AppFeedback.stampFirstLaunchIfNeeded(defaults: defaults, now: install.addingTimeInterval(86_400 * 30))
        XCTAssertEqual(defaults.object(forKey: "feedback.firstLaunchDate") as? Date, install)
    }

    func testOnlyRecordedFlightsCount() {
        XCTAssertEqual(AppFeedback.completedFlightCount(defaults: defaults), 0)
        AppFeedback.recordCompletedFlight(defaults: defaults)
        AppFeedback.recordCompletedFlight(defaults: defaults)
        XCTAssertEqual(AppFeedback.completedFlightCount(defaults: defaults), 2)
    }

    func testDoesNotAskBeforeSevenDays() {
        let install = Date(timeIntervalSince1970: 1_000_000)
        prepare(installedAt: install, flights: 5)
        XCTAssertFalse(gate(now: install.addingTimeInterval(days: 6.9)))
    }

    func testDoesNotAskWithTooFewFlights() {
        let install = Date(timeIntervalSince1970: 1_000_000)
        prepare(installedAt: install, flights: 2)
        XCTAssertFalse(gate(now: install.addingTimeInterval(days: 40)))
    }

    func testDoesNotAskTwiceForTheSameVersion() {
        let install = Date(timeIntervalSince1970: 1_000_000)
        prepare(installedAt: install, flights: 9)
        AppFeedback.markReviewRequested(defaults: defaults, version: "1.0")

        XCTAssertFalse(gate(now: install.addingTimeInterval(days: 40)))
        // A new build is a new chance to ask.
        XCTAssertTrue(gate(version: "1.1", now: install.addingTimeInterval(days: 40)))
    }

    func testAsksOnceBothThresholdsAreMet() {
        let install = Date(timeIntervalSince1970: 1_000_000)
        prepare(installedAt: install, flights: 3)
        XCTAssertTrue(gate(now: install.addingTimeInterval(days: 7)))
    }

    func testNeverAsksWithoutAFirstLaunchDate() {
        AppFeedback.recordCompletedFlight(defaults: defaults)
        AppFeedback.recordCompletedFlight(defaults: defaults)
        AppFeedback.recordCompletedFlight(defaults: defaults)
        XCTAssertFalse(gate(now: Date(timeIntervalSince1970: 9_000_000)))
    }

    func testTestLaunchArgumentsSuppressTheProductionGate() {
        // The test runner always sets XCTestConfigurationFilePath, so the
        // no-argument entry point must refuse regardless of stored state.
        prepare(installedAt: Date(timeIntervalSince1970: 0), flights: 99)
        XCTAssertFalse(AppFeedback.shouldRequestReview(defaults: defaults, version: "1.0", now: .now))
    }

    // MARK: Issue URL

    func testIssueURLPercentEncodesNewlinesAmpersandsAndEmoji() throws {
        let message = "Wing & window\nvanished mid-cruise ✈️"
        let url = try XCTUnwrap(AppFeedback.issueURL(
            kind: .broke,
            message: message,
            environment: "---\nVoyage 1.0 (7)"
        ))
        let raw = url.absoluteString

        XCTAssertTrue(raw.hasPrefix("https://github.com/machmoon/Voyage/issues/new?"))
        // The body must survive as one query item: no bare &, newline or space.
        let body = try XCTUnwrap(queryValue(named: "body", in: raw))
        XCTAssertFalse(body.contains("\n"))
        XCTAssertFalse(body.contains(" "))
        XCTAssertTrue(body.contains("%26"))   // &
        XCTAssertTrue(body.contains("%0A"))   // newline
        XCTAssertTrue(body.contains("%E2%9C%88"))  // ✈️

        XCTAssertEqual(body.removingPercentEncoding, "\(message)\n\n---\nVoyage 1.0 (7)")
    }

    func testIssueURLCarriesKindLabelAndSummaryTitle() throws {
        let url = try XCTUnwrap(AppFeedback.issueURL(
            kind: .idea,
            message: "Let me pick the cabin crew\nand the meal service",
            environment: "iOS 18.0"
        ))
        let raw = url.absoluteString
        XCTAssertEqual(queryValue(named: "labels", in: raw)?.removingPercentEncoding, "enhancement")
        XCTAssertEqual(queryValue(named: "title", in: raw)?.removingPercentEncoding,
                       "Idea: Let me pick the cabin crew")
    }

    func testEmptyMessageFallsBackToTheKindTitle() throws {
        let url = try XCTUnwrap(AppFeedback.issueURL(kind: .loved, message: "  ", environment: "iOS 18.0"))
        let raw = url.absoluteString
        XCTAssertEqual(queryValue(named: "title", in: raw)?.removingPercentEncoding, "Praise: Something I loved")
        XCTAssertEqual(queryValue(named: "body", in: raw)?.removingPercentEncoding, "iOS 18.0")
    }

    func testEnvironmentFooterListsVersionSystemAndDevice() {
        let footer = AppFeedback.environmentFooter(
            version: "1.2", build: "34", systemVersion: "18.1", device: "iPhone16,2"
        )
        XCTAssertTrue(footer.contains("Voyage 1.2 (34)"))
        XCTAssertTrue(footer.contains("iOS 18.1"))
        XCTAssertTrue(footer.contains("iPhone16,2"))
    }

    // MARK: Helpers

    private func prepare(installedAt: Date, flights: Int) {
        AppFeedback.stampFirstLaunchIfNeeded(defaults: defaults, now: installedAt)
        for _ in 0..<flights { AppFeedback.recordCompletedFlight(defaults: defaults) }
    }

    private func gate(version: String = "1.0", now: Date) -> Bool {
        AppFeedback.shouldRequestReview(defaults: defaults, version: version, now: now, underTestHarness: false)
    }

    private func queryValue(named name: String, in url: String) -> String? {
        guard let query = url.split(separator: "?", maxSplits: 1).last else { return nil }
        return query
            .split(separator: "&")
            .first { $0.hasPrefix("\(name)=") }
            .map { String($0.dropFirst(name.count + 1)) }
    }
}

private extension Date {
    func addingTimeInterval(days: Double) -> Date {
        addingTimeInterval(days * 86_400)
    }
}
