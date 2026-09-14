import Foundation

/// The logbook as one Markdown string: the debrief prompt first, then a
/// 90-day summary, then the recorder's findings with their intervals, then
/// the last 20 flights as CSV rows. The traveler reads the text before it
/// leaves the device; nothing here talks to a model.
///
/// Shape follows nicepkg/ctxport's Markdown serializer
/// (github.com/nicepkg/ctxport, packages/core-markdown/src/serializer.ts):
/// a fixed block the reader needs first, then the sections joined with a
/// blank line, the raw content last. ctxport leads with a metadata
/// frontmatter and ships no prompt; the prompt-first order is the
/// export-and-paste pattern the research memo settled on, and the template
/// text is the one in QA/RESEARCH-2026-09-14.md. Pure and calendar-injected,
/// like `FlightDataRecorder`, so the same logbook exports the same bytes in
/// a test.
enum LogbookExport {
    static let summaryWindowDays = 90
    static let recentFlightLimit = 20

    static let prompt = """
    You are reading a student's focus-session log from Voyage, an app that
    frames study sessions as flights. A flight "lands" when the session runs
    to its planned end; it is "stopped early" when the app was left or the
    session was ended early. "Bags" are tasks the student set out to finish. Use only
    the numbers below. Do not invent data, do not diagnose, do not praise.
    Give three plain observations and one concrete suggestion for next week.
    """

    static func markdown(entries: [LogbookEntry],
                         now: Date,
                         calendar: Calendar = .current) -> String {
        let flights = entries.map(RecordedFlight.init(entry:))
        let rows = entries.map(Row.init(entry:))
        return markdown(flights: flights, rows: rows, now: now, calendar: calendar)
    }

    /// One CSV row's worth of a flight. Separate from `RecordedFlight`
    /// because the recorder does not keep the route or the seat.
    struct Row {
        let endedAt: Date
        let departedAt: Date?
        let originCode: String
        let destinationCode: String
        let scheduledSeconds: TimeInterval?
        let focusSeconds: TimeInterval
        let outcome: FlightOutcome
        let bagsClaimed: Int
        let bagsTotal: Int
        let seat: String

        init(entry: LogbookEntry) {
            endedAt = entry.date
            departedAt = entry.departedAt
            originCode = entry.originCode
            destinationCode = entry.destinationCode
            scheduledSeconds = entry.scheduledSeconds > 0 ? entry.scheduledSeconds : nil
            focusSeconds = entry.focusSeconds
            outcome = entry.outcome
            bagsTotal = entry.intentions.count
            bagsClaimed = entry.intentionsCompleted.prefix(entry.intentions.count).filter { $0 }.count
            seat = entry.seat
        }

        init(endedAt: Date,
             departedAt: Date? = nil,
             originCode: String,
             destinationCode: String,
             scheduledSeconds: TimeInterval? = nil,
             focusSeconds: TimeInterval,
             outcome: FlightOutcome,
             bagsClaimed: Int = 0,
             bagsTotal: Int = 0,
             seat: String = "C10") {
            self.endedAt = endedAt
            self.departedAt = departedAt
            self.originCode = originCode
            self.destinationCode = destinationCode
            self.scheduledSeconds = scheduledSeconds
            self.focusSeconds = focusSeconds
            self.outcome = outcome
            self.bagsClaimed = bagsClaimed
            self.bagsTotal = bagsTotal
            self.seat = seat
        }
    }

    static func markdown(flights: [RecordedFlight],
                         rows: [Row],
                         now: Date,
                         calendar: Calendar = .current) -> String {
        var sections: [String] = [prompt]
        sections.append(summary(rows: rows, now: now, calendar: calendar))
        sections.append(findings(flights: flights, calendar: calendar))
        sections.append(recentFlights(rows: rows, calendar: calendar))
        return sections.joined(separator: "\n\n") + "\n"
    }

    // MARK: Sections

