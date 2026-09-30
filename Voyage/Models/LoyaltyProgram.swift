import Foundation

// MARK: - Loyalty progression
//
// Destinations open up as the traveler logs study time, and the front row of
// the premium cabin opens after the first landing, ahead of the rest of the
// cabin at Silver. Everything here is cosmetic, like `FlyerTier`: it changes
// which cards can be booked and which seats can be picked, never timing,
// strict mode or the logbook.
//
// The shape is Habitica's quest gating (HabitRPG/habitica @ bce89c6):
//   - the threshold is data on the content, not logic in the view
//     (`lvl: 15` on each quest in website/common/script/content/quests/series.js,
//     here `RouteBand.requiredFocusSeconds`);
//   - one pure predicate decides locked or not from the content and the
//     user's totals (`lockQuest(quest, user)` in
//     website/common/script/libs/getItemInfo.js, here `LoyaltyProgram.access`);
//   - a locked item stays in the shop, dimmed, and says what opens it
//     ("You must be level <%= level %> to buy this quest!", the `mustLvlQuest`
//     popover in website/client/src/components/shops/quests/questPopover.vue,
//     here "Opens at 2h focus");
//   - once earned it stays earned (`user.flags.levelDrops` in
//     website/common/script/fns/updateStats.js, here a destination already in
//     the logbook never locks again).

/// The totals a loyalty decision needs, folded once from the logbook.
struct LoyaltyStanding: Equatable {
    /// Focus time of landed flights. The same "total time" the pilot rating
    /// line on Home counts, so the two numbers never disagree.
    var landedFocusSeconds: TimeInterval
    /// Flights that reached the gate.
    var landedFlights: Int
    /// Every airport the traveler has landed at or departed from. A place you
    /// have already flown to never locks again, whatever the rules say later.
    var visitedCodes: Set<String>

    static let newTraveler = LoyaltyStanding(landedFocusSeconds: 0, landedFlights: 0, visitedCodes: [])

    init(landedFocusSeconds: TimeInterval, landedFlights: Int, visitedCodes: Set<String>) {
        self.landedFocusSeconds = landedFocusSeconds
        self.landedFlights = landedFlights
        self.visitedCodes = visitedCodes
    }

    init(entries: [LogbookEntry]) {
        let landed = entries.filter(\.completed)
        self.landedFocusSeconds = LogbookStats.totalFocusSeconds(entries)
        self.landedFlights = landed.count
        self.visitedCodes = Set(landed.flatMap { [$0.originCode, $0.destinationCode] })
    }
}

/// How far a destination sits from the traveler's origin, by its rank in
/// great-circle distance. The words are the ones airlines use for stage
/// length; the thresholds are landed study time.
enum RouteBand: Int, CaseIterable, Comparable {
    case regional
    case shortHaul
    case mediumHaul
    case longHaul

    var title: String {
        switch self {
        case .regional: return "Regional"
        case .shortHaul: return "Short-haul"
        case .mediumHaul: return "Medium-haul"
        case .longHaul: return "Long-haul"
        }
    }

    /// Landed focus needed to book this band.
    ///
    /// Tuned so a traveler studying about an hour a day opens short-haul on
    /// day two, medium-haul inside the first week, and long-haul in the
    /// second. The nearest pair is open from the first launch.
    var requiredFocusSeconds: TimeInterval {
        switch self {
        case .regional: return 0
        case .shortHaul: return 2 * 3_600
        case .mediumHaul: return 5 * 3_600
        case .longHaul: return 10 * 3_600
        }
    }

    /// Nearest two destinations are regional, the next two short-haul, the
    /// next two medium-haul, and everything farther is long-haul. Ranked
    /// rather than cut at fixed distances so every origin starts with two
    /// open routes, including Regina, whose nearest neighbor is 800 miles out.
    static func band(forDistanceRank rank: Int) -> RouteBand {
        switch rank {
        case ..<2: return .regional
        case 2..<4: return .shortHaul
        case 4..<6: return .mediumHaul
        default: return .longHaul
        }
    }

