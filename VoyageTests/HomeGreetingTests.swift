import XCTest
@testable import Voyage

final class HomeGreetingTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let suite = "HomeGreetingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testNeverRepeatsThePreviousLaunch() {
        let defaults = freshDefaults()
        var previous = HomeGreeting.next(defaults: defaults)
        // Many draws in a row must never match the immediately preceding one.
        for _ in 0..<500 {
            let line = HomeGreeting.next(defaults: defaults)
            XCTAssertNotEqual(line, previous, "greeting repeated back to back")
            previous = line
        }
    }

    func testEveryLineIsReachable() {
        let defaults = freshDefaults()
        var seen = Set<String>()
        for _ in 0..<2_000 { seen.insert(HomeGreeting.next(defaults: defaults)) }
        XCTAssertEqual(seen, Set(HomeGreeting.lines), "some greeting never appeared")
    }

    func testCopyHasNoEmDashes() {
        for line in HomeGreeting.lines + [HomeGreeting.subtitle] {
            XCTAssertFalse(line.contains("\u{2014}"), "em-dash in \(line)")
        }
    }
}
