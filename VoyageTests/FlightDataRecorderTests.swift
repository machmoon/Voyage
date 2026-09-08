import XCTest
@testable import Voyage

/// The recorder's contract is as much about what it refuses to say as what
/// it says, so the silence cases are tested as hard as the findings.
final class FlightDataRecorderTests: XCTestCase {

    // MARK: Calendars

    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    private var newYork: Calendar { calendar("America/New_York") }
    private var tokyo: Calendar { calendar("Asia/Tokyo") }

    private func date(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return calendar.date(from: components)!
    }

    // MARK: Builders

    private func flight(departing departure: Date? = nil,
                        outcome: FlightOutcome,
                        scheduled: TimeInterval? = nil,
                        endedAt: Date? = nil,
                        bags: [(label: String, claimed: Bool)] = []) -> RecordedFlight {
        RecordedFlight(
            endedAt: endedAt ?? (departure ?? Date(timeIntervalSince1970: 0)).addingTimeInterval(3600),
            departedAt: departure,
            outcome: outcome,
            scheduledSeconds: scheduled,
            focusSeconds: scheduled ?? 0,
            bags: bags
        )
    }

    private func repeated(_ count: Int, _ make: (Int) -> RecordedFlight) -> [RecordedFlight] {
        (0..<count).map(make)
    }

    // MARK: Wilson score interval

    /// The port has to agree with the source it came from. reddit's
    /// `_confidence(1, 0)` at z = 1.281551565545 is 1/(1 + z*z) because the
    /// left and right terms cancel exactly at p = 1, n = 1.
    func testWilsonLowerBoundMatchesRedditConfidenceSort() {
        let z = 1.281551565545
        let interval = RateInterval(successes: 1, trials: 1, z: z)
        XCTAssertEqual(interval.lower, 1.0 / (1.0 + z * z), accuracy: 1e-9)
    }

    func testWilsonIntervalIsSymmetricAboutAPerfectSplit() {
        let perfect = RateInterval(successes: 6, trials: 6)
        let empty = RateInterval(successes: 0, trials: 6)
        XCTAssertEqual(perfect.lower, 0.6096, accuracy: 1e-4)
        XCTAssertEqual(empty.upper, 0.3904, accuracy: 1e-4)
        XCTAssertEqual(perfect.lower, 1 - empty.upper, accuracy: 1e-9)
    }

    func testWilsonIntervalNarrowsWithSampleSize() {
        let small = RateInterval(successes: 4, trials: 5)
        let large = RateInterval(successes: 40, trials: 50)
        XCTAssertEqual(small.rate, large.rate, accuracy: 1e-9)
        XCTAssertGreaterThan(small.upper - small.lower, large.upper - large.lower)
    }

    func testEmptyIntervalIsZeroWidthAndDoesNotDivideByZero() {
        let none = RateInterval(successes: 0, trials: 0)
        XCTAssertEqual(none.lower, 0)
        XCTAssertEqual(none.upper, 0)
        XCTAssertEqual(none.rate, 0)
    }

    func testSeparationIsZeroWhenIntervalsOverlap() {
        let a = RateInterval(successes: 5, trials: 6)
        let b = RateInterval(successes: 4, trials: 6)
        XCTAssertEqual(a.separation(above: b), 0)
        XCTAssertEqual(b.separation(above: a), 0)
    }

    /// Four is the mechanical floor claimed in `minimumGroup`'s comment, and
    /// three is below it. If this ever changes the comment is wrong.
    func testFourIsTheSmallestGroupThatCanSeparateAtAll() {
        XCTAssertGreaterThan(
            RateInterval(successes: 4, trials: 4).separation(above: RateInterval(successes: 0, trials: 4)),
            0
        )
        XCTAssertEqual(
            RateInterval(successes: 3, trials: 3).separation(above: RateInterval(successes: 0, trials: 3)),
            0
        )
    }

    // MARK: Silence

