import XCTest
@testable import Voyage

final class StudyCoachTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    /// 2026-09-14 12:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_789_387_200)

    private func flight(daysAgo: Int, hour: Int = 18, minutes: Double = 60,
                        outcome: FlightOutcome = .arrived) -> RecordedFlight {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        let departed = calendar.date(byAdding: .hour, value: hour, to: day)!
        return RecordedFlight(endedAt: departed.addingTimeInterval(minutes * 60),
                              departedAt: departed,
                              outcome: outcome,
                              scheduledSeconds: minutes * 60,
                              focusSeconds: minutes * 60)
    }

    private func plan(_ flights: [RecordedFlight]) -> StudyCoach.Plan {
        let report = FlightDataRecorder.report(corpus: FlightCorpus(flights: flights, calendar: calendar))
        return StudyCoach.plan(flights: flights, report: report, calendar: calendar)
    }

    func testTooFewLandedFlightsAsksForMore() {
        let result = plan([flight(daysAgo: 1), flight(daysAgo: 2, outcome: .interrupted)])
        XCTAssertNil(result.suggestedMinutes)
        XCTAssertEqual(result.headline, "Start with a flight under an hour.")
        XCTAssertTrue(result.detail.contains("Land 2 more flights"), result.detail)
    }

    func testMedianLengthOfRecentLandedFlights() {
        let flights = [
            flight(daysAgo: 1, hour: 9, minutes: 50),
            flight(daysAgo: 2, hour: 14, minutes: 55),
            flight(daysAgo: 3, hour: 20, minutes: 85),
            flight(daysAgo: 4, hour: 18, minutes: 240, outcome: .leftEarly),
        ]
        let result = plan(flights)
        XCTAssertEqual(result.suggestedMinutes, 55)
        // Three bands, one flight each: no majority, so no time is suggested.
        XCTAssertNil(result.band)
        XCTAssertEqual(result.headline, "Book about 55m.")
    }

    func testClearMajorityBandIsDescribedNotCompared() {
        let flights = (1...4).map { flight(daysAgo: $0, hour: 18, minutes: 45) }
            + [flight(daysAgo: 5, hour: 10, minutes: 45)]
        let result = plan(flights)
        XCTAssertEqual(result.band, .evening)
        XCTAssertEqual(result.headline, "Book about 45m, between 5pm and 9pm.")
        XCTAssertTrue(result.detail.contains("4 of the 5 with a recorded departure left between 5pm and 9pm."), result.detail)
        XCTAssertFalse(result.detail.contains("more often"), "the plan never makes the recorder's comparison itself")
    }

    func testMethodsLeadWithWhatTheRecorderFound() {
        let bags = Finding(kind: .bags, mode: .comparative, headline: "", detail: "",
                           evidence: [], support: 12, separation: 0.2)
        let report = FlightDataReport(flightsAnalyzed: 12, findings: [bags], flightsUntilReporting: 0)
        let methods = StudyCoach.methods(report: report)
        XCTAssertEqual(methods.first, .specificBags)
        XCTAssertEqual(Set(methods), Set(StudyCoach.Method.allCases))
    }

    func testCopyHasNoEmDashes() {
        let text = StudyCoach.Method.allCases.map { $0.title + $0.body }.joined()
            + LogbookExport.prompt
        XCTAssertFalse(text.contains("\u{2014}"))
    }
}
