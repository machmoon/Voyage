import XCTest
@testable import Voyage

final class LogbookPostTests: XCTestCase {
    func testDefaultPostTitleByTimeOfDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let morning = calendar.date(from: DateComponents(year: 2026, month: 7, day: 24, hour: 9))!
        XCTAssertEqual(LogbookStats.defaultPostTitle(at: morning, calendar: calendar), "Morning flight")

        let afternoon = calendar.date(from: DateComponents(year: 2026, month: 7, day: 24, hour: 14))!
        XCTAssertEqual(LogbookStats.defaultPostTitle(at: afternoon, calendar: calendar), "Afternoon flight")

        let evening = calendar.date(from: DateComponents(year: 2026, month: 7, day: 24, hour: 19))!
        XCTAssertEqual(LogbookStats.defaultPostTitle(at: evening, calendar: calendar), "Evening flight")

        let redeye = calendar.date(from: DateComponents(year: 2026, month: 7, day: 24, hour: 2))!
        XCTAssertEqual(LogbookStats.defaultPostTitle(at: redeye, calendar: calendar), "Red-eye flight")
    }

    func testPersonalBestFocusOnRoute() {
        let entry = LogbookEntry(
            originCode: "BOS",
            destinationCode: "SFO",
            flightNumber: "VOY 1",
            seat: "A1",
            miles: 2_600,
            focusSeconds: 3_600,
            completed: true
        )
        let older = LogbookEntry(
            originCode: "BOS",
            destinationCode: "SFO",
            flightNumber: "VOY 1",
            seat: "B2",
            miles: 2_600,
            focusSeconds: 3_000,
            completed: true
        )
        let otherRoute = LogbookEntry(
            originCode: "BOS",
            destinationCode: "LAX",
            flightNumber: "VOY 2",
            seat: "C3",
            miles: 2_600,
            focusSeconds: 9_999,
            completed: true
        )
        XCTAssertTrue(LogbookStats.isPersonalBestFocus(entry, among: [older, otherRoute]))
        XCTAssertFalse(LogbookStats.isPersonalBestFocus(older, among: [entry, otherRoute]))
    }
}