    static func < (lhs: RouteBand, rhs: RouteBand) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One destination card's loyalty state.
struct DestinationAccess: Identifiable, Equatable {
    let airport: Airport
    let band: RouteBand
    let distanceMiles: Double
    let isUnlocked: Bool
    /// Landed focus still needed. Zero when unlocked.
    let remainingFocusSeconds: TimeInterval

    var id: String { airport.code }

    /// "Opens at 2h focus", the hint on a locked card.
    var unlockHint: String {
        "Opens at \(PilotRatings.hoursText(band.requiredFocusSeconds)) focus"
    }

    /// "1h 20m to go", the progress half of the hint.
    var remainingText: String {
        "\(PilotRatings.hoursText(remainingFocusSeconds)) to go"
    }
}

/// The next band that opens, for the one-line hint on Home.
struct NextUnlock: Equatable {
    let band: RouteBand
    let airports: [Airport]
    let remainingFocusSeconds: TimeInterval
}

/// Where a premium seat stands for this traveler.
enum PremiumSeatAccess: Equatable {
    /// Not a premium seat, or the whole premium cabin is open.
    case open
    /// A front-row seat opened early, before Silver.
    case earlyUpgrade
    /// Still closed; opens after the first landed flight.
    case lockedUntilFirstLanding
    /// Still closed; opens at Silver status.
    case lockedUntilSilver
    /// A seat free status has not opened yet, open because the traveler
    /// flies Voyage First. Only ever replaces one of the two locked cases:
    /// a seat status already opened stays `.open`/`.earlyUpgrade`.
    case voyageFirst

    var isBookable: Bool {
        switch self {
        case .open, .earlyUpgrade, .voyageFirst: return true
        case .lockedUntilFirstLanding, .lockedUntilSilver: return false
        }
    }
}

enum LoyaltyProgram {

    // MARK: Test and demo bypass

    /// QA, UI-test, screenshot and demo launches see the whole network.
    /// Every one of them passes a `-Voyage…` argument and production never
    /// does (the same test `RootView.recoverInterruptedFlight` uses), so the
    /// existing tours can keep booking LAX or YQR from a fresh simulator.
    /// `-VoyageEnforceLoyalty` (or `-VoyageLoyaltyStarter`) turns the rules
    /// back on for a capture of the locked state.
    static func bypassesLocks(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        if arguments.contains("-VoyageEnforceLoyalty")
            || arguments.contains(LoyaltyStarterLogbook.argument) { return false }
        return arguments.contains { $0.hasPrefix("-Voyage") }
    }

    // MARK: Destinations

    /// Every other catalog airport, nearest first, with its lock state.
    static func destinations(
        from origin: Airport,
        standing: LoyaltyStanding,
        airports: [Airport] = Airport.all,
        bypass: Bool = false
    ) -> [DestinationAccess] {
        let others: [Airport] = airports.filter { $0.code != origin.code }
        let ranked: [(airport: Airport, miles: Double)] = others
            .map { (airport: $0, miles: origin.distanceMiles(to: $0)) }
            .sorted { lhs, rhs in
                if lhs.miles != rhs.miles { return lhs.miles < rhs.miles }
                return lhs.airport.code < rhs.airport.code
            }

        var result: [DestinationAccess] = []
        for (rank, pair) in ranked.enumerated() {
            let airport = pair.airport
            let miles = pair.miles
            let band = RouteBand.band(forDistanceRank: rank)
            let remaining: TimeInterval = max(0, band.requiredFocusSeconds - standing.landedFocusSeconds)
            let visited = standing.visitedCodes.contains(airport.code)
            let unlocked = bypass || remaining == 0 || visited
            result.append(DestinationAccess(
                airport: airport,
                band: band,
                distanceMiles: miles,
                isUnlocked: unlocked,
                remainingFocusSeconds: unlocked ? 0 : remaining
            ))
        }
        return result
    }