    func testRecorderSaysNothingBelowTheFlightMinimum() {
        let flights = repeated(FlightDataRecorder.minimumFlights - 1) { _ in
            flight(departing: date(newYork, 2026, 4, 6, 19), outcome: .arrived, scheduled: 1800)
        }
        let report = FlightDataRecorder.report(corpus: FlightCorpus(flights: flights, calendar: newYork))

        XCTAssertFalse(report.isReporting)
        XCTAssertTrue(report.findings.isEmpty)
        XCTAssertEqual(report.flightsAnalyzed, 11)
        XCTAssertEqual(report.flightsUntilReporting, 1)
    }

    func testEmptyLogbookReportsTheFullDistanceToTheMinimum() {
        let report = FlightDataRecorder.report(corpus: FlightCorpus(flights: [], calendar: newYork))
        XCTAssertEqual(report.flightsUntilReporting, FlightDataRecorder.minimumFlights)
        XCTAssertTrue(report.findings.isEmpty)
    }

    /// Exactly at the threshold the recorder starts reporting, and with a
    /// perfectly uniform logbook it still finds nothing. Reporting and
    /// having something to report are separate states.
    func testAtTheThresholdWithIdenticalFlightsItReportsAndFindsNothing() {
        let flights = repeated(FlightDataRecorder.minimumFlights) { index in
            flight(departing: date(newYork, 2026, 4, 6, 19).addingTimeInterval(Double(index) * 86_400),
                   outcome: .arrived,
                   scheduled: 3600)
        }
        let report = FlightDataRecorder.report(corpus: FlightCorpus(flights: flights, calendar: newYork))

        XCTAssertTrue(report.isReporting)
        XCTAssertEqual(report.flightsUntilReporting, 0)
        XCTAssertEqual(report.flightsAnalyzed, 12)
        XCTAssertTrue(report.findings.isEmpty, "A logbook with no variation cannot support a finding")
    }

    /// The same shape of difference that fires at six a side must stay
    /// silent at five, or the group minimum is not doing anything.
    func testAGapThatFiresAtSixASideIsSilentAtFive() {
        func corpus(perSide: Int) -> FlightCorpus {
            let evening = repeated(perSide) { index in
                flight(departing: date(newYork, 2026, 4, 6, 19).addingTimeInterval(Double(index) * 86_400),
                       outcome: .arrived)
            }
            let late = repeated(perSide) { index in
                flight(departing: date(newYork, 2026, 4, 6, 23).addingTimeInterval(Double(index) * 86_400),
                       outcome: .interrupted)
            }
            // Padding keeps the corpus over the flight minimum so the only
            // thing under test is the per-group gate.
            let padding = repeated(6) { index in
                flight(departing: date(newYork, 2026, 4, 6, 10).addingTimeInterval(Double(index) * 86_400),
                       outcome: index.isMultiple(of: 2) ? .arrived : .leftEarly)
            }
            return FlightCorpus(flights: evening + late + padding, calendar: newYork)
        }

        let fiveASide = FlightDataRecorder.report(corpus: corpus(perSide: 5))
        XCTAssertNil(fiveASide.findings.first { $0.kind == .departureTime })

        let sixASide = FlightDataRecorder.report(corpus: corpus(perSide: 6))
        XCTAssertNotNil(sixASide.findings.first { $0.kind == .departureTime })
    }

    // MARK: Departure time

    func testDepartureTimeFindingNamesTheBandThatLands() throws {
        let evening = repeated(8) { index in
            flight(departing: date(newYork, 2026, 4, 6, 19).addingTimeInterval(Double(index) * 86_400),
                   outcome: .arrived)
        }
        let late = repeated(8) { index in
            flight(departing: date(newYork, 2026, 4, 6, 23).addingTimeInterval(Double(index) * 86_400),
                   outcome: .interrupted)
        }
        let report = FlightDataRecorder.report(corpus: FlightCorpus(flights: evening + late, calendar: newYork))

        let finding = try XCTUnwrap(report.findings.first { $0.kind == .departureTime })
        XCTAssertEqual(finding.mode, .comparative)
        XCTAssertTrue(finding.headline.contains("between 5pm and 9pm"), finding.headline)
        XCTAssertTrue(finding.detail.contains("8 of 8"), finding.detail)
        XCTAssertEqual(finding.evidence.count, 2)
        XCTAssertEqual(finding.evidence.first { $0.isSubject }?.label, "17 to 21")
        XCTAssertGreaterThan(finding.separation, 0)
    }

