import XCTest
@testable import Voyage

/// OneSignal stays off without an App ID, and the segmentation tags are
/// derived from the logbook and the scheduled departure only.
@MainActor
final class PushEngagementTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    /// 2026-09-30 at `hour`:00 in Los Angeles.
    private func date(day: Int = 30, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }

    private func entry(miles: Double, at date: Date, completed: Bool = true) -> LogbookEntry {
        LogbookEntry(date: date, originCode: "SFO", destinationCode: "LAX", flightNumber: "VOY 100",
                     seat: "C10", miles: miles, focusSeconds: 3_600, completed: completed)
    }

    // MARK: App ID

    func testOnlyAUUIDConfiguresTheSDK() {
        XCTAssertNil(PushEngagement.appID(in: nil))
        XCTAssertNil(PushEngagement.appID(in: [:]))
        XCTAssertNil(PushEngagement.appID(in: [PushEngagement.appIDInfoKey: "ONESIGNAL_APP_ID_NOT_SET"]))
        XCTAssertNil(PushEngagement.appID(in: [PushEngagement.appIDInfoKey: "$(ONESIGNAL_APP_ID)"]))
        XCTAssertNil(PushEngagement.appID(in: [PushEngagement.appIDInfoKey: ""]))
        XCTAssertEqual(PushEngagement.appID(in: [PushEngagement.appIDInfoKey: " 5EB5A37E-B458-11E3-AC11-000C2940E62C "]),
                       "5eb5a37e-b458-11e3-ac11-000c2940e62c")
    }

    /// The unit-test host never initialises OneSignal, so nothing here can
    /// prompt or reach the network.
    func testTheTestHostLeavesTheSDKOff() {
        PushEngagement.configure(launchOptions: nil)
        XCTAssertFalse(PushEngagement.isConfigured)
    }

    // MARK: Tags

    func testNewTravelerHasNoGuessedStudyHourAndNoDeparture() {
        let tags = PushEngagement.tags(entries: [], scheduled: nil, membership: "unknown", calendar: calendar)
        XCTAssertEqual(tags["tier"], "member")
        XCTAssertEqual(tags["next_tier"], "silver")
        XCTAssertEqual(tags["miles_to_next_tier"], "5500")
        XCTAssertEqual(tags["flights_landed"], "0")
        XCTAssertEqual(tags["voyage_first"], "unknown")
        // Present with a nil value: remove the tag, do not leave a stale one.
        for key in ["study_hour", "last_landing_unix", "next_departure_unix", "gate_closes_unix", "next_destination"] {
            XCTAssertTrue(tags.keys.contains(key), key)
            XCTAssertEqual(tags[key], .some(nil), key)
        }
    }

    func testMilesToNextTierMatchesTheHomeCard() {
        let entries = [entry(miles: 4_700, at: date(day: 29, hour: 20))]
        let tags = PushEngagement.tags(entries: entries, scheduled: nil, membership: "economy", calendar: calendar)
        let progress = MilesProgress(entries: entries)
        XCTAssertEqual(tags["miles_to_next_tier"], String(Int(progress.remaining.rounded(.up))))
        XCTAssertEqual(tags["status_miles"], "5200")
        XCTAssertEqual(tags["last_landing_unix"], String(Int(date(day: 29, hour: 20).timeIntervalSince1970)))
    }

    func testScheduledDepartureCarriesTheGateWindow() {
        let departure = date(hour: 21)
        let flight = ScheduledFlight(destinationCode: "JFK", departure: departure)
        let tags = PushEngagement.tags(entries: [], scheduled: flight, membership: "economy", calendar: calendar)
        XCTAssertEqual(tags["next_departure_unix"], String(Int(departure.timeIntervalSince1970)))
        XCTAssertEqual(tags["gate_closes_unix"],
                       String(Int(departure.addingTimeInterval(ScheduledFlight.boardingClose).timeIntervalSince1970)))
        XCTAssertEqual(tags["next_destination"], "JFK")
        XCTAssertEqual(tags["study_hour"], "21")
    }

    func testStudyHourIsTheMostCommonDepartureHourNewestWinsATie() {
        let entries = [
            entry(miles: 300, at: date(day: 25, hour: 9)),
            entry(miles: 300, at: date(day: 26, hour: 9)),
            entry(miles: 300, at: date(day: 27, hour: 20)),
        ]
        XCTAssertEqual(PushEngagement.preferredStudyHour(entries: entries, scheduled: nil, calendar: calendar), 9)
        // One more evening flight ties 2–2; the newest hour wins.
        let tied = entries + [entry(miles: 300, at: date(day: 28, hour: 20))]
        XCTAssertEqual(PushEngagement.preferredStudyHour(entries: tied, scheduled: nil, calendar: calendar), 20)
    }

    // MARK: Diff

    func testFirstSyncClearsAbsentTagsAndLaterSyncsSendOnlyChanges() {
        let first = PushEngagement.diff(previous: nil, next: ["tier": "silver", "study_hour": nil])
        XCTAssertEqual(first.set, ["tier": "silver"])
        XCTAssertEqual(first.remove, ["study_hour"])

        let unchanged = PushEngagement.diff(previous: ["tier": "silver"], next: ["tier": "silver", "study_hour": nil])
        XCTAssertTrue(unchanged.set.isEmpty)
        XCTAssertTrue(unchanged.remove.isEmpty)

        // Boarding clears the departure: the tag must go, so the traveler
        // leaves the "gate closing" segment.
        let boarded = PushEngagement.diff(previous: ["tier": "silver", "next_departure_unix": "1790000000"],
                                          next: ["tier": "gold", "next_departure_unix": nil])
        XCTAssertEqual(boarded.set, ["tier": "gold"])
        XCTAssertEqual(boarded.remove, ["next_departure_unix"])
    }
}
