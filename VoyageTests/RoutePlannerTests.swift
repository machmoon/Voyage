import XCTest
import CoreLocation
@testable import Voyage

final class RoutePlannerTests: XCTestCase {

    private var bos: Airport { Airport.byCode("BOS") }
    private var jfk: Airport { Airport.byCode("JFK") }
    private var sfo: Airport { Airport.byCode("SFO") }
    private var yqr: Airport { Airport.byCode("YQR") }
    private var yyz: Airport { Airport.byCode("YYZ") }
    private var lax: Airport { Airport.byCode("LAX") }

    // MARK: Great-circle distance

    func testBOSToJFKIsShortHaulDistance() {
        let miles = bos.distanceMiles(to: jfk)
        // ~185–200 statute miles depending on exact airport coords
        XCTAssertGreaterThan(miles, 150)
        XCTAssertLessThan(miles, 250)
        XCTAssertFalse(RoutePlanner.isLongHaul(from: bos, to: jfk))
    }

    func testBOSToSFOIsLongHaulDistance() {
        let miles = bos.distanceMiles(to: sfo)
        // Coast-to-coast ~2,700 miles
        XCTAssertGreaterThan(miles, 2_400)
        XCTAssertLessThan(miles, 3_000)
        XCTAssertTrue(RoutePlanner.isLongHaul(from: bos, to: sfo))
    }

    func testDistanceIsSymmetric() {
        XCTAssertEqual(bos.distanceMiles(to: sfo), sfo.distanceMiles(to: bos), accuracy: 0.001)
    }

    func testNearestAirportFromDowntownBoston() {
        let downtown = CLLocation(latitude: 42.3601, longitude: -71.0589)
        XCTAssertEqual(Airport.nearest(to: downtown).code, "BOS")
    }

    // MARK: Duration bucketing

    func testShortHaulBucketsToTwoHours() {
        XCTAssertEqual(RoutePlanner.focusDuration(from: bos, to: jfk), RoutePlanner.shortHaulDuration)
        let itinerary = RoutePlanner.itinerary(from: bos, to: jfk)
        XCTAssertEqual(itinerary.legs.count, 1)
        XCTAssertEqual(itinerary.legs[0].duration, 2 * 3600)
        XCTAssertEqual(itinerary.layoverDuration, 0)
        XCTAssertFalse(itinerary.isConnection)
    }

    func testLongHaulBucketsToSixHoursFocus() {
        XCTAssertEqual(RoutePlanner.focusDuration(from: bos, to: sfo), RoutePlanner.longHaulDuration)
        let itinerary = RoutePlanner.itinerary(from: bos, to: sfo)
        XCTAssertEqual(itinerary.totalFocusDuration, 6 * 3600, accuracy: 0.1)
        XCTAssertTrue(itinerary.isConnection)
        XCTAssertEqual(itinerary.layoverDuration, RoutePlanner.layoverDuration)
    }

    // MARK: Connection routing

    func testLongHaulBecomesTwoLegConnection() {
        let itinerary = RoutePlanner.itinerary(from: bos, to: yqr)
        XCTAssertEqual(itinerary.legs.count, 2)
        XCTAssertEqual(itinerary.origin.code, "BOS")
        XCTAssertEqual(itinerary.destination.code, "YQR")
        XCTAssertNotNil(itinerary.connection)
        XCTAssertEqual(itinerary.legs[0].destination, itinerary.legs[1].origin)
        XCTAssertEqual(itinerary.legs[0].duration + itinerary.legs[1].duration, 6 * 3600, accuracy: 0.1)
    }

    func testConnectionAirportMinimizesDetour() {
        // For BOS→YQR the planner should pick a sensible via (often YYZ).
        let via = RoutePlanner.connectionAirport(from: bos, to: yqr)
        XCTAssertNotEqual(via, bos)
        XCTAssertNotEqual(via, yqr)

        let viaDetour = bos.distanceMiles(to: via) + via.distanceMiles(to: yqr)
        for candidate in Airport.all where candidate != bos && candidate != yqr {
            let detour = bos.distanceMiles(to: candidate) + candidate.distanceMiles(to: yqr)
            XCTAssertLessThanOrEqual(viaDetour, detour + 0.001)
        }
    }

    func testLegDurationsNeverDropBelowNinetyMinutes() {
        let itinerary = RoutePlanner.itinerary(from: lax, to: jfk)
        XCTAssertEqual(itinerary.legs.count, 2)
        for leg in itinerary.legs {
            XCTAssertGreaterThanOrEqual(leg.duration, 90 * 60)
        }
    }

    func testFlightNumberIsDeterministic() {
        let a = RoutePlanner.flightNumber(from: bos, to: sfo)
        let b = RoutePlanner.flightNumber(from: bos, to: sfo)
        XCTAssertEqual(a, b)
        XCTAssertTrue(a.hasPrefix("VA "))
        XCTAssertNotEqual(
            RoutePlanner.flightNumber(from: bos, to: sfo),
            RoutePlanner.flightNumber(from: sfo, to: bos)
        )
    }

    func testThresholdBoundaryAt1500Miles() {
        XCTAssertEqual(RoutePlanner.longHaulThresholdMiles, 1500)
        // BOS–MIA is typically ~1,250 mi (short); BOS–YVR is long.
        XCTAssertFalse(RoutePlanner.isLongHaul(from: bos, to: Airport.byCode("MIA")))
        XCTAssertTrue(RoutePlanner.isLongHaul(from: bos, to: Airport.byCode("YVR")))
        _ = yyz // keep airport set "used" for clarity in suite
    }
}
