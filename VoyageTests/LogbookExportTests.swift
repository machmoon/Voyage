import XCTest
@testable import Voyage

final class LogbookExportTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    /// 2026-09-14 12:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_789_387_200)

    private func date(daysAgo: Int, hour: Int = 18) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        return calendar.date(byAdding: .hour, value: hour, to: day)!
    }

    private func entry(daysAgo: Int,
                       completed: Bool = true,
                       focus: TimeInterval = 5_400,
                       scheduled: TimeInterval = 0,
                       departed: Bool = false,
                       to code: String = "JFK") -> LogbookEntry {
        LogbookEntry(date: date(daysAgo: daysAgo),
                     originCode: "BOS", destinationCode: code,
                     flightNumber: "VOY 100", seat: "C10",
                     miles: 187, focusSeconds: focus, completed: completed,
                     intentions: ["Read chapter 4", "Problem set"],
                     intentionsCompleted: [true, false],
                     scheduledSeconds: scheduled,
                     departedAt: departed ? date(daysAgo: daysAgo, hour: 17) : nil,
                     outcome: completed ? .arrived : .interrupted)
    }

    func testPromptComesFirst() {
        let text = LogbookExport.markdown(entries: [], now: now, calendar: calendar)
        XCTAssertTrue(text.hasPrefix(LogbookExport.prompt))
        let promptRange = text.range(of: "Give three plain observations")!
        let summaryRange = text.range(of: "## Summary")!
        XCTAssertLessThan(promptRange.lowerBound, summaryRange.lowerBound)
        XCTAssertFalse(text.contains("\u{2014}"), "no em-dashes in the export")
    }

    func testLegacyRowsRender() {
        // A row from before the recorder fields: no schedule, no departure
        // stamp, no outcome. It still renders as a landed flight with a
        // blank planned column.
        let text = LogbookExport.markdown(entries: [entry(daysAgo: 3)], now: now, calendar: calendar)
        XCTAssertTrue(text.contains("- Flights: 1, landed 1 (100%)"))
        XCTAssertTrue(text.contains("- Departures by band: not recorded"))
        XCTAssertTrue(text.contains("- Bags checked: 2, claimed: 1 (50%)"))
        XCTAssertTrue(text.contains("2026-09-11, BOS-JFK, , 90, landed, 1/2, C10"))
    }

    func testSummaryCountsOnlyTheLastNinetyDays() {
        let entries = [
            entry(daysAgo: 1, scheduled: 5_400, departed: true),
            entry(daysAgo: 8, completed: false, focus: 1_200, scheduled: 5_400, departed: true),
            entry(daysAgo: 120, scheduled: 5_400, departed: true),
        ]
        let text = LogbookExport.markdown(entries: entries, now: now, calendar: calendar)
        XCTAssertTrue(text.contains("- Flights: 2, landed 1 (50%)"))
        XCTAssertTrue(text.contains("- Planned minutes: 180; completed: 110 (61%)"))
        XCTAssertTrue(text.contains("- Departures by band: 05 to 09: 0, 09 to 13: 0, 13 to 17: 0, 17 to 21: 2, 21 to 05: 0"))
        XCTAssertTrue(text.contains("longest gap: 7 days"))
        // The CSV section is not windowed, only capped.
        XCTAssertTrue(text.contains("2026-05-17, BOS-JFK"))
    }

    func testRecentFlightsAreCappedAtTwentyNewestFirst() {
        let entries = (0..<25).map { entry(daysAgo: $0) }
        let text = LogbookExport.markdown(entries: entries.shuffled(), now: now, calendar: calendar)
        let csv = text.components(separatedBy: "## Recent flights\n")[1]
        let rows = csv.split(separator: "\n").dropFirst()
        XCTAssertEqual(rows.count, 20)
        XCTAssertTrue(rows.first!.hasPrefix("2026-09-14"))
        XCTAssertTrue(rows.last!.hasPrefix("2026-08-26"))
    }

    func testFindingsCarryIntervals() {
        // Twelve flights with a departure stamp: evening flights always land,
        // the rest never do, which the recorder reports with its intervals.
        let flights = (0..<12).map { index -> RecordedFlight in
            let evening = index < 6
            return RecordedFlight(endedAt: date(daysAgo: index, hour: evening ? 19 : 10),
                                  departedAt: date(daysAgo: index, hour: evening ? 18 : 9),
                                  outcome: evening ? .arrived : .interrupted,
                                  scheduledSeconds: 3_600,
                                  focusSeconds: evening ? 3_600 : 600)
        }
        let text = LogbookExport.findings(flights: flights, calendar: calendar)
        XCTAssertTrue(text.contains("## What the recorder found (95% confidence)"))
        XCTAssertTrue(text.contains("- Departure time:"), text)
        XCTAssertTrue(text.contains("6/6, 95% "), text)
        XCTAssertTrue(text.contains(" to 1.00"), text)
    }

    func testRecorderSilenceIsStated() {
        let text = LogbookExport.findings(flights: [], calendar: calendar)
        XCTAssertTrue(text.contains("Not reporting yet: 12 more flights needed."))
    }
}
