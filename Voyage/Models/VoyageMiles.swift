import Foundation

// MARK: - Voyage Miles
//
// The frequent-flyer card. Miles are the real great-circle distance of the
// legs you flew, which already scale with focused time because a longer
// route is a longer session. Two loyalty-card findings shape how progress is
// shown, and neither changes what anyone has earned:
//
// - Endowed progress (Nunes & Drèze 2006, J. Consumer Research 32(4)): a
//   ten-stamp card with two stamps already on it is finished more often
//   than an eight-stamp blank one. Voyage credits a 500-mile welcome bonus
//   at the first torn boarding pass, with its reason printed, and moves every
//   threshold up by the same 500, so the effort to Silver is unchanged.
// - Goal gradient (Kivetz, Urminsky & Zheng 2006, J. Marketing Research
//   43(1)): customers speed up as the reward gets closer. The gap to the
//   next tier is translated into a flight you can book.
//
// Miles are feedback about studying already done, never a wage for it
// (Deci, Koestner & Ryan 1999): nothing needed to study sits behind them.

enum VoyageMiles {
    /// Credited at the first departure (any logbook entry means a pass was torn).
    static let welcomeBonusMiles: Double = 500
    static let welcomeBonusReason = "Welcome aboard. 500 miles for your first departure."
    static let explainer = "Miles are the real distance you flew. Longer sessions, more miles."

    static func hasDeparted(_ entries: [LogbookEntry]) -> Bool { !entries.isEmpty }

    static func bonusMiles(_ entries: [LogbookEntry]) -> Double {
        hasDeparted(entries) ? welcomeBonusMiles : 0
    }

    /// Flown miles plus the welcome bonus: what tiers are measured in.
    /// Logbook "Total miles" stays the flown distance only.
    static func statusMiles(_ entries: [LogbookEntry]) -> Double {
        LogbookStats.totalMiles(entries) + bonusMiles(entries)
    }
}

/// Where a traveler stands on the way to the next tier, folded once for the
/// Home card, the upgrade sheet and the membership card.
struct MilesProgress: Equatable {
    let flownMiles: Double
    let bonusMiles: Double
    let tier: FlyerTier
    let next: FlyerTier?

    var statusMiles: Double { flownMiles + bonusMiles }

    init(flownMiles: Double, bonusMiles: Double, tier: FlyerTier) {
        self.flownMiles = flownMiles
        self.bonusMiles = bonusMiles
        self.tier = tier
        self.next = tier.next
    }

    init(entries: [LogbookEntry]) {
        self.init(flownMiles: LogbookStats.totalMiles(entries),
                  bonusMiles: VoyageMiles.bonusMiles(entries),
                  tier: LogbookStats.tier(entries))
    }

    /// Miles still needed for the next tier; zero at Platinum.
    var remaining: Double {
        guard let next else { return 0 }
        return max(0, next.threshold - statusMiles)
    }

    /// Span of the current band, from this tier's threshold to the next.
    private var band: ClosedRange<Double>? {
        guard let next else { return nil }
        return tier.threshold...next.threshold
    }

    /// Fraction of the band covered, 0...1. A tier reached by pilot rating
    /// rather than miles can sit below its own threshold; it reads as 0.
    var fraction: Double {
        guard let band else { return 1 }
        let span = band.upperBound - band.lowerBound
        return min(1, max(0, (statusMiles - band.lowerBound) / span))
    }

    /// The welcome bonus as the bar's first segment, only while it sits in
    /// the band being shown (Member to Silver).
    var bonusFraction: Double {
        guard let band, bonusMiles > 0, band.lowerBound < bonusMiles else { return 0 }
        let span = band.upperBound - band.lowerBound
        return min(fraction, (bonusMiles - band.lowerBound) / span)
    }

    /// 80% of the way: the card takes the accent colour and says so.
    var isAlmostThere: Bool { next != nil && fraction >= 0.8 }

    /// Miles past this tier's threshold that carry into the next band after
    /// a tier-up. Post-reward resetting (Kivetz et al. 2006): the bar never
    /// shows zero right after a reward.
    var carriedOver: Double { max(0, statusMiles - tier.threshold) }

    /// "1,240 miles to Silver", "Almost Silver", "Platinum. Top of the program."
    var headline: String {
        guard let next else { return "\(tier.rawValue). Top of the program." }
        if isAlmostThere { return "Almost \(next.rawValue). \(MilesFormat.miles(remaining)) to go." }
        return "\(MilesFormat.miles(remaining)) to \(next.rawValue)"
    }
}

/// The gap to the next tier as a flight you can take.
struct MilesRouteSuggestion: Equatable {
    let origin: Airport
    let destination: Airport
    let miles: Double
    let focusSeconds: TimeInterval
    /// Flights of this route needed to cover the gap.
    let trips: Int

    var routeText: String { "\(origin.code)–\(destination.code)" }

    /// "SFO–LAX gets you there.", "SFO–LAX (1h 25m) twice gets you there."
    var sentence: String {
        let duration = PilotRatings.hoursText(focusSeconds)
        switch trips {
        case 1: return "\(routeText) (\(duration)) gets you there."
        case 2: return "\(routeText) (\(duration)) twice gets you there."
        default: return "\(routeText) (\(duration)) \(trips) times gets you there."
        }
    }

    /// Hours of flying when no route covers the gap in a handful of trips.
    static func hoursSentence(remaining: Double) -> String {
        // About 450 statute miles per block hour on the catalog's routes.
        let hours = max(1, Int((remaining / 450).rounded(.up)))
        return "About \(hours) h of flying."
    }

    /// The bookable route from `origin` that covers `remaining` in the
    /// fewest trips, shortest flight first on a tie. Nil when nothing is
    /// needed or no route covers it within `maxTrips`.
    static func best(
        remaining: Double,
        from origin: Airport,
        standing: LoyaltyStanding,
        bypass: Bool = false,
        maxTrips: Int = 12
    ) -> MilesRouteSuggestion? {
        guard remaining > 0 else { return nil }
        let open = LoyaltyProgram.destinations(from: origin, standing: standing, bypass: bypass)
            .filter(\.isUnlocked)
        let candidates: [MilesRouteSuggestion] = open.compactMap { access in
            let itinerary = RoutePlanner.itinerary(from: origin, to: access.airport)
            let miles = itinerary.totalMiles
            guard miles > 0 else { return nil }
            let trips = Int((remaining / miles).rounded(.up))
            guard trips <= maxTrips else { return nil }
            return MilesRouteSuggestion(origin: origin, destination: access.airport,
                                        miles: miles,
                                        focusSeconds: itinerary.totalFocusDuration,
                                        trips: trips)
        }
        return candidates.min { lhs, rhs in
            if lhs.trips != rhs.trips { return lhs.trips < rhs.trips }
            if lhs.miles != rhs.miles { return lhs.miles < rhs.miles }
            return lhs.destination.code < rhs.destination.code
        }
    }
}

enum MilesFormat {
    /// "1,240 miles", "1 mile".
    static func miles(_ value: Double) -> String {
        let whole = Int(value.rounded(.up))
        return "\(number(Double(whole))) \(whole == 1 ? "mile" : "miles")"
    }

    static func number(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value.rounded())) ?? "\(Int(value))"
    }
}
