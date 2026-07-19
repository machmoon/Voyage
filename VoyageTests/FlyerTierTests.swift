import XCTest
import SwiftData
@testable import Voyage

@MainActor
final class FlyerTierTests: XCTestCase {

    func testTierThresholds() {
        XCTAssertEqual(FlyerTier.tier(forMiles: 0), .member)
        XCTAssertEqual(FlyerTier.tier(forMiles: 4_999), .member)
        XCTAssertEqual(FlyerTier.tier(forMiles: 5_000), .silver)
        XCTAssertEqual(FlyerTier.tier(forMiles: 14_999), .silver)
        XCTAssertEqual(FlyerTier.tier(forMiles: 15_000), .gold)
        XCTAssertEqual(FlyerTier.tier(forMiles: 39_999), .gold)
        XCTAssertEqual(FlyerTier.tier(forMiles: 40_000), .platinum)
        XCTAssertEqual(FlyerTier.tier(forMiles: 100_000), .platinum)
    }

    func testTierOrderingAndNext() {
        XCTAssertLessThan(FlyerTier.member, FlyerTier.silver)
        XCTAssertLessThan(FlyerTier.silver, FlyerTier.gold)
        XCTAssertLessThan(FlyerTier.gold, FlyerTier.platinum)
        XCTAssertEqual(FlyerTier.member.next, .silver)
        XCTAssertEqual(FlyerTier.platinum.next, nil)
    }

    func testTotalMilesSumsAllEntries() throws {
        let entries = [
            makeEntry(miles: 100, completed: true),
            makeEntry(miles: 250, completed: false),
            makeEntry(miles: 50, completed: true),
        ]
        XCTAssertEqual(LogbookStats.totalMiles(entries), 400, accuracy: 0.001)
        XCTAssertEqual(LogbookStats.tier(entries), .member)
    }

    func testStreakCountsConsecutiveCompletedDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!
        let fourDaysAgo = calendar.date(byAdding: .day, value: -4, to: today)!

        let entries = [
            makeEntry(miles: 10, completed: true, date: today),
            makeEntry(miles: 10, completed: true, date: yesterday),
            makeEntry(miles: 10, completed: true, date: twoDaysAgo),
            makeEntry(miles: 10, completed: false, date: fourDaysAgo), // diverted — ignored
            makeEntry(miles: 10, completed: true, date: fourDaysAgo),
        ]
        XCTAssertEqual(LogbookStats.streakDays(entries, calendar: calendar), 3)
    }

    func testStreakAllowsYesterdayWhenNoFlightToday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let entries = [makeEntry(miles: 10, completed: true, date: yesterday)]
        XCTAssertEqual(LogbookStats.streakDays(entries, calendar: calendar), 1)
    }

    func testStreakIsZeroWhenGapBeforeYesterday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.startOfDay(for: Date())
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: today)!

        let entries = [makeEntry(miles: 10, completed: true, date: threeDaysAgo)]
        XCTAssertEqual(LogbookStats.streakDays(entries, calendar: calendar), 0)
    }

    // MARK: Helpers

    private func makeEntry(miles: Double, completed: Bool, date: Date = .now) -> LogbookEntry {
        LogbookEntry(
            date: date,
            originCode: "BOS",
            destinationCode: "JFK",
            flightNumber: "VA 100",
            seat: "12A",
            miles: miles,
            focusSeconds: 7200,
            completed: completed
        )
    }
}