    /// Rows written before `departedAt` existed have no hour to bucket by.
    /// They are dropped from the time-of-day work rather than guessed at
    /// from the arrival timestamp.
    func testFlightsWithNoRecordedDepartureAreExcludedFromTimeOfDayWork() {
        let legacy = repeated(20) { index in
            flight(departing: nil,
                   outcome: index.isMultiple(of: 2) ? .arrived : .interrupted,
                   endedAt: date(newYork, 2026, 4, 6, 19).addingTimeInterval(Double(index) * 86_400))
        }
        let corpus = FlightCorpus(flights: legacy, calendar: newYork)

        XCTAssertEqual(corpus.timestamped.count, 0)
        XCTAssertNil(FlightDataRecorder.report(corpus: corpus).findings.first { $0.kind == .departureTime })
        XCTAssertNil(FlightDataRecorder.report(corpus: corpus).findings.first { $0.kind == .weekPattern })
    }

    // MARK: Time zones and DST

    /// The same instants, read in two time zones, are two different stories
    /// about someone's day. The recorder must tell the one the student
    /// actually lived, which is why the calendar is injected.
    func testTheSameInstantsBucketDifferentlyInDifferentTimeZones() throws {
        let flights = repeated(8) { index in
            flight(departing: date(newYork, 2026, 4, 6, 19).addingTimeInterval(Double(index) * 86_400),
                   outcome: .arrived)
        } + repeated(8) { index in
            flight(departing: date(newYork, 2026, 4, 6, 9).addingTimeInterval(Double(index) * 86_400),
                   outcome: .interrupted)
        }

        let atHome = FlightDataRecorder.report(corpus: FlightCorpus(flights: flights, calendar: newYork))
        let abroad = FlightDataRecorder.report(corpus: FlightCorpus(flights: flights, calendar: tokyo))

        let home = try XCTUnwrap(atHome.findings.first { $0.kind == .departureTime })
        let away = try XCTUnwrap(abroad.findings.first { $0.kind == .departureTime })

        XCTAssertTrue(home.headline.contains("between 5pm and 9pm"), home.headline)
        // 19:00 in New York is 08:00 the next morning in Tokyo.
        XCTAssertTrue(away.headline.contains("before 9am"), away.headline)
    }

    /// Spring forward moves the UTC offset, not the student's evening. Two
    /// 7pm departures either side of the 2026 US transition have to land in
    /// the same band despite being an hour apart in absolute terms.
    func testDaylightSavingDoesNotMoveAFlightBetweenBands() {
        let calendar = newYork
        let beforeShift = date(calendar, 2026, 3, 1, 19)   // EST, UTC-5
        let afterShift = date(calendar, 2026, 3, 15, 19)   // EDT, UTC-4

        XCTAssertNotEqual(calendar.timeZone.secondsFromGMT(for: beforeShift),
                          calendar.timeZone.secondsFromGMT(for: afterShift),
                          "This test is worthless if the dates do not straddle the transition")

        let corpus = FlightCorpus(
            flights: [flight(departing: beforeShift, outcome: .arrived),
                      flight(departing: afterShift, outcome: .arrived)],
            calendar: calendar
        )

        XCTAssertEqual(corpus.departureHour(corpus.flights[0]), 19)
        XCTAssertEqual(corpus.departureHour(corpus.flights[1]), 19)
        XCTAssertEqual(DepartureBand(hour: 19), .evening)
    }

    func testDepartureBandsCoverEveryHourOfTheDay() {
        for hour in 0..<24 {
            XCTAssertNotNil(DepartureBand(hour: hour).label)
        }
        XCTAssertEqual(DepartureBand(hour: 0), .late)
        XCTAssertEqual(DepartureBand(hour: 4), .late)
        XCTAssertEqual(DepartureBand(hour: 5), .early)
        XCTAssertEqual(DepartureBand(hour: 21), .late)
    }

    // MARK: Block time

