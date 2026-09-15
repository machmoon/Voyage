import Foundation

/// The study coach under the recorder: when to book the next flight, how long
/// to book it for, and which study methods to pack into it.
///
/// Two parts, both deterministic and both read from the logbook alone.
///
/// The plan describes; it does not compare. The recorder owns every "more
/// often than" claim and holds it to non-overlapping 95% intervals, so the
/// plan only restates what the traveler's landed flights look like (a median
/// length, the band most of them left in) and defers to a recorder finding
/// whenever one exists. That split follows Anki's Hourly Breakdown
/// (ankitects/anki, rslib/src/stats/graphs/hours.rs and
/// ts/routes/graphs/hours.ts), which shows the per-hour success rate from the
/// user's own reviews and never names a "best" hour on its own authority.
///
/// The methods are fixed text, ordered by what the logbook shows. No
/// open-source study or focus app we could find ships technique advice in
/// code (Super Productivity's metric constants in
/// src/app/features/metric/metric-scoring.util.ts are the nearest thing and
/// are not advice), so the wording is ours. The methods themselves are the
/// best-replicated findings in learning research: retrieval practice
/// (Roediger and Karpicke, 2006), spaced review (Cepeda et al., 2008),
/// interleaved practice (Brunmair and Richter, 2019 meta-analysis), specific
/// goals, and short breaks between sessions.
enum StudyCoach {
    /// Landed flights the plan needs before it will describe a pattern.
    static let minimumLanded = 3
    /// How far back the plan looks, newest first.
    static let recentLandedLimit = 10

    struct Plan: Equatable {
        /// One sentence: what to book next.
        let headline: String
        /// The numbers behind it, in one or two sentences.
        let detail: String
        /// Minutes to book, rounded to five. `nil` before there is a history.
        let suggestedMinutes: Int?
        /// The departure band to book in, when the logbook points to one.
        let band: DepartureBand?
    }

    enum Method: String, CaseIterable, Identifiable {
        case activeRecall
        case spacedReview
        case interleaving
        case specificBags
        case phoneAway
        case breaks

        var id: String { rawValue }

        var title: String {
            switch self {
            case .activeRecall: return "Recall before you reread"
            case .spacedReview: return "Space the same topic out"
            case .interleaving: return "Mix problem types"
            case .specificBags: return "Pack bags you can finish"
            case .phoneAway: return "Put the phone out of reach"
            case .breaks: return "Rest between flights"
            }
        }

        var body: String {
            switch self {
            case .activeRecall:
                return "Close the notes and write down what you remember, then check what you missed. Testing yourself holds more than reading it again."
            case .spacedReview:
                return "Fly the same topic again one day later, then three days, then a week. Short reviews spread out beat one long session."
            case .interleaving:
                return "Put problems from different chapters in one bag instead of twenty of the same kind, so you practise choosing the method."
            case .specificBags:
                return "\"Problems 1 to 10\" is a bag you can claim. \"Study calculus\" is not. Name the page, the set or the section."
            case .phoneAway:
                return "Leaving the app ends the flight after 30 seconds. Turn on a Focus and put the phone face down before you tear the pass."
            case .breaks:
                return "Take 5 to 10 minutes away from the desk after you land, then book the next flight."
            }
        }
    }

    // MARK: Plan

    static func plan(flights: [RecordedFlight], report: FlightDataReport,
                     calendar: Calendar = .current) -> Plan {
        let landed = flights
            .filter(\.arrived)
            .sorted { $0.endedAt > $1.endedAt }
            .prefix(recentLandedLimit)

        guard landed.count >= minimumLanded else {
            return Plan(
                headline: "Start with a flight under an hour.",
                detail: "Land \(pluralized(minimumLanded - landed.count, "more flight")) and the coach will suggest a length and a time from your own logbook.",
                suggestedMinutes: nil,
                band: nil
            )
        }

        // Length: the median booked time of recent landed flights, capped
        // under the recorder's block-time ceiling when it found one.
        let booked = landed.map { $0.scheduledSeconds ?? $0.focusSeconds }.sorted()
        var minutes = roundedToFive(median(booked) / 60)
        let ceiling = subjectLabel(of: .blockTime, in: report)
            .flatMap { label in BlockTimeDetector.splitPoints.first { label == "Under \($0.shortDurationText)" } }
        if let ceiling, Double(minutes * 60) >= ceiling {
            minutes = max(15, roundedToFive(ceiling / 60) - 5)
        }

        // Time: the recorder's departure-time finding wins; otherwise the band
        // most recent landed flights left in, when a clear majority did.
        let recorderBand = subjectLabel(of: .departureTime, in: report)
            .flatMap { label in DepartureBand.allCases.first { $0.label == label } }

        var bandCounts: [DepartureBand: Int] = [:]
        for flight in landed {
            guard let departed = flight.departedAt else { continue }
            bandCounts[DepartureBand(hour: calendar.component(.hour, from: departed)), default: 0] += 1
        }
        let timed = bandCounts.values.reduce(0, +)
        let commonest = bandCounts.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key.sortIndex > rhs.key.sortIndex : lhs.value < rhs.value
        }
        let habitBand = commonest.flatMap { $0.value * 2 > timed && $0.value >= minimumLanded ? $0.key : nil }
        let band = recorderBand ?? habitBand

        let lengthText = TimeInterval(minutes * 60).shortDurationText
        let headline = band.map { "Book about \(lengthText), \($0.phrase)." } ?? "Book about \(lengthText)."

        var detail = "Your last \(pluralized(landed.count, "landed flight")) ran a median of \(lengthText)."
        if let ceiling, minutes * 60 < Int(ceiling) {
            detail += " Flights of \(ceiling.shortDurationText) and longer land less often for you."
        }
        if let recorderBand, recorderBand == band {
            detail += " Flights \(recorderBand.phrase) land more often for you."
        } else if let habitBand, let count = bandCounts[habitBand] {
            detail += " \(count) of the \(timed) with a recorded departure left \(habitBand.phrase)."
        }

        return Plan(headline: headline, detail: detail, suggestedMinutes: minutes, band: band)
    }

    // MARK: Methods

    /// Every method, with the ones the logbook argues for first.
    static func methods(report: FlightDataReport) -> [Method] {
        var first: [Method] = []
        let kinds = Set(report.findings.map(\.kind))
        if kinds.contains(.bags) { first.append(.specificBags) }
        if kinds.contains(.interruption) { first.append(.phoneAway) }
        let rest = Method.allCases.filter { !first.contains($0) }
        return first + rest
    }

    // MARK: Helpers

    /// The highlighted evidence row of a recorder finding: the band or length
    /// the finding is about, in the recorder's own label.
    static func subjectLabel(of kind: FindingKind, in report: FlightDataReport) -> String? {
        report.findings.first { $0.kind == kind }?.evidence.first(where: \.isSubject)?.label
    }

    static func median(_ sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    static func roundedToFive(_ minutes: Double) -> Int {
        max(5, Int((minutes / 5).rounded()) * 5)
    }
}

private extension DepartureBand {
    var sortIndex: Int { DepartureBand.allCases.firstIndex(of: self) ?? 0 }
}
