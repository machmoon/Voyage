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

    private func reward(hours: Double, days: Int, heldFirst: Bool = false) -> FirstClassReward {
        FirstClassReward(standing: LoyaltyStanding(
            landedFocusSeconds: hours * hour, landedFlights: days, visitedCodes: [],
            flightDays: days, heldFirstSeat: heldFirst))
    }

    func testFrontRowOpensAfterFirstLandingRestWithTheReward() {
        let plan = AircraftProfile.boeing737800.cabinPlan
        func access(_ row: Int, _ reward: FirstClassReward, _ landings: Int) -> PremiumSeatAccess {
            LoyaltyProgram.premiumSeatAccess(row: row, plan: plan, reward: reward, landedFlights: landings)
        }
        let fresh = FirstClassReward.newTraveler
        let earned = reward(hours: 8, days: 5)
        XCTAssertEqual(access(1, fresh, 0), .lockedUntilFirstLanding)
        XCTAssertEqual(access(2, fresh, 0), .lockedUntilReward)
        XCTAssertEqual(access(1, fresh, 1), .earlyUpgrade)
        XCTAssertEqual(access(4, reward(hours: 4, days: 3), 3), .lockedUntilReward)
        XCTAssertEqual(access(1, earned, 5), .open)
        XCTAssertEqual(access(4, earned, 5), .open)
        // Economy is never gated.
        XCTAssertEqual(access(14, fresh, 0), .open)
        XCTAssertTrue(access(1, fresh, 1).isBookable)
        XCTAssertFalse(access(2, fresh, 1).isBookable)
    }

    // MARK: First class reward

    func testRewardNeedsBothTheHoursAndTheDays() {
        XCTAssertFalse(reward(hours: 0, days: 0).isUnlocked)
        // One long cram day is not regular use.
        XCTAssertFalse(reward(hours: 9, days: 1).isUnlocked)
        // Five days of short sessions is not enough focus.
        XCTAssertFalse(reward(hours: 7.9, days: 6).isUnlocked)
        XCTAssertTrue(reward(hours: 8, days: 5).isUnlocked)
        XCTAssertTrue(reward(hours: 20, days: 12).isUnlocked)
    }

    /// Silver comes with the Solo rating at three landings. Three hops on
    /// day one must not open the cabin any more.
    func testSoloSilverOnDayOneDoesNotOpenFirst() {
        let day = Date(timeIntervalSince1970: 1_790_000_000)
        let entries = (0..<3).map { index in
            LogbookEntry(date: day.addingTimeInterval(Double(index) * 2 * hour),
                         originCode: "SFO", destinationCode: "LAX", flightNumber: "VOY 1",
                         seat: "C14", miles: 337, focusSeconds: 90 * 60, completed: true)
        }
        XCTAssertGreaterThanOrEqual(LogbookStats.tier(entries), .silver)
        let reward = FirstClassReward(standing: LoyaltyStanding(entries: entries))
        XCTAssertFalse(reward.isUnlocked)
        XCTAssertEqual(reward.flightDays, 1)
    }

    /// An hour a day, every day: locked on day seven, open on day eight.
    func testAnHourADayOpensFirstInTheSecondWeek() {
        let calendar = Calendar(identifier: .gregorian)
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        func logbook(days: Int) -> [LogbookEntry] {
            (0..<days).map { day in
                LogbookEntry(date: calendar.date(byAdding: .day, value: day, to: start)!,
                             originCode: "SFO", destinationCode: "LAX", flightNumber: "VOY 1",
                             seat: "C14", miles: 337, focusSeconds: hour, completed: true)
            }
        }
        XCTAssertFalse(FirstClassReward(standing: LoyaltyStanding(entries: logbook(days: 7), calendar: calendar)).isUnlocked)
        XCTAssertTrue(FirstClassReward(standing: LoyaltyStanding(entries: logbook(days: 8), calendar: calendar)).isUnlocked)
    }

    func testRewardCopySaysHowCloseItIs() {
        XCTAssertEqual(reward(hours: 0, days: 0).progressLine,
                       "First class unlocks after 8 focus hours · 8h to go")
        XCTAssertEqual(reward(hours: 1 + 25.0 / 60, days: 1).progressLine,
                       "First class unlocks after 8 focus hours · 6h 35m to go")
        // Twenty seconds short rounds up, never "0h to go".
        XCTAssertEqual(reward(hours: 8 - 20.0 / 3_600, days: 5).progressLine,
                       "First class unlocks after 8 focus hours · 1m to go")
        XCTAssertEqual(reward(hours: 9, days: 3).progressLine,
                       "First class unlocks on your 5th flying day · 2 more days to go")
        XCTAssertEqual(reward(hours: 9, days: 4).progressLine,
                       "First class unlocks on your 5th flying day · 1 more day to go")
        XCTAssertNil(reward(hours: 8, days: 5).progressLine)
    }

    func testUnlockMomentFiresOnceOnTheCrossingLanding() {
        let before = reward(hours: 7.5, days: 5)
        let after = reward(hours: 8.5, days: 6)
        XCTAssertTrue(after.unlocks(comparedTo: before))
        XCTAssertFalse(after.unlocks(comparedTo: after))
        XCTAssertFalse(before.unlocks(comparedTo: .newTraveler))
    }

    /// Earned stays earned: a logbook that already sat in row 2+ of First
    /// under the old Silver rule keeps the cabin.
    func testTravelerWhoAlreadyFlewFirstKeepsIt() {
        let plan = AircraftProfile.boeing737800.cabinPlan
        let rowTwo = plan.cabins.first(where: \.isPremium)!.rows.sorted()[1]
        let flown = LogbookEntry(originCode: "SFO", destinationCode: "LAX", flightNumber: "VOY 1",
                                 seat: "\(rowTwo)A", miles: 337, focusSeconds: 90 * 60, completed: true,
                                 aircraft: .boeing737800)
        let standing = LoyaltyStanding(entries: [flown])
        XCTAssertTrue(standing.heldFirstSeat)
        XCTAssertTrue(FirstClassReward(standing: standing).isUnlocked)
        // The early-upgrade front row is not proof of the whole cabin.
        let rowOne = plan.cabins.first(where: \.isPremium)!.rows.min()!
        let early = LogbookEntry(originCode: "SFO", destinationCode: "LAX", flightNumber: "VOY 1",
                                 seat: "\(rowOne)A", miles: 337, focusSeconds: 90 * 60, completed: true,
                                 aircraft: .boeing737800)
        XCTAssertFalse(LoyaltyStanding(entries: [early]).heldFirstSeat)
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

    // MARK: Voyage First

    /// Voyage First opens every premium seat the free rules still hold, and
    /// never changes a seat status already opened.
    func testVoyageFirstOpensLockedPremiumSeatsOnly() {
        for aircraft in AircraftProfile.allCases {
            let plan = aircraft.cabinPlan
            for row in plan.cabins.flatMap(\.rows) {
                for reward in [FirstClassReward.newTraveler, reward(hours: 4, days: 3), reward(hours: 8, days: 5)] {
                    for landings in [0, 1, 5] {
                        let free = LoyaltyProgram.premiumSeatAccess(row: row, plan: plan, reward: reward,
                                                                    landedFlights: landings)
                        let member = LoyaltyProgram.premiumSeatAccess(row: row, plan: plan, reward: reward,
                                                                      landedFlights: landings,
                                                                      isFirstMember: true)
                        XCTAssertTrue(member.isBookable)
                        if free.isBookable {
                            XCTAssertEqual(member, free, "\(aircraft) row \(row) changed for a member")
                        } else {
                            XCTAssertEqual(member, .voyageFirst)
                        }
                    }
                }
            }
        }
    }

    func testPaywallNeverPresentsMidFlight() {
        XCTAssertTrue(FirstClassPaywallGate.canPresent(stage: nil))
        XCTAssertTrue(FirstClassPaywallGate.canPresent(stage: .preflight))
        XCTAssertTrue(FirstClassPaywallGate.canPresent(stage: .arrived))
        for stage: FlightSession.Stage in [.inFlight, .layover, .diverted, .missedConnection] {
            XCTAssertFalse(FirstClassPaywallGate.canPresent(stage: stage), "\(stage)")
        }
    }

    /// First-class seats are the reward, not a tier perk, so no tier may
    /// promise them on the tier-up card.
    func testNoTierPromisesFirstClassSeats() {
        for tier in FlyerTier.allCases {
            XCTAssertFalse(tier.perkDescription.localizedCaseInsensitiveContains("first-class seat"), "\(tier)")
        }
    }
}
