import Foundation

// MARK: - Wilson score interval
//
// Ported from reddit's confidence sort, r2/r2/lib/db/_sorts.pyx, function
// `_confidence(ups, downs)`:
//
//     left  = p + 1/(2*n)*z*z
//     right = z*sqrt(p*(1-p)/n + z*z/(4*n*n))
//     under = 1+1/n*z*z
//     return (left - right) / under
//
// Two deliberate changes from that source. reddit keeps only the lower
// bound, because it is ranking; the recorder needs both bounds, because it
// is deciding whether two rates are actually distinguishable. And reddit
// uses z = 1.2815 (80%), which is right for ordering a feed and far too
// loose for telling a student something about themselves, so the recorder
// uses 1.96 (95%).
//
// Wilson rather than the textbook normal interval for the reason Evan
// Miller gives in the post reddit cites: at small n, and at rates near 0
// or 1, the normal interval is wrong in exactly the cases a new logbook
// consists of.

/// A binomial proportion with a Wilson score interval around it.
struct RateInterval: Equatable {
    let successes: Int
    let trials: Int
    let lower: Double
    let upper: Double

    static let z95 = 1.959963984540054

    init(successes: Int, trials: Int, z: Double = RateInterval.z95) {
        self.successes = max(0, successes)
        self.trials = max(0, trials)
        guard trials > 0 else {
            lower = 0
            upper = 0
            return
        }
        let n = Double(trials)
        let p = Double(self.successes) / n
        let denominator = 1 + z * z / n
        let centre = p + z * z / (2 * n)
        let spread = z * (p * (1 - p) / n + z * z / (4 * n * n)).squareRoot()
        lower = max(0, (centre - spread) / denominator)
        upper = min(1, (centre + spread) / denominator)
    }

    var rate: Double { trials > 0 ? Double(successes) / Double(trials) : 0 }

    /// How far this interval sits above `other` with no overlap. Zero when
    /// the intervals touch or cross, which is the recorder's whole gate:
    /// overlapping intervals mean the difference could be luck, and a
    /// finding that could be luck does not get shown.
    func separation(above other: RateInterval) -> Double {
        max(0, lower - other.upper)
    }
}

// MARK: - Corpus

/// One flight, flattened out of SwiftData into a plain value so every
/// detector reads the same normalised record and tests can build one
/// without a model container.
struct RecordedFlight: Equatable {
    /// When the flight ended.
    let endedAt: Date
    /// When the pass was torn. `nil` on rows written before this was recorded.
    let departedAt: Date?
    let outcome: FlightOutcome
    /// Booked block time. `nil` on rows written before this was recorded.
    let scheduledSeconds: TimeInterval?
    let focusSeconds: TimeInterval
    let destinationCode: String
    /// Checked bags and whether each was claimed at the carousel.
    let bags: [(label: String, claimed: Bool)]

    var arrived: Bool { outcome.didArrive }

    static func == (lhs: RecordedFlight, rhs: RecordedFlight) -> Bool {
        lhs.endedAt == rhs.endedAt
            && lhs.departedAt == rhs.departedAt
            && lhs.outcome == rhs.outcome
            && lhs.scheduledSeconds == rhs.scheduledSeconds
            && lhs.focusSeconds == rhs.focusSeconds
            && lhs.destinationCode == rhs.destinationCode
            && lhs.bags.map(\.label) == rhs.bags.map(\.label)
            && lhs.bags.map(\.claimed) == rhs.bags.map(\.claimed)
    }

    init(entry: LogbookEntry) {
        endedAt = entry.date
        departedAt = entry.departedAt
        outcome = entry.outcome
        scheduledSeconds = entry.scheduledSeconds > 0 ? entry.scheduledSeconds : nil
        focusSeconds = entry.focusSeconds
        destinationCode = entry.destinationCode
        let claims = entry.intentionsCompleted
        bags = entry.intentions.enumerated().map { index, label in
            (label: label, claimed: index < claims.count ? claims[index] : false)
        }
    }

    init(endedAt: Date,
         departedAt: Date? = nil,
         outcome: FlightOutcome,
         scheduledSeconds: TimeInterval? = nil,
         focusSeconds: TimeInterval = 0,
         destinationCode: String = "JFK",
         bags: [(label: String, claimed: Bool)] = []) {
        self.endedAt = endedAt
        self.departedAt = departedAt
        self.outcome = outcome
        self.scheduledSeconds = scheduledSeconds
        self.focusSeconds = focusSeconds
        self.destinationCode = destinationCode
        self.bags = bags
    }
}