    /// The useful answer is a ceiling, so the detector reports the shortest
    /// split point at which the two sides separate, not the largest gap.
    func testBlockTimeReportsTheShortestSplitThatSeparates() throws {
        let shortHops = repeated(6) { _ in flight(outcome: .arrived, scheduled: 30 * 60) }
        let mediumHops = repeated(6) { _ in flight(outcome: .arrived, scheduled: 60 * 60) }
        let longHauls = repeated(6) { _ in flight(outcome: .interrupted, scheduled: 180 * 60) }
        let report = FlightDataRecorder.report(
            corpus: FlightCorpus(flights: shortHops + mediumHops + longHauls, calendar: newYork)
        )

        let finding = try XCTUnwrap(report.findings.first { $0.kind == .blockTime })
        // 45m does not separate (12/12 landed against 6/12), 1h 30m does.
        XCTAssertTrue(finding.headline.contains("1h 30m"), finding.headline)
        XCTAssertTrue(finding.detail.contains("12 of 12"), finding.detail)
    }

    func testBlockTimeIgnoresRowsWithNoRecordedSchedule() {
        let legacy = repeated(16) { index in
            flight(outcome: index < 8 ? .arrived : .interrupted, scheduled: nil)
        }
        let report = FlightDataRecorder.report(corpus: FlightCorpus(flights: legacy, calendar: newYork))
        XCTAssertNil(report.findings.first { $0.kind == .blockTime })
    }

    func testBlockTimeStaysSilentWhenLongFlightsLandJustAsOften() {
        let flights = repeated(8) { _ in flight(outcome: .arrived, scheduled: 30 * 60) }
            + repeated(8) { _ in flight(outcome: .arrived, scheduled: 180 * 60) }
        let report = FlightDataRecorder.report(corpus: FlightCorpus(flights: flights, calendar: newYork))
        XCTAssertNil(report.findings.first { $0.kind == .blockTime })
    }

    // MARK: Week pattern

    func testWeekPatternComparesWeekdaysAgainstWeekends() throws {
        // 2026-04-06 is a Monday; 2026-04-04 is a Saturday.
        let weekdays = repeated(8) { index in
            flight(departing: date(newYork, 2026, 4, 6, 19).addingTimeInterval(Double(index / 2) * 7 * 86_400),
                   outcome: .arrived)
        }
        let weekends = repeated(8) { index in
            flight(departing: date(newYork, 2026, 4, 4, 19).addingTimeInterval(Double(index / 2) * 7 * 86_400),
                   outcome: .interrupted)
        }
        let report = FlightDataRecorder.report(corpus: FlightCorpus(flights: weekdays + weekends, calendar: newYork))

        let finding = try XCTUnwrap(report.findings.first { $0.kind == .weekPattern })
        XCTAssertTrue(finding.headline.hasPrefix("Weekdays"), finding.headline)
        XCTAssertEqual(finding.evidence.first { $0.isSubject }?.label, "Weekdays")
    }

    // MARK: Bags

    func testBagFindingNamesTheLabelThatLagsTheOthers() throws {
        let carried = repeated(5) { _ in
            flight(outcome: .arrived, bags: [(label: "Calculus", claimed: false)])
        }
        let claimed = repeated(5) { _ in
            flight(outcome: .arrived, bags: [(label: "Reading", claimed: true)])
        }
        let bare = repeated(2) { _ in flight(outcome: .arrived) }
        let report = FlightDataRecorder.report(corpus: FlightCorpus(flights: carried + claimed + bare, calendar: newYork))

        let finding = try XCTUnwrap(report.findings.first { $0.kind == .bags })
        XCTAssertTrue(finding.headline.hasPrefix("Calculus"), finding.headline)
        XCTAssertTrue(finding.detail.contains("0 of 5"), finding.detail)
        XCTAssertEqual(finding.evidence.first { $0.isSubject }?.label, "Calculus")
    }

