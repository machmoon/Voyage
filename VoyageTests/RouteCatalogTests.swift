import XCTest
@testable import Voyage

final class RouteCatalogTests: XCTestCase {

    // MARK: Catalog coverage & integrity

    func testEveryDirectedPairIsNonstopOrHasValidConnection() {
        for origin in Airport.all {
            for destination in Airport.all where destination != origin {
                let nonstop = RouteCatalog.nonstop(from: origin, to: destination)
                let via = RouteCatalog.via(from: origin, to: destination)
                XCTAssertTrue(nonstop != nil || via != nil,
                              "\(origin.code)→\(destination.code) missing from catalog")
                if let via {
                    XCTAssertNil(nonstop, "\(origin.code)→\(destination.code) can't be both")
                    XCTAssertNotEqual(via.code, origin.code)
                    XCTAssertNotEqual(via.code, destination.code)
                    XCTAssertNotNil(RouteCatalog.nonstop(from: origin, to: via),
                                    "First connecting leg \(origin.code)→\(via.code) must be a real nonstop")
                    XCTAssertNotNil(RouteCatalog.nonstop(from: via, to: destination),
                                    "Second connecting leg \(via.code)→\(destination.code) must be a real nonstop")
                }
            }
        }
    }

    func testNonstopBlockTimesAreRealistic() {
        for (key, route) in RouteCatalog.nonstops {
            XCTAssertGreaterThanOrEqual(route.minutes, 60, key)
            XCTAssertLessThanOrEqual(route.minutes, 430, key)
            XCTAssertFalse(route.departureTimes.isEmpty, key)
            // Departure times parse and are ascending.
            let minutesOfDay: [Int] = route.departureTimes.compactMap { time in
                let parts = time.split(separator: ":")
                guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
                      (0..<24).contains(h), (0..<60).contains(m) else { return nil }
                return h * 60 + m
            }
            XCTAssertEqual(minutesOfDay.count, route.departureTimes.count, key)
            XCTAssertEqual(minutesOfDay, minutesOfDay.sorted(), key)
        }
    }

    func testBlockTimeScalesWithDistance() {
        for (key, route) in RouteCatalog.nonstops {
            let origin = Airport.byCode(route.originCode)
            let destination = Airport.byCode(route.destinationCode)
            let miles = origin.distanceMiles(to: destination)
            // Implied end-to-end speed sanity (accounts for taxi overhead).
            let hours = Double(route.minutes) / 60
            let mph = miles / hours
            XCTAssertGreaterThan(mph, 100, "\(key) implies impossibly slow flight")
            XCTAssertLessThan(mph, 600, "\(key) implies faster than airliners fly")
        }
    }

    // MARK: Departure board

    func testUpcomingDeparturesAreFutureSortedAndCounted() {
        let bos = Airport.byCode("BOS")
        let jfk = Airport.byCode("JFK")
        let now = Date()
        let options = RouteCatalog.upcomingDepartures(from: bos, to: jfk, after: now, count: 6)
        XCTAssertEqual(options.count, 6)
        for option in options {
            XCTAssertGreaterThan(option.departure, now)
        }
        let dates = options.map(\.departure)
        XCTAssertEqual(dates, dates.sorted())
    }

    func testLateNightRollsToTomorrow() {
        // 23:50 local: every BOS→JFK departure today is gone.
        var calendar = Calendar.current
        calendar.timeZone = .current
        let lateTonight = calendar.date(bySettingHour: 23, minute: 50, second: 0, of: Date())!
        let options = RouteCatalog.upcomingDepartures(from: Airport.byCode("BOS"),
                                                      to: Airport.byCode("JFK"),
                                                      after: lateTonight, count: 3)
        XCTAssertEqual(options.count, 3)
        for option in options {
            XCTAssertGreaterThan(option.departure, lateTonight)
        }
    }

    func testConnectionRouteUsesFirstLegScheduleAndThroughItinerary() {
        let bos = Airport.byCode("BOS")
        let yqr = Airport.byCode("YQR")
        let options = RouteCatalog.upcomingDepartures(from: bos, to: yqr, count: 3)
        XCTAssertFalse(options.isEmpty)
        for option in options {
            XCTAssertTrue(option.itinerary.isConnection)
            XCTAssertEqual(option.itinerary.connection?.code, "YYZ")
            XCTAssertEqual(option.itinerary.primaryFlightNumber, option.flightNumber,
                           "Booked departure's number must appear on the boarding pass")
            XCTAssertGreaterThan(option.arrival, option.departure)
        }
    }

    func testDistinctDeparturesGetDistinctFlightNumbers() {
        let sfo = Airport.byCode("SFO")
        let lax = Airport.byCode("LAX")
        let options = RouteCatalog.upcomingDepartures(from: sfo, to: lax, count: 5)
        let numbers = Set(options.map(\.flightNumber))
        XCTAssertGreaterThan(numbers.count, 1, "Consecutive departures should differ")
    }
}