/// The flights a report is computed from, plus the calendar that decides
/// what "evening" and "weekend" mean. The calendar is injected rather than
/// read from `.current` so the hour and weekday buckets are testable across
/// time zones and across a DST shift, where a flight's UTC offset changes
/// but the wall clock the student experienced does not.
struct FlightCorpus {
    let flights: [RecordedFlight]
    let calendar: Calendar

    init(flights: [RecordedFlight], calendar: Calendar = .current) {
        self.flights = flights
        self.calendar = calendar
    }

    init(entries: [LogbookEntry], calendar: Calendar = .current) {
        self.init(flights: entries.map(RecordedFlight.init(entry:)), calendar: calendar)
    }

    var count: Int { flights.count }

    /// Flights whose departure moment was recorded. Older rows are excluded
    /// from time-of-day work rather than guessed at from the arrival time.
    var timestamped: [RecordedFlight] { flights.filter { $0.departedAt != nil } }

    /// Local wall-clock hour of departure, per the injected calendar.
    func departureHour(_ flight: RecordedFlight) -> Int? {
        guard let departed = flight.departedAt else { return nil }
        return calendar.component(.hour, from: departed)
    }

    func isWeekend(_ flight: RecordedFlight) -> Bool? {
        guard let departed = flight.departedAt else { return nil }
        return calendar.isDateInWeekend(departed)
    }
}

// MARK: - Findings

/// The subject a finding is about. One case per detector: a detector that
/// cannot produce a distinguishable result produces nothing, so at most one
/// finding of each kind ever appears in a report.
enum FindingKind: String, CaseIterable {
    case departureTime
    case blockTime
    case weekPattern
    case bags
    case interruption
    case recentForm

    /// Uppercase strap line above the headline, in the app's field-label voice.
    var label: String {
        switch self {
        case .departureTime: return "Departure time"
        case .blockTime: return "Block time"
        case .weekPattern: return "Week pattern"
        case .bags: return "Checked bags"
        case .interruption: return "Interruptions"
        case .recentForm: return "Recent form"
        }
    }
}

/// Borrowed from Lighthouse's audit result shape
/// (GoogleChrome/lighthouse, core/audits/audit.js): an audit either scores
/// a comparison or declares itself informative, and the report renders the
/// two differently instead of pretending an unscored result is a verdict.
enum FindingMode {
    /// Two groups whose confidence intervals do not overlap.
    case comparative
    /// A composition worth stating, with no claim that it is a difference.
    case informative
}

/// One row of the evidence table under a finding. Carries the interval as
/// well as the point estimate so the screen can draw the uncertainty
/// instead of hiding it behind a percentage.
struct FindingEvidence: Identifiable, Equatable {
    let label: String
    let interval: RateInterval
    /// The group the headline is about.
    let isSubject: Bool

    var id: String { label }
    var countText: String { "\(interval.successes)/\(interval.trials)" }
    var percentText: String { "\(Int((interval.rate * 100).rounded()))%" }
}

/// A single statement the recorder is prepared to stand behind.
struct Finding: Identifiable, Equatable {
    let kind: FindingKind
    let mode: FindingMode
    /// One plain sentence. Never a verdict on the person.
    let headline: String
    /// The numbers behind the headline, spelled out.
    let detail: String
    let evidence: [FindingEvidence]
    /// Flights this finding was computed from.
    let support: Int
    /// Gap between the two confidence intervals, 0 for informative findings.
    /// Used only for ordering.
    let separation: Double

    var id: String { kind.rawValue }

    static func == (lhs: Finding, rhs: Finding) -> Bool {
        lhs.kind == rhs.kind && lhs.headline == rhs.headline && lhs.detail == rhs.detail
    }
}

/// What the recorder has to say, including the case where it has nothing.
struct FlightDataReport: Equatable {
    let flightsAnalyzed: Int
    let findings: [Finding]
    /// Flights still needed before the recorder will report at all.
    /// Zero once the corpus is large enough, whether or not it found anything.
    let flightsUntilReporting: Int

    var isReporting: Bool { flightsUntilReporting == 0 }