    /// Bag labels are free text a student types. Case and stray whitespace
    /// must not split one bag into two under-sampled ones.
    func testBagLabelsAreMatchedCaseAndWhitespaceInsensitively() throws {
        let messy = ["Calculus", " calculus", "CALCULUS  ", "calculus", "Calculus "]
        let carried = messy.map { label in
            flight(outcome: .arrived, bags: [(label: label, claimed: false)])
        }
        let claimed = repeated(5) { _ in
            flight(outcome: .arrived, bags: [(label: "Reading", claimed: true)])
        }
        let bare = repeated(2) { _ in flight(outcome: .arrived) }
        let report = FlightDataRecorder.report(corpus: FlightCorpus(flights: carried + claimed + bare, calendar: newYork))

        let finding = try XCTUnwrap(report.findings.first { $0.kind == .bags })
        XCTAssertTrue(finding.detail.contains("0 of 5"), finding.detail)
    }

    /// A bag on a flight that never landed is unclaimed for a reason that
    /// has nothing to do with the bag, so those flights are not counted.
    func testBagsOnFlightsThatDidNotLandAreNotHeldAgainstTheLabel() {
        let diverted = repeated(6) { _ in
            flight(outcome: .interrupted, bags: [(label: "Calculus", claimed: false)])
        }
        let landed = repeated(6) { _ in
            flight(outcome: .arrived, bags: [(label: "Calculus", claimed: true)])
        }
        let others = repeated(6) { _ in
            flight(outcome: .arrived, bags: [(label: "Reading", claimed: true)])
        }
        let report = FlightDataRecorder.report(corpus: FlightCorpus(flights: diverted + landed + others, calendar: newYork))
        XCTAssertNil(report.findings.first { $0.kind == .bags })
    }

    func testASingleBagLabelCannotProduceAFinding() {
        let flights = repeated(14) { index in
            flight(outcome: .arrived, bags: [(label: "Calculus", claimed: index < 2)])
        }
        let report = FlightDataRecorder.report(corpus: FlightCorpus(flights: flights, calendar: newYork))
        XCTAssertNil(report.findings.first { $0.kind == .bags })
    }

    // MARK: Interruptions

    func testInterruptionFindingIsInformativeAndBreaksDownTheCauses() throws {
        let flights = repeated(6) { _ in flight(outcome: .arrived) }
            + repeated(3) { _ in flight(outcome: .interrupted) }
            + repeated(2) { _ in flight(outcome: .leftEarly) }
            + repeated(1) { _ in flight(outcome: .missedConnection) }
        let report = FlightDataRecorder.report(corpus: FlightCorpus(flights: flights, calendar: newYork))

        let finding = try XCTUnwrap(report.findings.first { $0.kind == .interruption })
        XCTAssertEqual(finding.mode, .informative)
        XCTAssertEqual(finding.separation, 0)
        XCTAssertEqual(finding.evidence.count, 3)
        XCTAssertEqual(finding.support, 6)
        XCTAssertTrue(finding.detail.contains("3 ended because the app went to the background"), finding.detail)
        XCTAssertTrue(finding.detail.contains("1 ran out the layover clock"), finding.detail)
    }

    /// A cause that never happened is not a fact about the traveler, so it
    /// does not get a clause.
    func testInterruptionOmitsCausesThatNeverHappened() throws {
        let flights = repeated(6) { _ in flight(outcome: .arrived) }
            + repeated(9) { _ in flight(outcome: .interrupted) }
            + repeated(4) { _ in flight(outcome: .leftEarly) }
        let report = FlightDataRecorder.report(corpus: FlightCorpus(flights: flights, calendar: newYork))

        let finding = try XCTUnwrap(report.findings.first { $0.kind == .interruption })
        XCTAssertFalse(finding.detail.contains("0 ran out"), finding.detail)
        XCTAssertFalse(finding.detail.contains(", 0 "), finding.detail)
        XCTAssertEqual(finding.evidence.count, 2)
        XCTAssertTrue(finding.headline.hasPrefix("Most of your diversions"), finding.headline)
    }

    /// With no dominant cause the headline stops claiming one.
    func testInterruptionHeadlineDoesNotClaimADominantCauseWhenThereIsNone() throws {
        let flights = repeated(6) { _ in flight(outcome: .arrived) }
            + repeated(5) { _ in flight(outcome: .interrupted) }
            + repeated(5) { _ in flight(outcome: .leftEarly) }
        let report = FlightDataRecorder.report(corpus: FlightCorpus(flights: flights, calendar: newYork))

        let finding = try XCTUnwrap(report.findings.first { $0.kind == .interruption })
        XCTAssertEqual(finding.headline, "Your diversions split fairly evenly between causes.")
    }