    static func summary(rows: [Row], now: Date, calendar: Calendar) -> String {
        let windowStart = calendar.date(byAdding: .day, value: -summaryWindowDays, to: now) ?? now
        let recent = rows.filter { $0.endedAt >= windowStart && $0.endedAt <= now }
        let landed = recent.filter { $0.outcome.didArrive }

        var lines = ["## Summary (last \(summaryWindowDays) days, all times local)"]
        lines.append("- Flights: \(recent.count), landed \(landed.count) (\(percent(landed.count, of: recent.count)))")

        let planned = recent.compactMap(\.scheduledSeconds).reduce(0, +)
        let completed = recent.reduce(0) { $0 + $1.focusSeconds }
        let plannedMinutes = Int((planned / 60).rounded())
        let completedMinutes = Int((completed / 60).rounded())
        lines.append("- Planned minutes: \(formatted(plannedMinutes)); completed: \(formatted(completedMinutes)) (\(percent(completedMinutes, of: plannedMinutes)))")

        let timestamped = recent.compactMap(\.departedAt)
        if timestamped.isEmpty {
            lines.append("- Departures by band: not recorded")
        } else {
            let bands = DepartureBand.allCases.map { band -> String in
                let count = timestamped.filter { DepartureBand(hour: calendar.component(.hour, from: $0)) == band }.count
                return "\(band.label): \(count)"
            }
            lines.append("- Departures by band: \(bands.joined(separator: ", "))")
        }

        let bagsTotal = recent.reduce(0) { $0 + $1.bagsTotal }
        let bagsClaimed = recent.reduce(0) { $0 + $1.bagsClaimed }
        lines.append("- Bags checked: \(bagsTotal), claimed: \(bagsClaimed) (\(percent(bagsClaimed, of: bagsTotal)))")

        let perWeek = Double(recent.count) / (Double(summaryWindowDays) / 7)
        let gap = longestGapDays(recent.map(\.endedAt), calendar: calendar)
        lines.append("- Flights per week: \(String(format: "%.1f", perWeek)); longest gap: \(gap.map { "\($0) day\($0 == 1 ? "" : "s")" } ?? "n/a")")
        return lines.joined(separator: "\n")
    }

    static func findings(flights: [RecordedFlight], calendar: Calendar) -> String {
        let report = FlightDataRecorder.report(corpus: FlightCorpus(flights: flights, calendar: calendar))
        var lines = ["## What the recorder found (95% confidence)"]
        guard report.isReporting else {
            lines.append("- Not reporting yet: \(report.flightsUntilReporting) more flight\(report.flightsUntilReporting == 1 ? "" : "s") needed.")
            return lines.joined(separator: "\n")
        }
        guard !report.findings.isEmpty else {
            lines.append("- Nothing separates yet across \(report.flightsAnalyzed) flights.")
            return lines.joined(separator: "\n")
        }
        for finding in report.findings {
            lines.append("- \(finding.kind.label): \(finding.headline)")
            lines.append("  \(finding.detail)")
            for evidence in finding.evidence {
                lines.append("  \(evidence.label): \(evidence.countText), \(interval(evidence.interval))")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func recentFlights(rows: [Row], calendar: Calendar) -> String {
        var lines = ["## Recent flights"]
        lines.append("date, route, planned min, completed min, outcome, bags claimed/total, seat")
        let recent = rows.sorted { $0.endedAt > $1.endedAt }.prefix(recentFlightLimit)
        for row in recent {
            let planned = row.scheduledSeconds.map { String(Int(($0 / 60).rounded())) } ?? ""
            let completed = Int((row.focusSeconds / 60).rounded())
            lines.append([
                dateText(row.endedAt, calendar: calendar),
                "\(row.originCode)-\(row.destinationCode)",
                planned,
                String(completed),
                outcomeText(row.outcome),
                "\(row.bagsClaimed)/\(row.bagsTotal)",
                row.seat,
            ].joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Formatting

    static func outcomeText(_ outcome: FlightOutcome) -> String {
        switch outcome {
        case .arrived: return "landed"
        case .interrupted: return "stopped early"
        case .leftEarly: return "left early"
        case .missedConnection: return "missed connection"
        case .unknown: return "stopped early"
        }
    }

    /// "95% 0.62 to 0.91", the Wilson interval the recorder used.
    static func interval(_ interval: RateInterval) -> String {
        String(format: "95%% %.2f to %.2f", interval.lower, interval.upper)
    }

    static func percent(_ part: Int, of whole: Int) -> String {
        guard whole > 0 else { return "0%" }
        return "\(Int((Double(part) / Double(whole) * 100).rounded()))%"
    }

    static func formatted(_ value: Int) -> String {
        value.formatted(.number.locale(Locale(identifier: "en_US_POSIX")))
    }

    static func dateText(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d",
                      components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    /// Longest run of days between consecutive flights, or nil with fewer
    /// than two flights.
    static func longestGapDays(_ dates: [Date], calendar: Calendar) -> Int? {
        let days = dates.map { calendar.startOfDay(for: $0) }.sorted()
        guard days.count >= 2 else { return nil }
        var longest = 0
        for (earlier, later) in zip(days, days.dropFirst()) {
            let gap = calendar.dateComponents([.day], from: earlier, to: later).day ?? 0
            longest = max(longest, gap)
        }
        return longest
    }
}