    static let empty = FlightDataReport(flightsAnalyzed: 0, findings: [], flightsUntilReporting: FlightDataRecorder.minimumFlights)
}

// MARK: - Detectors

protocol FindingDetector {
    var kind: FindingKind { get }
    /// Flights this detector needs in its own smallest group before it will
    /// speak. Separate from the corpus minimum: a detector can be starved
    /// even when the logbook as a whole is large.
    var minimumGroup: Int { get }
    func evaluate(_ corpus: FlightCorpus) -> Finding?
}

extension FindingDetector {
    var minimumGroup: Int { FlightDataRecorder.minimumGroup }

    /// The shared gate. Two groups, each at least `minimumGroup` flights,
    /// and 95% Wilson intervals that do not overlap. Anything else returns
    /// nil and the finding is never built.
    func compare(subject: RateInterval, rest: RateInterval) -> Double? {
        guard subject.trials >= minimumGroup, rest.trials >= minimumGroup else { return nil }
        let gap = subject.separation(above: rest)
        guard gap > 0 else { return nil }
        return gap
    }
}

/// Which part of the day a flight pushed back in. Bands rather than raw
/// hours because 24 buckets can never reach a usable sample in a logbook
/// this size, and because "evening" is the unit a student actually
/// schedules in.
enum DepartureBand: String, CaseIterable {
    case early, morning, afternoon, evening, late

    init(hour: Int) {
        switch hour {
        case 5..<9: self = .early
        case 9..<13: self = .morning
        case 13..<17: self = .afternoon
        case 17..<21: self = .evening
        default: self = .late
        }
    }

    var label: String {
        switch self {
        case .early: return "05 to 09"
        case .morning: return "09 to 13"
        case .afternoon: return "13 to 17"
        case .evening: return "17 to 21"
        case .late: return "21 to 05"
        }
    }

    var phrase: String {
        switch self {
        case .early: return "before 9am"
        case .morning: return "between 9am and 1pm"
        case .afternoon: return "between 1pm and 5pm"
        case .evening: return "between 5pm and 9pm"
        case .late: return "after 9pm"
        }
    }
}

/// Does the hour a flight leaves at change whether it lands?
struct DepartureTimeDetector: FindingDetector {
    let kind = FindingKind.departureTime

    func evaluate(_ corpus: FlightCorpus) -> Finding? {
        let flights = corpus.timestamped
        guard flights.count >= FlightDataRecorder.minimumFlights else { return nil }

        var grouped: [DepartureBand: [RecordedFlight]] = [:]
        for flight in flights {
            guard let hour = corpus.departureHour(flight) else { continue }
            grouped[DepartureBand(hour: hour), default: []].append(flight)
        }

        var best: (band: DepartureBand, subject: RateInterval, rest: RateInterval, gap: Double)?
        for band in DepartureBand.allCases {
            guard let inBand = grouped[band] else { continue }
            let others = flights.filter { flight in
                guard let hour = corpus.departureHour(flight) else { return false }
                return DepartureBand(hour: hour) != band
            }
            let subject = RateInterval(successes: inBand.filter(\.arrived).count, trials: inBand.count)
            let rest = RateInterval(successes: others.filter(\.arrived).count, trials: others.count)
            guard let gap = compare(subject: subject, rest: rest) else { continue }
            if gap > (best?.gap ?? 0) { best = (band, subject, rest, gap) }
        }
        guard let best else { return nil }

        let evidence = DepartureBand.allCases.compactMap { band -> FindingEvidence? in
            guard let inBand = grouped[band], !inBand.isEmpty else { return nil }
            return FindingEvidence(
                label: band.label,
                interval: RateInterval(successes: inBand.filter(\.arrived).count, trials: inBand.count),
                isSubject: band == best.band
            )
        }

        return Finding(
            kind: kind,
            mode: .comparative,
            headline: "Your flights \(best.band.phrase) reach the gate more often.",
            detail: "\(best.subject.successes) of \(best.subject.trials) landed, against \(best.rest.successes) of \(best.rest.trials) at every other hour.",
            evidence: evidence,
            support: flights.count,
            separation: best.gap
        )
    }
}

/// Is there a length past which flights stop landing? Rather than
/// comparing one bucket against the rest, this walks candidate split points
/// and reports the shortest booked block time at which the two sides
/// separate, because the useful answer is a ceiling, not a category.
struct BlockTimeDetector: FindingDetector {
    let kind = FindingKind.blockTime