    /// Diversions written by a build that recorded no cause cannot be
    /// broken down, and are not filled in with a guess.
    func testInterruptionStaysSilentWhenTheCauseWasNeverRecorded() {
        let flights = repeated(6) { _ in flight(outcome: .arrived) }
            + repeated(8) { _ in flight(outcome: .unknown) }
        let report = FlightDataRecorder.report(corpus: FlightCorpus(flights: flights, calendar: newYork))
        XCTAssertNil(report.findings.first { $0.kind == .interruption })
    }

    func testInterruptionStaysSilentWithOnlyOneCause() {
        let flights = repeated(6) { _ in flight(outcome: .arrived) }
            + repeated(8) { _ in flight(outcome: .interrupted) }
        let report = FlightDataRecorder.report(corpus: FlightCorpus(flights: flights, calendar: newYork))
        XCTAssertNil(report.findings.first { $0.kind == .interruption })
    }

    // MARK: Recent form

    func testRecentFormComparesTheLatestBlockAgainstThePreviousOne() throws {
        let start = date(newYork, 2026, 1, 5, 19)
        let earlier = repeated(8) { index in
            flight(outcome: .interrupted, endedAt: start.addingTimeInterval(Double(index) * 86_400))
        }
        let later = repeated(8) { index in
            flight(outcome: .arrived, endedAt: start.addingTimeInterval(Double(index + 8) * 86_400))
        }
        // Deliberately out of order: the detector sorts by end time itself.
        let report = FlightDataRecorder.report(corpus: FlightCorpus(flights: later + earlier, calendar: newYork))

        let finding = try XCTUnwrap(report.findings.first { $0.kind == .recentForm })
        XCTAssertTrue(finding.headline.contains("land more often"), finding.headline)
        XCTAssertEqual(finding.support, 16)
    }

    func testRecentFormNeedsEightASide() {
        let start = date(newYork, 2026, 1, 5, 19)
        let flights = repeated(7) { index in
            flight(outcome: .interrupted, endedAt: start.addingTimeInterval(Double(index) * 86_400))
        } + repeated(7) { index in
            flight(outcome: .arrived, endedAt: start.addingTimeInterval(Double(index + 7) * 86_400))
        }
        let report = FlightDataRecorder.report(corpus: FlightCorpus(flights: flights, calendar: newYork))
        XCTAssertNil(report.findings.first { $0.kind == .recentForm })
    }

    // MARK: Ranking

    func testComparativeFindingsRankAboveInformativeOnes() {
        let evening = repeated(8) { index in
            flight(departing: date(newYork, 2026, 4, 6, 19).addingTimeInterval(Double(index) * 86_400),
                   outcome: .arrived)
        }
        let interrupted = repeated(5) { index in
            flight(departing: date(newYork, 2026, 4, 6, 23).addingTimeInterval(Double(index) * 86_400),
                   outcome: .interrupted)
        }
        let leftEarly = repeated(3) { index in
            flight(departing: date(newYork, 2026, 4, 6, 23).addingTimeInterval(Double(index + 5) * 86_400),
                   outcome: .leftEarly)
        }
        let report = FlightDataRecorder.report(
            corpus: FlightCorpus(flights: evening + interrupted + leftEarly, calendar: newYork)
        )

        XCTAssertGreaterThanOrEqual(report.findings.count, 2)
        XCTAssertEqual(report.findings.first?.mode, .comparative)
        XCTAssertEqual(report.findings.last?.kind, .interruption)
    }

