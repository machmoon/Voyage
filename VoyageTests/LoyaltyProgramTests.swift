import XCTest
@testable import Voyage

final class LoyaltyProgramTests: XCTestCase {

    private let hour: TimeInterval = 3_600

    private func standing(hours: Double, landings: Int = 0,
                          visited: Set<String> = []) -> LoyaltyStanding {
        LoyaltyStanding(landedFocusSeconds: hours * hour, landedFlights: landings, visitedCodes: visited)
    }

    private func unlocked(from code: String, _ standing: LoyaltyStanding) -> Set<String> {
        LoyaltyProgram.unlockedCodes(from: Airport.byCode(code), standing: standing)
    }

    private func entry(_ from: String, _ to: String, minutes: Double,
                       completed: Bool = true) -> LogbookEntry {
        LogbookEntry(originCode: from, destinationCode: to, flightNumber: "VOY 1", seat: "C10",
                     miles: 100, focusSeconds: minutes * 60, completed: completed)
    }

    // MARK: Destinations

    func testNewTravelerStartsWithTheTwoNearestDestinations() {
        XCTAssertEqual(unlocked(from: "BOS", .newTraveler), ["JFK", "YYZ"])
        XCTAssertEqual(unlocked(from: "SFO", .newTraveler), ["LAX", "SEA"])
    }

    func testEveryOriginStartsWithExactlyTwoAndTheyAreTheClosest() {
        for origin in Airport.all {
            let access = LoyaltyProgram.destinations(from: origin, standing: .newTraveler)
            XCTAssertEqual(access.count, Airport.all.count - 1)
            XCTAssertEqual(access.filter(\.isUnlocked).count, 2, origin.code)
            // Nearest first, and the open ones are the head of the list.
            XCTAssertEqual(access.map(\.distanceMiles), access.map(\.distanceMiles).sorted(), origin.code)
            XCTAssertTrue(access.prefix(2).allSatisfy(\.isUnlocked), origin.code)
            XCTAssertTrue(access.dropFirst(2).allSatisfy { !$0.isUnlocked }, origin.code)
        }
    }

    func testBandsOpenAtTheirFocusThresholds() {
        XCTAssertEqual(unlocked(from: "BOS", standing(hours: 1.99)).count, 2)
        XCTAssertEqual(unlocked(from: "BOS", standing(hours: 2)).count, 4)
        XCTAssertEqual(unlocked(from: "BOS", standing(hours: 4.99)).count, 4)
        XCTAssertEqual(unlocked(from: "BOS", standing(hours: 5)).count, 6)
        XCTAssertEqual(unlocked(from: "BOS", standing(hours: 9.99)).count, 6)
        XCTAssertEqual(unlocked(from: "BOS", standing(hours: 10)).count, 9)
    }

    func testLongHaulIsTheFarthestFromOrigin() {
        let access = LoyaltyProgram.destinations(from: Airport.byCode("BOS"), standing: .newTraveler)
        let longHaul = Set(access.filter { $0.band == .longHaul }.map(\.airport.code))
        // The west coast is the far side of the network from Boston.
        XCTAssertTrue(longHaul.isSuperset(of: ["SFO", "LAX", "YVR"]))
        XCTAssertEqual(access.first { $0.airport.code == "JFK" }?.band, .regional)
    }

    func testAlreadyVisitedDestinationStaysOpen() {
        // A traveler whose history includes a transcon keeps it, even with
        // less focus time than long-haul needs.
        let open = unlocked(from: "BOS", standing(hours: 1, landings: 1, visited: ["BOS", "LAX"]))
        XCTAssertEqual(open, ["JFK", "YYZ", "LAX"])
    }

    func testStandingCountsOnlyLandedFlights() {
        let entries = [
            entry("BOS", "JFK", minutes: 80),
            entry("BOS", "MIA", minutes: 100, completed: false),
        ]
        let standing = LoyaltyStanding(entries: entries)
        XCTAssertEqual(standing.landedFlights, 1)
        XCTAssertEqual(standing.landedFocusSeconds, 80 * 60, accuracy: 0.001)
        XCTAssertEqual(standing.visitedCodes, ["BOS", "JFK"])
        XCTAssertFalse(unlocked(from: "BOS", standing).contains("MIA"))
    }

    func testExistingHistoryKeepsWhatItsTotalsEarn() {
        // Ten landed two-hour flights: past every threshold.
        let entries = (0..<10).map { _ in entry("SFO", "LAX", minutes: 120) }
        let standing = LoyaltyStanding(entries: entries)
        XCTAssertEqual(unlocked(from: "SFO", standing).count, 9)
        XCTAssertNil(LoyaltyProgram.nextUnlock(from: Airport.byCode("SFO"), standing: standing))
    }