    /// Split points in seconds: 45m, 1h30, 3h. Chosen to match the block
    /// times `RouteCatalog` actually ships, not round numbers for their
    /// own sake.
    static let splitPoints: [TimeInterval] = [45 * 60, 90 * 60, 180 * 60]

    func evaluate(_ corpus: FlightCorpus) -> Finding? {
        let flights = corpus.flights.filter { $0.scheduledSeconds != nil }
        guard flights.count >= FlightDataRecorder.minimumFlights else { return nil }

        for split in Self.splitPoints {
            let shorter = flights.filter { ($0.scheduledSeconds ?? 0) < split }
            let longer = flights.filter { ($0.scheduledSeconds ?? 0) >= split }
            let shortInterval = RateInterval(successes: shorter.filter(\.arrived).count, trials: shorter.count)
            let longInterval = RateInterval(successes: longer.filter(\.arrived).count, trials: longer.count)
            guard let gap = compare(subject: shortInterval, rest: longInterval) else { continue }

            let evidence = [
                FindingEvidence(label: "Under \(split.shortDurationText)", interval: shortInterval, isSubject: true),
                FindingEvidence(label: "\(split.shortDurationText) and over", interval: longInterval, isSubject: false),
            ]
            return Finding(
                kind: kind,
                mode: .comparative,
                headline: "Past \(split.shortDurationText), fewer of your flights reach the gate.",
                detail: "Under \(split.shortDurationText) you land \(shortInterval.successes) of \(shortInterval.trials). At \(split.shortDurationText) and longer, \(longInterval.successes) of \(longInterval.trials).",
                evidence: evidence,
                support: flights.count,
                separation: gap
            )
        }
        return nil
    }
}

/// Weekday against weekend. Two groups rather than seven, because seven
/// weekday buckets would need roughly 35 flights before any of them could
/// clear the group minimum.
struct WeekPatternDetector: FindingDetector {
    let kind = FindingKind.weekPattern

    func evaluate(_ corpus: FlightCorpus) -> Finding? {
        let flights = corpus.timestamped
        guard flights.count >= FlightDataRecorder.minimumFlights else { return nil }

        let weekend = flights.filter { corpus.isWeekend($0) == true }
        let weekday = flights.filter { corpus.isWeekend($0) == false }
        let weekendInterval = RateInterval(successes: weekend.filter(\.arrived).count, trials: weekend.count)
        let weekdayInterval = RateInterval(successes: weekday.filter(\.arrived).count, trials: weekday.count)

        let subject: (name: String, interval: RateInterval)
        let other: (name: String, interval: RateInterval)
        if let gap = compare(subject: weekdayInterval, rest: weekendInterval) {
            subject = ("Weekdays", weekdayInterval)
            other = ("Weekends", weekendInterval)
            return build(subject: subject, other: other, gap: gap, support: flights.count)
        }
        if let gap = compare(subject: weekendInterval, rest: weekdayInterval) {
            subject = ("Weekends", weekendInterval)
            other = ("Weekdays", weekdayInterval)
            return build(subject: subject, other: other, gap: gap, support: flights.count)
        }
        return nil
    }

    private func build(subject: (name: String, interval: RateInterval),
                       other: (name: String, interval: RateInterval),
                       gap: Double,
                       support: Int) -> Finding {
        Finding(
            kind: kind,
            mode: .comparative,
            headline: "\(subject.name) carry more of your completed flights.",
            detail: "\(subject.name.lowercased()): \(subject.interval.successes) of \(subject.interval.trials) landed. \(other.name.lowercased()): \(other.interval.successes) of \(other.interval.trials).",
            evidence: [
                FindingEvidence(label: subject.name, interval: subject.interval, isSubject: true),
                FindingEvidence(label: other.name, interval: other.interval, isSubject: false),
            ],
            support: support,
            separation: gap
        )
    }
}

/// Which checked bag never comes off the carousel. Compares one bag label
/// against every other bag the traveler has ever checked.
struct BagDetector: FindingDetector {
    let kind = FindingKind.bags
    /// Four, the mechanical floor rather than the corpus-wide six. A bag
    /// label is a rarer event than a flight, and at four the gate still
    /// admits only a label that was missed every single time while the
    /// others were claimed every single time. That is a fact worth stating,
    /// and it is not a marginal one.
    let minimumGroup = 4