    func testAReportNeverContainsTwoFindingsOfTheSameKind() {
        let flights = repeated(8) { index in
            flight(departing: date(newYork, 2026, 4, 6, 19).addingTimeInterval(Double(index) * 86_400),
                   outcome: .arrived, scheduled: 30 * 60)
        } + repeated(8) { index in
            flight(departing: date(newYork, 2026, 4, 6, 23).addingTimeInterval(Double(index) * 86_400),
                   outcome: .interrupted, scheduled: 180 * 60)
        }
        let report = FlightDataRecorder.report(corpus: FlightCorpus(flights: flights, calendar: newYork))
        XCTAssertEqual(Set(report.findings.map(\.kind)).count, report.findings.count)
    }

    // MARK: Copy

    /// The owner's bar: no scolding, no exclamation, no em-dashes. Findings
    /// are generated strings, so this is worth asserting rather than reading.
    func testFindingCopyStaysWithinTheProductVoice() {
        let flights = repeated(8) { index in
            flight(departing: date(newYork, 2026, 4, 6, 19).addingTimeInterval(Double(index) * 86_400),
                   outcome: .arrived, scheduled: 30 * 60,
                   bags: [(label: "Reading", claimed: true)])
        } + repeated(5) { index in
            flight(departing: date(newYork, 2026, 4, 6, 23).addingTimeInterval(Double(index) * 86_400),
                   outcome: .interrupted, scheduled: 180 * 60,
                   bags: [(label: "Calculus", claimed: false)])
        } + repeated(3) { index in
            flight(departing: date(newYork, 2026, 4, 6, 23).addingTimeInterval(Double(index + 5) * 86_400),
                   outcome: .leftEarly, scheduled: 180 * 60)
        }
        let report = FlightDataRecorder.report(corpus: FlightCorpus(flights: flights, calendar: newYork))
        XCTAssertFalse(report.findings.isEmpty)

        let banned = ["!", "—", "–", "fail", "should", "you need to", "bad", "worse", "lazy"]
        for finding in report.findings {
            for text in [finding.headline, finding.detail] {
                for token in banned {
                    XCTAssertFalse(text.lowercased().contains(token),
                                   "\(finding.kind) copy contains \"\(token)\": \(text)")
                }
            }
        }
    }

    // MARK: Bridging from SwiftData rows

    func testLegacyRowsReadAsArrivedOrUnknownRatherThanBeingGuessedAt() {
        let landed = LogbookEntry(originCode: "BOS", destinationCode: "JFK", flightNumber: "VOY 100",
                                  seat: "C10", miles: 187, focusSeconds: 3600, completed: true)
        let lost = LogbookEntry(originCode: "BOS", destinationCode: "JFK", flightNumber: "VOY 100",
                                seat: "C10", miles: 0, focusSeconds: 600, completed: false)

        XCTAssertEqual(landed.outcome, .arrived)
        XCTAssertEqual(lost.outcome, .unknown)

        let flight = RecordedFlight(entry: lost)
        XCTAssertNil(flight.departedAt)
        XCTAssertNil(flight.scheduledSeconds, "A stored 0 means not recorded, not a zero-length flight")
        XCTAssertFalse(flight.arrived)
    }

    func testWritingAnOutcomeKeepsTheLegacyCompletedFlagInStep() {
        let entry = LogbookEntry(originCode: "BOS", destinationCode: "JFK", flightNumber: "VOY 100",
                                 seat: "C10", miles: 187, focusSeconds: 3600, completed: true,
                                 scheduledSeconds: 3600, departedAt: Date(timeIntervalSince1970: 0),
                                 outcome: .leftEarly)
        XCTAssertEqual(entry.outcome, .leftEarly)
        XCTAssertFalse(entry.completed, "completed must track the outcome so existing readers stay correct")

        entry.outcome = .arrived
        XCTAssertTrue(entry.completed)
    }

    func testBagsPairUpEvenWhenTheClaimArrayIsShort() {
        let entry = LogbookEntry(originCode: "BOS", destinationCode: "JFK", flightNumber: "VOY 100",
                                 seat: "C10", miles: 187, focusSeconds: 3600, completed: true,
                                 intentions: ["Calculus", "Reading"], intentionsCompleted: [true])
        let flight = RecordedFlight(entry: entry)
        XCTAssertEqual(flight.bags.count, 2)
        XCTAssertTrue(flight.bags[0].claimed)
        XCTAssertFalse(flight.bags[1].claimed)
    }
}