    func testNextUnlockNamesTheNearestLockedBandAndTimeToGo() throws {
        let next = try XCTUnwrap(LoyaltyProgram.nextUnlock(from: Airport.byCode("BOS"),
                                                           standing: standing(hours: 0.5)))
        XCTAssertEqual(next.band, .shortHaul)
        XCTAssertEqual(next.remainingFocusSeconds, 1.5 * hour, accuracy: 0.001)
        XCTAssertEqual(next.airports.count, 2)
    }

    func testNextUnlockSkipsABandOpenedByVisits() throws {
        let bos = Airport.byCode("BOS")
        let shortHaul = LoyaltyProgram.destinations(from: bos, standing: .newTraveler)
            .filter { $0.band == .shortHaul }.map(\.airport.code)
        let next = try XCTUnwrap(LoyaltyProgram.nextUnlock(
            from: bos, standing: standing(hours: 0, visited: Set(shortHaul))))
        XCTAssertEqual(next.band, .mediumHaul)
    }

    func testLockedHintText() throws {
        let access = try XCTUnwrap(LoyaltyProgram.destinations(from: Airport.byCode("BOS"),
                                                               standing: standing(hours: 0.75))
            .first { $0.band == .shortHaul })
        XCTAssertFalse(access.isUnlocked)
        XCTAssertEqual(access.unlockHint, "Opens at 2h focus")
        XCTAssertEqual(access.remainingText, "1h 15m to go")
    }

    func testBypassOpensEverything() {
        let codes = LoyaltyProgram.unlockedCodes(from: Airport.byCode("YQR"),
                                                 standing: .newTraveler, bypass: true)
        XCTAssertEqual(codes.count, 9)
        XCTAssertNil(LoyaltyProgram.nextUnlock(from: Airport.byCode("YQR"),
                                               standing: .newTraveler, bypass: true))
    }

    func testQALaunchArgumentsBypassAndEnforceFlagWins() {
        XCTAssertFalse(LoyaltyProgram.bypassesLocks(arguments: []))
        XCTAssertFalse(LoyaltyProgram.bypassesLocks(arguments: ["-AppleLanguages", "(en)"]))
        XCTAssertTrue(LoyaltyProgram.bypassesLocks(arguments: ["-VoyageShortFlights"]))
        XCTAssertTrue(LoyaltyProgram.bypassesLocks(arguments: ["-VoyageHomeAirport", "SFO", "-VoyageOpenOnWindow"]))
        XCTAssertTrue(LoyaltyProgram.bypassesLocks(arguments: ["-VoyageRecorderDemo"]))
        XCTAssertFalse(LoyaltyProgram.bypassesLocks(arguments: ["-VoyageShortFlights", "-VoyageEnforceLoyalty"]))
        XCTAssertFalse(LoyaltyProgram.bypassesLocks(arguments: ["-VoyageLoyaltyStarter"]))
    }

    // MARK: Premium seats

    func testFrontRowOpensAfterFirstLandingRestAtSilver() {
        let plan = AircraftProfile.boeing737800.cabinPlan
        func access(_ row: Int, _ tier: FlyerTier, _ landings: Int) -> PremiumSeatAccess {
            LoyaltyProgram.premiumSeatAccess(row: row, plan: plan, tier: tier, landedFlights: landings)
        }
        XCTAssertEqual(access(1, .member, 0), .lockedUntilFirstLanding)
        XCTAssertEqual(access(2, .member, 0), .lockedUntilSilver)
        XCTAssertEqual(access(1, .member, 1), .earlyUpgrade)
        XCTAssertEqual(access(4, .member, 2), .lockedUntilSilver)
        XCTAssertEqual(access(1, .silver, 5), .open)
        XCTAssertEqual(access(4, .silver, 5), .open)
        // Economy is never gated.
        XCTAssertEqual(access(14, .member, 0), .open)
        XCTAssertTrue(access(1, .member, 1).isBookable)
        XCTAssertFalse(access(2, .member, 1).isBookable)
    }

    func testEarlyRowIsTheFrontPremiumRowOnEveryAircraft() {
        for aircraft in AircraftProfile.allCases {
            let plan = aircraft.cabinPlan
            let rows = LoyaltyProgram.earlyUpgradeRows(in: plan)
            let premium = plan.cabins.first(where: \.isPremium)
            XCTAssertEqual(rows, premium.map { [$0.rows.min()!] } ?? [], aircraft.name)
            // A small number of seats: never the whole premium cabin.
            if let premium { XCTAssertLessThan(rows.count, premium.rows.count, aircraft.name) }
        }
    }
}