    func evaluate(_ corpus: FlightCorpus) -> Finding? {
        // Only flights that reached the carousel can tell us whether a bag
        // arrived. A diverted flight's bags are unclaimed for a reason that
        // has nothing to do with the bag.
        let landed = corpus.flights.filter(\.arrived)
        var byLabel: [String: (claimed: Int, total: Int, display: String)] = [:]
        for flight in landed {
            for bag in flight.bags {
                let key = bag.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !key.isEmpty else { continue }
                var bucket = byLabel[key] ?? (0, 0, bag.label.trimmingCharacters(in: .whitespacesAndNewlines))
                bucket.claimed += bag.claimed ? 1 : 0
                bucket.total += 1
                byLabel[key] = bucket
            }
        }
        guard byLabel.count >= 2 else { return nil }

        var worst: (display: String, subject: RateInterval, rest: RateInterval, gap: Double)?
        for (key, bucket) in byLabel {
            let others = byLabel.filter { $0.key != key }.values
            let otherClaimed = others.reduce(0) { $0 + $1.claimed }
            let otherTotal = others.reduce(0) { $0 + $1.total }
            let subject = RateInterval(successes: bucket.claimed, trials: bucket.total)
            let rest = RateInterval(successes: otherClaimed, trials: otherTotal)
            // Inverted: the finding is about the bag that lags the rest.
            guard let gap = compare(subject: rest, rest: subject) else { continue }
            if gap > (worst?.gap ?? 0) { worst = (bucket.display, subject, rest, gap) }
        }
        guard let worst else { return nil }

        return Finding(
            kind: kind,
            mode: .comparative,
            headline: "\(worst.display) comes off the carousel less than your other bags.",
            detail: "Claimed on \(worst.subject.successes) of \(worst.subject.trials) landed flights. Every other bag: \(worst.rest.successes) of \(worst.rest.trials).",
            evidence: [
                FindingEvidence(label: worst.display, interval: worst.subject, isSubject: true),
                FindingEvidence(label: "Every other bag", interval: worst.rest, isSubject: false),
            ],
            support: landed.count,
            separation: worst.gap
        )
    }
}

/// What actually ends the flights that do not land. Informative: it states
/// a composition and makes no claim that one cause is significantly larger.
struct InterruptionDetector: FindingDetector {
    let kind = FindingKind.interruption
    let minimumGroup = 5

    func evaluate(_ corpus: FlightCorpus) -> Finding? {
        let known = corpus.flights.filter { !$0.arrived && $0.outcome != .unknown }
        guard known.count >= minimumGroup else { return nil }

        let interrupted = known.filter { $0.outcome == .interrupted }.count
        let leftEarly = known.filter { $0.outcome == .leftEarly }.count
        let missed = known.filter { $0.outcome == .missedConnection }.count

        var evidence: [FindingEvidence] = []
        let total = known.count
        if interrupted > 0 {
            evidence.append(FindingEvidence(label: "Left the app", interval: RateInterval(successes: interrupted, trials: total), isSubject: interrupted >= leftEarly && interrupted >= missed))
        }
        if leftEarly > 0 {
            evidence.append(FindingEvidence(label: "Ended on purpose", interval: RateInterval(successes: leftEarly, trials: total), isSubject: leftEarly > interrupted && leftEarly >= missed))
        }
        if missed > 0 {
            evidence.append(FindingEvidence(label: "Missed connection", interval: RateInterval(successes: missed, trials: total), isSubject: missed > interrupted && missed > leftEarly))
        }
        guard evidence.count >= 2 else { return nil }

        return Finding(
            kind: kind,
            mode: .informative,
            headline: "Most of your diversions happen the same way.",
            detail: "Of \(total) flights that did not land, \(interrupted) ended because the app went to the background, \(leftEarly) were ended from the cabin, and \(missed) ran out the layover clock.",
            evidence: evidence,
            support: total,
            separation: 0
        )
    }
}

/// The last block of flights against the block before it. The one finding
/// that is allowed to be about change over time.
struct RecentFormDetector: FindingDetector {
    let kind = FindingKind.recentForm
    /// Eight a side. Below that a single flight moves the rate by more
    /// than 12 points and the comparison is noise dressed as a trend.
    let minimumGroup = 8
    static let window = 24

