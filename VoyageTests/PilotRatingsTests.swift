import XCTest
@testable import Voyage

final class PilotRatingsTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private let epoch = Date(timeIntervalSince1970: 1_780_000_000)

    private func flight(_ index: Int,
                        arrived: Bool = true,
                        hours: Double = 1,
                        to code: String = "JFK",
                        connection: Bool = false) -> LoggedFlight {
        LoggedFlight(endedAt: epoch.addingTimeInterval(Double(index) * 86_400),
                     arrived: arrived,
                     focusSeconds: hours * 3_600,
                     destinationCode: code,
                     hasConnection: connection)
    }

    private func evaluate(_ flights: [LoggedFlight]) -> RatingProgress {
        RatingProgress.evaluate(flights: flights, calendar: calendar)
    }

    func testEmptyLogbookIsStudent() {
        let progress = evaluate([])
        XCTAssertEqual(progress.current, .student)
        XCTAssertEqual(progress.next, .solo)
        XCTAssertEqual(progress.nextRequirements.count, 1)
        XCTAssertEqual(progress.nextRequirements[0].progress, 0)
        XCTAssertEqual(progress.nextRequirements[0].threshold, 3)
    }

    func testSoloAfterThreeLandedFlights() {
        let progress = evaluate([flight(0), flight(1), flight(2)])
        XCTAssertEqual(progress.current, .solo)
        XCTAssertEqual(progress.next, .soloCrossCountry)
    }

    func testThreeDivertedFlightsDoNotEarnSolo() {
        let progress = evaluate([
            flight(0, arrived: false), flight(1, arrived: false), flight(2, arrived: false),
        ])
        XCTAssertEqual(progress.current, .student)
        XCTAssertEqual(progress.nextRequirements[0].progress, 0)
    }

    func testCrossCountryCountsDistinctAirports() {
        let sameAirport = (0..<10).map { flight($0, to: "JFK") }
        XCTAssertEqual(evaluate(sameAirport).current, .solo)
        let airports = evaluate(sameAirport).nextRequirements.first { $0.title == "Airports" }
        XCTAssertEqual(airports?.progress, 1)

        var threeAirports = sameAirport
        threeAirports[1] = flight(1, to: "LAX")
        threeAirports[2] = flight(2, to: "LAX")
        threeAirports[3] = flight(3, to: "ORD")
        let progress = evaluate(threeAirports)
        XCTAssertEqual(progress.current, .soloCrossCountry)
        XCTAssertEqual(progress.next, .privatePilot)
    }

    func testLegacyRowsWithoutScheduleOrDepartureStillCount() {
        // Rows written before the recorder fields existed carry
        // scheduledSeconds == 0 and departedAt == nil. The projection reads
        // neither, so a legacy entry counts like any other.
        let entries = (0..<3).map { index in
            LogbookEntry(date: epoch.addingTimeInterval(Double(index) * 86_400),
                         originCode: "BOS", destinationCode: "JFK",
                         flightNumber: "VOY 100", seat: "C10",
                         miles: 187, focusSeconds: 5_400, completed: true)
        }
        XCTAssertEqual(entries[0].scheduledSeconds, 0)
        XCTAssertNil(entries[0].departedAt)
        let progress = RatingProgress.evaluate(entries: entries, calendar: calendar)
        XCTAssertEqual(progress.current, .solo)
        let time = PilotRatings.Columns(flights: entries.map(LoggedFlight.init(entry:)), calendar: calendar)
        XCTAssertEqual(time.totalSeconds, 16_200, accuracy: 0.001)
        XCTAssertEqual(time.landings, 3)
    }

    func testConnectionSatisfiesLongFlightItem() {
        let base = (0..<10).map { flight($0, hours: 1, to: ["JFK", "LAX", "ORD", "SEA", "MIA"][$0 % 5]) }
        let withoutConnection = evaluate(base)
        XCTAssertEqual(withoutConnection.current, .soloCrossCountry)
        let longItem = withoutConnection.nextRequirements.first { $0.kind == .achieveOnce }
        XCTAssertEqual(longItem?.isSatisfied, false)

        var withConnection = base
        withConnection[4] = flight(4, hours: 1, to: "MIA", connection: true)
        let longSatisfied = evaluate(withConnection).nextRequirements.first { $0.kind == .achieveOnce }
        XCTAssertEqual(longSatisfied?.isSatisfied, true)

        var withLongFlight = base
        withLongFlight[4] = flight(4, hours: 2, to: "MIA")
        let twoHourSatisfied = evaluate(withLongFlight).nextRequirements.first { $0.kind == .achieveOnce }
        XCTAssertEqual(twoHourSatisfied?.isSatisfied, true)
    }

    func testCurrentIsHighestFullySatisfiedRating() {
        // Forty hours and a connection, but only one airport: Solo, not
        // cross-country and not Private, no matter how much time is logged.
        let flights = (0..<40).map { flight($0, hours: 1, to: "JFK", connection: true) }
        let progress = evaluate(flights)
        XCTAssertEqual(progress.current, .solo)
        XCTAssertEqual(progress.next, .soloCrossCountry)

        let privateFlights = (0..<40).map {
            flight($0, hours: 1, to: ["JFK", "LAX", "ORD", "SEA", "MIA"][$0 % 5], connection: $0 == 0)
        }
        let top = evaluate(privateFlights)
        XCTAssertEqual(top.current, .privatePilot)
        XCTAssertNil(top.next)
        XCTAssertTrue(top.nextRequirements.isEmpty)
        XCTAssertEqual(top.summaryLine, "Private pilot")
    }

    func testNextReportsRemainingAmounts() {
        let progress = evaluate([flight(0, hours: 1.5)])
        XCTAssertEqual(progress.current, .student)
        let landings = progress.nextRequirements[0]
        XCTAssertEqual(landings.progressText, "1 of 3 landings")
        XCTAssertEqual(landings.remainingText, "2 more landings")
        XCTAssertEqual(progress.summaryLine, "Student pilot · 1 of 3 landings toward Solo")

        let crossCountry = evaluate((0..<10).map {
            flight($0, hours: 1.25, to: ["JFK", "LAX", "ORD"][$0 % 3])
        })
        XCTAssertEqual(crossCountry.current, .soloCrossCountry)
        let time = crossCountry.nextRequirements.first { $0.kind == .time }
        XCTAssertEqual(time?.progressText, "12h 30m of 40h")
        XCTAssertEqual(time?.remainingText, "27h 30m to go")
        let airports = crossCountry.nextRequirements.first { $0.title == "Airports" }
        XCTAssertEqual(airports?.remainingText, "2 more airports")
        XCTAssertEqual(crossCountry.summaryLine, "Solo cross-country · 12h 30m of 40h toward Private")
    }

    func testRatingsAreMonotonicAsEntriesAreAppended() {
        let flights = (0..<45).map { index in
            flight(index,
                   arrived: index % 4 != 3,
                   hours: index % 5 == 0 ? 2 : 1,
                   to: ["JFK", "LAX", "ORD", "SEA", "MIA", "DEN"][index % 6])
        }
        var previous = PilotRating.student
        for count in 0...flights.count {
            let current = evaluate(Array(flights.prefix(count))).current
            XCTAssertGreaterThanOrEqual(current, previous, "rating fell after \(count) flights")
            previous = current
        }
        XCTAssertEqual(previous, .privatePilot)
    }

    func testHoursTextAndEndorsementLine() {
        XCTAssertEqual(PilotRatings.hoursText(0), "0h")
        XCTAssertEqual(PilotRatings.hoursText(7_800), "2h 10m")
        XCTAssertEqual(PilotRatings.hoursText(144_000), "40h")
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        XCTAssertEqual(PilotRatings.endorsementLine(for: .solo, on: date, calendar: calendar),
                       "Solo endorsement · 14 SEP 2026")
    }

    func testCosmeticTiersMapOntoFlyerTier() {
        XCTAssertEqual(PilotRating.student.cosmeticTier, .member)
        XCTAssertEqual(PilotRating.solo.cosmeticTier, .silver)
        XCTAssertEqual(PilotRating.soloCrossCountry.cosmeticTier, .gold)
        XCTAssertEqual(PilotRating.privatePilot.cosmeticTier, .platinum)
    }
}
