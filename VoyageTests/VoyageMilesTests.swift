import XCTest
@testable import Voyage

/// The welcome bonus, the +500 thresholds, the progress bar and the
/// miles-to-tier route.
@MainActor
final class VoyageMilesTests: XCTestCase {

    private func entry(miles: Double, completed: Bool = true) -> LogbookEntry {
        LogbookEntry(date: Date(timeIntervalSince1970: 1_700_000_000),
                     originCode: "SFO", destinationCode: "LAX", flightNumber: "VOY 100",
                     seat: "C10", miles: miles, focusSeconds: 0, completed: completed)
    }

    /// The old rule, before the welcome bonus: tier by flown miles against
    /// 5,000 / 15,000 / 40,000.
    private func oldTier(_ miles: Double) -> FlyerTier {
        switch miles {
        case 40_000...: return .platinum
        case 15_000...: return .gold
        case 5_000...: return .silver
        default: return .member
        }
    }

    /// No logbook changes tier under +500 bonus / +500 thresholds, including
    /// every value right at and around the old boundaries.
    func testNoLogbookChangesTier() {
        var samples: [Double] = [0, 1, 250, 4_999, 5_000, 5_001, 14_999, 15_000, 15_001,
                                 39_999, 40_000, 40_001, 123_456]
        samples += stride(from: 0.0, through: 45_000, by: 37.5).map { $0 }
        for miles in samples {
            let entries = [entry(miles: miles)]
            let byMiles = FlyerTier.tier(forMiles: VoyageMiles.statusMiles(entries))
            XCTAssertEqual(byMiles, oldTier(miles), "tier changed at \(miles) flown miles")
        }
    }

    func testBonusOnlyAfterFirstDepartureAndTotalMilesStayFlown() {
        XCTAssertEqual(VoyageMiles.statusMiles([]), 0)
        let entries = [entry(miles: 337), entry(miles: 100, completed: false)]
        XCTAssertEqual(VoyageMiles.bonusMiles(entries), 500)
        XCTAssertEqual(LogbookStats.totalMiles(entries), 437, accuracy: 0.001)
        XCTAssertEqual(VoyageMiles.statusMiles(entries), 937, accuracy: 0.001)
    }

    func testProgressShowsBonusAsFirstSegment() {
        let progress = MilesProgress(flownMiles: 337, bonusMiles: 500, tier: .member)
        XCTAssertEqual(progress.next, .silver)
        XCTAssertEqual(progress.remaining, 5_500 - 837, accuracy: 0.001)
        XCTAssertEqual(progress.fraction, 837 / 5_500, accuracy: 0.0001)
        XCTAssertEqual(progress.bonusFraction, 500 / 5_500, accuracy: 0.0001)
        XCTAssertFalse(progress.isAlmostThere)
        XCTAssertEqual(progress.headline, "4,663 miles to Silver")
    }

    func testAlmostThereAtEightyPercent() {
        let progress = MilesProgress(flownMiles: 3_900, bonusMiles: 500, tier: .member)
        XCTAssertTrue(progress.isAlmostThere)
        XCTAssertTrue(progress.headline.hasPrefix("Almost Silver"))
    }

    /// Post-reward resetting: right after Silver the Gold bar already carries
    /// the surplus, and the bonus segment is no longer drawn.
    func testTierUpCarriesSurplusIntoNextBand() {
        let progress = MilesProgress(flownMiles: 5_320, bonusMiles: 500, tier: .silver)
        XCTAssertEqual(progress.carriedOver, 320, accuracy: 0.001)
        XCTAssertGreaterThan(progress.fraction, 0)
        XCTAssertEqual(progress.bonusFraction, 0)
    }

    func testPlatinumHasNoGap() {
        let progress = MilesProgress(flownMiles: 60_000, bonusMiles: 500, tier: .platinum)
        XCTAssertEqual(progress.remaining, 0)
        XCTAssertEqual(progress.fraction, 1)
    }

    func testRouteSuggestionUsesFewestTripsOnAnOpenRoute() throws {
        let origin = Airport.byCode("SFO")
        let open = LoyaltyProgram.destinations(from: origin, standing: .newTraveler)
            .filter(\.isUnlocked)
        let nearest = try XCTUnwrap(open.first)
        let miles = RoutePlanner.itinerary(from: origin, to: nearest.airport).totalMiles

        let one = try XCTUnwrap(MilesRouteSuggestion.best(remaining: miles * 0.5, from: origin,
                                                          standing: .newTraveler))
        XCTAssertEqual(one.trips, 1)
        XCTAssertTrue(open.map(\.airport.code).contains(one.destination.code))
        XCTAssertTrue(one.sentence.hasSuffix("gets you there."))

        XCTAssertNil(MilesRouteSuggestion.best(remaining: 0, from: origin, standing: .newTraveler))
        XCTAssertNil(MilesRouteSuggestion.best(remaining: 1_000_000, from: origin, standing: .newTraveler))
        XCTAssertEqual(MilesRouteSuggestion.hoursSentence(remaining: 900), "About 2 h of flying.")
    }

    func testSentenceWording() {
        let sfo = Airport.byCode("SFO"), lax = Airport.byCode("LAX")
        let twice = MilesRouteSuggestion(origin: sfo, destination: lax, miles: 337,
                                         focusSeconds: 85 * 60, trips: 2)
        XCTAssertEqual(twice.sentence, "SFO–LAX (1h 25m) twice gets you there.")
    }
}