    func evaluate(_ corpus: FlightCorpus) -> Finding? {
        let ordered = corpus.flights.sorted { $0.endedAt < $1.endedAt }
        let recent = Array(ordered.suffix(Self.window))
        guard recent.count >= minimumGroup * 2 else { return nil }

        let half = recent.count / 2
        let earlier = Array(recent.prefix(half))
        let later = Array(recent.suffix(recent.count - half))
        let earlierInterval = RateInterval(successes: earlier.filter(\.arrived).count, trials: earlier.count)
        let laterInterval = RateInterval(successes: later.filter(\.arrived).count, trials: later.count)

        let rising = compare(subject: laterInterval, rest: earlierInterval)
        let falling = compare(subject: earlierInterval, rest: laterInterval)
        guard let gap = rising ?? falling else { return nil }

        let headline = rising != nil
            ? "Your last \(later.count) flights land more often than the \(earlier.count) before them."
            : "Your last \(later.count) flights land less often than the \(earlier.count) before them."

        return Finding(
            kind: kind,
            mode: .comparative,
            headline: headline,
            detail: "Latest \(later.count): \(laterInterval.successes) landed. Previous \(earlier.count): \(earlierInterval.successes) landed.",
            evidence: [
                FindingEvidence(label: "Latest \(later.count)", interval: laterInterval, isSubject: rising != nil),
                FindingEvidence(label: "Previous \(earlier.count)", interval: earlierInterval, isSubject: rising == nil),
            ],
            support: recent.count,
            separation: gap
        )
    }
}

// MARK: - Recorder

/// Reads the logbook and reports only what the numbers actually support.
///
/// The design rule, and the reason the thresholds are as high as they are:
/// a wrong finding costs far more than a missing one. A student told that
/// they focus best in the evening on the strength of four flights will
/// rearrange their week around a coin flip. So every comparative finding
/// has to clear two gates, a minimum group size and non-overlapping 95%
/// Wilson intervals, and the recorder stays silent otherwise.
enum FlightDataRecorder {

    /// Flights in the logbook before the recorder reports anything at all.
    ///
    /// Twelve: `minimumGroup` on each side of a comparison. Below that the
    /// recorder could only ever produce silence, so it says how far off it
    /// is instead of showing an empty screen.
    static let minimumFlights = 12

    /// Flights required in each side of a comparison.
    ///
    /// The mechanical floor is four. At n = 4 the only split that clears a
    /// 95% Wilson gate is a perfect one, 4/4 against 0/4, and it clears by
    /// 0.02 (lower 0.510 against upper 0.490); at n = 3 even a perfect split
    /// overlaps. Six is deliberately above that floor, because a finding
    /// that depends on a flawless record and a rounding margin is a finding
    /// one unlucky evening would have erased. At n = 6 the perfect split
    /// separates by 0.22 (0.610 against 0.390), and imperfect records can
    /// clear it too.
    static let minimumGroup = 6

    static let detectors: [any FindingDetector] = [
        DepartureTimeDetector(),
        BlockTimeDetector(),
        WeekPatternDetector(),
        BagDetector(),
        InterruptionDetector(),
        RecentFormDetector(),
    ]

    static func report(entries: [LogbookEntry], calendar: Calendar = .current) -> FlightDataReport {
        report(corpus: FlightCorpus(entries: entries, calendar: calendar))
    }

    static func report(corpus: FlightCorpus) -> FlightDataReport {
        guard corpus.count >= minimumFlights else {
            return FlightDataReport(
                flightsAnalyzed: corpus.count,
                findings: [],
                flightsUntilReporting: minimumFlights - corpus.count
            )
        }

        let findings = detectors
            .compactMap { $0.evaluate(corpus) }
            .sorted { lhs, rhs in
                // Comparative findings first, then by how cleanly the two
                // intervals separate. Ties break on the detector's declared
                // order so the screen does not reshuffle between launches.
                if (lhs.mode == .comparative) != (rhs.mode == .comparative) {
                    return lhs.mode == .comparative
                }
                if lhs.separation != rhs.separation { return lhs.separation > rhs.separation }
                let order = FindingKind.allCases
                return (order.firstIndex(of: lhs.kind) ?? 0) < (order.firstIndex(of: rhs.kind) ?? 0)
            }

        return FlightDataReport(
            flightsAnalyzed: corpus.count,
            findings: findings,
            flightsUntilReporting: 0
        )
    }
}
