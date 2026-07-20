import XCTest
import CoreLocation
@testable import Voyage

final class GreatCircleTests: XCTestCase {

    private let bos = Airport.byCode("BOS").coordinate
    private let sfo = Airport.byCode("SFO").coordinate
    private let jfk = Airport.byCode("JFK").coordinate

    func testEndpointsAreExact() {
        let start = GreatCircle.point(from: bos, to: sfo, fraction: 0)
        let end = GreatCircle.point(from: bos, to: sfo, fraction: 1)
        XCTAssertEqual(start.latitude, bos.latitude, accuracy: 1e-6)
        XCTAssertEqual(start.longitude, bos.longitude, accuracy: 1e-6)
        XCTAssertEqual(end.latitude, sfo.latitude, accuracy: 1e-6)
        XCTAssertEqual(end.longitude, sfo.longitude, accuracy: 1e-6)
    }

    func testFractionIsClamped() {
        let below = GreatCircle.point(from: bos, to: sfo, fraction: -0.4)
        let above = GreatCircle.point(from: bos, to: sfo, fraction: 1.7)
        XCTAssertEqual(below.latitude, bos.latitude, accuracy: 1e-6)
        XCTAssertEqual(above.longitude, sfo.longitude, accuracy: 1e-6)
    }

    func testMidpointArcsNorthOfRhumbLine() {
        // Great circles between mid-latitude east–west pairs bow poleward.
        let mid = GreatCircle.point(from: bos, to: sfo, fraction: 0.5)
        let straightMidLat = (bos.latitude + sfo.latitude) / 2
        XCTAssertGreaterThan(mid.latitude, straightMidLat + 1,
                             "BOS–SFO great circle should arc well north")
        XCTAssertGreaterThan(mid.longitude, -123)
        XCTAssertLessThan(mid.longitude, -71)
    }

    func testMidpointIsEquidistantFromEndpoints() {
        let mid = GreatCircle.point(from: bos, to: sfo, fraction: 0.5)
        let midLocation = CLLocation(latitude: mid.latitude, longitude: mid.longitude)
        let toStart = midLocation.distance(from: CLLocation(latitude: bos.latitude, longitude: bos.longitude))
        let toEnd = midLocation.distance(from: CLLocation(latitude: sfo.latitude, longitude: sfo.longitude))
        XCTAssertEqual(toStart, toEnd, accuracy: toStart * 0.01)
    }

    func testSamePointDegenerateCase() {
        let point = GreatCircle.point(from: bos, to: bos, fraction: 0.5)
        XCTAssertEqual(point.latitude, bos.latitude, accuracy: 1e-9)
        XCTAssertEqual(point.longitude, bos.longitude, accuracy: 1e-9)
    }

    func testBearingCardinalSanity() {
        // JFK → SFO heads generally west-northwest.
        let westish = GreatCircle.bearing(from: jfk, to: sfo)
        XCTAssertGreaterThan(westish, 250)
        XCTAssertLessThan(westish, 320)

        // Due north from the equator.
        let equatorA = CLLocationCoordinate2D(latitude: 0, longitude: -70)
        let north = CLLocationCoordinate2D(latitude: 10, longitude: -70)
        XCTAssertEqual(GreatCircle.bearing(from: equatorA, to: north), 0, accuracy: 0.5)

        // Due east along the equator.
        let east = CLLocationCoordinate2D(latitude: 0, longitude: -60)
        XCTAssertEqual(GreatCircle.bearing(from: equatorA, to: east), 90, accuracy: 0.5)
    }

    func testPointsSamplingIncludesEndpointsAndIsOrdered() {
        let points = GreatCircle.points(from: bos, to: sfo, count: 48)
        XCTAssertEqual(points.count, 48)
        XCTAssertEqual(points.first!.latitude, bos.latitude, accuracy: 1e-6)
        XCTAssertEqual(points.last!.longitude, sfo.longitude, accuracy: 1e-6)
        // Longitude decreases monotonically flying west.
        for i in 1..<points.count {
            XCTAssertLessThan(points[i].longitude, points[i - 1].longitude)
        }
    }
}
