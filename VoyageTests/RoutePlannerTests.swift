import XCTest
@testable import Voyage

final class RoutePlannerTests: XCTestCase {

    private let bos = Airport.byCode("BOS")
    private let jfk = Airport.byCode("JFK")
    private let sfo = Airport.byCode("SFO")
    private let yqr = Airport.byCode("YQR")
    private let lax = Airport.byCode("LAX")

    // MARK: Real durations

    func testShuttleRouteUsesRealBlockTime() {
        let itinerary = RoutePlanner.itinerary(from: bos, to: jfk)
        XCTAssertEqual(itinerary.legs.count, 1)
        XCTAssertEqual(itinerary.totalFocusDuration, 80 * 60)
        XCTAssertEqual(itinerary.layoverDuration, 0)
    }

    func testTranscontinentalNonstopIsOneLongLeg() {
        let itinerary = RoutePlanner.itinerary(from: bos, to: sfo)
        XCTAssertEqual(itinerary.legs.count, 1, "Popular BOS–SFO booking is nonstop")
        XCTAssertEqual(itinerary.totalFocusDuration, 405 * 60)
    }

    func testJetStreamAsymmetry() {
        let westbound = RoutePlanner.itinerary(from: bos, to: sfo).totalFocusDuration
        let eastbound = RoutePlanner.itinerary(from: sfo, to: bos).totalFocusDuration
        XCTAssertGreaterThan(westbound, eastbound,
                             "Westbound fights the jet stream and must be longer")
    }

    // MARK: Connections

    func testReginaRequiresConnection() {
        let itinerary = RoutePlanner.itinerary(from: bos, to: yqr)
        XCTAssertEqual(itinerary.legs.count, 2)
        XCTAssertEqual(itinerary.connection?.code, "YYZ")
        XCTAssertEqual(itinerary.layoverDuration, RoutePlanner.layoverDuration)
        // Leg durations come from the two real nonstops.
        XCTAssertEqual(itinerary.legs[0].duration, 115 * 60)
        XCTAssertEqual(itinerary.legs[1].duration, 185 * 60)
    }

    func testConnectionLegsAreContiguous() {
        let itinerary = RoutePlanner.itinerary(from: lax, to: yqr)
        XCTAssertEqual(itinerary.legs[0].destination, itinerary.legs[1].origin)
        XCTAssertEqual(itinerary.origin, lax)
        XCTAssertEqual(itinerary.destination, yqr)
    }

    // MARK: Flight numbers

    func testFlightNumbersAreDeterministicAndDirectional() {
        XCTAssertEqual(RoutePlanner.flightNumber(from: bos, to: sfo),
                       RoutePlanner.flightNumber(from: bos, to: sfo))
        XCTAssertNotEqual(RoutePlanner.flightNumber(from: bos, to: sfo),
                          RoutePlanner.flightNumber(from: sfo, to: bos))
    }

    func testFlightNumberOverrideStampsFirstLeg() {
        let itinerary = RoutePlanner.itinerary(from: bos, to: yqr, flightNumberOverride: "AC 745")
        XCTAssertEqual(itinerary.legs[0].flightNumber, "AC 745")
        XCTAssertNotEqual(itinerary.legs[1].flightNumber, "AC 745",
                          "Second leg keeps its own real number")
    }

    // MARK: Every pair resolves

    func testEveryAirportPairProducesAValidItinerary() {
        for origin in Airport.all {
            for destination in Airport.all where destination != origin {
                let itinerary = RoutePlanner.itinerary(from: origin, to: destination)
                XCTAssertFalse(itinerary.legs.isEmpty, "\(origin.code)→\(destination.code)")
                XCTAssertEqual(itinerary.origin, origin)
                XCTAssertEqual(itinerary.destination, destination)
                // Real-world sanity: 45 minutes to 8 hours of focus.
                XCTAssertGreaterThanOrEqual(itinerary.totalFocusDuration, 45 * 60,
                                            "\(origin.code)→\(destination.code)")
                XCTAssertLessThanOrEqual(itinerary.totalFocusDuration, 8 * 3600,
                                         "\(origin.code)→\(destination.code)")
                for leg in itinerary.legs {
                    XCTAssertNotEqual(leg.origin, leg.destination)
                    XCTAssertFalse(leg.flightNumber.isEmpty)
                }
            }
        }
    }

    func testEstimatedMinutesFallbackIsSane() {
        XCTAssertEqual(RoutePlanner.estimatedMinutes(forMiles: 0), 45)
        let transcon = RoutePlanner.estimatedMinutes(forMiles: 2700)
        XCTAssertGreaterThan(transcon, 300)
        XCTAssertLessThan(transcon, 480)
    }
}