    /// Codes of every bookable destination from `origin`.
    static func unlockedCodes(
        from origin: Airport,
        standing: LoyaltyStanding,
        bypass: Bool = false
    ) -> Set<String> {
        Set(destinations(from: origin, standing: standing, bypass: bypass)
            .filter(\.isUnlocked).map(\.airport.code))
    }

    /// The nearest band that still has a locked destination, or nil once the
    /// whole network is open.
    static func nextUnlock(
        from origin: Airport,
        standing: LoyaltyStanding,
        bypass: Bool = false
    ) -> NextUnlock? {
        let locked = destinations(from: origin, standing: standing, bypass: bypass)
            .filter { !$0.isUnlocked }
        guard let band = locked.map(\.band).min() else { return nil }
        let inBand = locked.filter { $0.band == band }
        return NextUnlock(
            band: band,
            airports: inBand.map(\.airport),
            remainingFocusSeconds: inBand.map(\.remainingFocusSeconds).max() ?? 0
        )
    }

    // MARK: Premium cabin

    /// Rows at the front of the premium cabin that open after the first
    /// landing, before Silver opens the rest. One row: four seats on the
    /// narrowbodies, two on the Overture.
    static let earlyUpgradeRowCount = 1

    /// Landings before the early rows open.
    static let earlyUpgradeLandings = 1

    /// The premium rows that open early on this plan: the front
    /// `earlyUpgradeRowCount` rows of its first premium cabin.
    static func earlyUpgradeRows(in plan: CabinPlan) -> Set<Int> {
        guard let premium = plan.cabins.first(where: \.isPremium) else { return [] }
        return Set(premium.rows.sorted().prefix(earlyUpgradeRowCount))
    }

    /// Whether a seat in `row` can be booked.
    ///
    /// `isFirstMember` only adds: Voyage First opens every premium seat the
    /// free rules still hold closed, and never changes a seat that status
    /// already opened. Free travellers keep the front row after their first
    /// landing and the whole cabin at Silver, forever.
    static func premiumSeatAccess(
        row: Int,
        plan: CabinPlan,
        tier: FlyerTier,
        landedFlights: Int,
        isFirstMember: Bool = false
    ) -> PremiumSeatAccess {
        guard plan.isPremiumRow(row), tier < .silver else { return .open }
        let free: PremiumSeatAccess
        if earlyUpgradeRows(in: plan).contains(row) {
            free = landedFlights >= earlyUpgradeLandings ? .earlyUpgrade : .lockedUntilFirstLanding
        } else {
            free = .lockedUntilSilver
        }
        if isFirstMember && !free.isBookable { return .voyageFirst }
        return free
    }
}

// MARK: - Capture mode

/// `-VoyageLoyaltyStarter`: an in-memory logbook holding one landed SFO to
/// LAX hop, with the loyalty rules enforced. It is what a traveler sees after
/// their first flight: the regional routes plus anywhere already flown, the
/// rest dimmed, and the front row of First open early. In-memory on purpose,
/// like `-VoyageRecorderDemo`, so a capture never touches the real store.
enum LoyaltyStarterLogbook {
    static let argument = "-VoyageLoyaltyStarter"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }

    static func entries(now: Date = .now) -> [LogbookEntry] {
        let origin = Airport.byCode("SFO")
        let destination = Airport.byCode("LAX")
        let itinerary = RoutePlanner.itinerary(from: origin, to: destination)
        return [LogbookEntry(
            date: now.addingTimeInterval(-86_400),
            originCode: origin.code,
            destinationCode: destination.code,
            flightNumber: itinerary.primaryFlightNumber,
            seat: "C14",
            miles: itinerary.totalMiles,
            focusSeconds: itinerary.totalFocusDuration,
            completed: true,
            outcome: .arrived
        )]
    }
}
