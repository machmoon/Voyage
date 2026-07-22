import SwiftData
import SwiftUI

/// A collectible record of every Voyage destination, presented as the document
/// it is imitating: a navy cover, a cream biodata page with a machine-readable
/// zone, and a page of inked arrival stamps that differ city by city.
struct PassportView: View {
    @Query(sort: \LogbookEntry.date, order: .reverse) private var entries: [LogbookEntry]

    fileprivate struct DestinationRecord: Identifiable {
        let airport: Airport
        let visits: Int
        let lastVisit: Date?

        var id: String { airport.code }
        var isCollected: Bool { lastVisit != nil }
    }

    private var completedEntries: [LogbookEntry] { entries.filter(\.completed) }

    private var records: [DestinationRecord] {
        var visitsByCode: [String: (count: Int, lastVisit: Date)] = [:]
        for entry in completedEntries {
            if let existing = visitsByCode[entry.destinationCode] {
                visitsByCode[entry.destinationCode] = (
                    existing.count + 1,
                    max(existing.lastVisit, entry.date)
                )
            } else {
                visitsByCode[entry.destinationCode] = (1, entry.date)
            }
        }

        return Airport.all
            .map { airport in
                let visit = visitsByCode[airport.code]
                return DestinationRecord(airport: airport, visits: visit?.count ?? 0, lastVisit: visit?.lastVisit)
            }
            .sorted { lhs, rhs in
                switch (lhs.lastVisit, rhs.lastVisit) {
                case let (left?, right?): return left > right
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return lhs.airport.code < rhs.airport.code
                }
            }
    }

    private var collectedCount: Int { records.filter(\.isCollected).count }
    private var tier: FlyerTier { LogbookStats.tier(entries) }
    private var memberSince: Date? { completedEntries.map(\.date).min() }

    /// A stable document number, so the passport a traveler saw yesterday is
    /// the same one today.
    private var passportNumber: String {
        var hash: UInt64 = 1469598103934665603
        for byte in (memberSince.map { "\($0.timeIntervalSince1970)" } ?? "unissued").utf8 {
            hash = (hash ^ UInt64(byte)) &* 1099511628211
        }
        return String(format: "VY%07d", hash % 10_000_000)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                passportBook
                stampPage
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    // MARK: Biodata page

    private var passportBook: some View {
        VStack(spacing: 0) {
            cover
            dataPage
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
    }

    private var cover: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe.americas.fill")
                .font(.system(size: 18, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text("PASSPORT")
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .kerning(3)
                Text("VOYAGE AIR")
                    .font(.system(size: 9, weight: .semibold))
                    .kerning(2.4)
                    .opacity(0.65)
            }
            Spacer()
            Text(tier.rawValue.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .kerning(1.4)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
        }
        // Gold foil on navy board, the way the cover of a real passport is
        // blocked rather than printed.
        .foregroundStyle(Color(hex: "E4C98A"))
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Theme.passportCover)
    }

    private var dataPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                portrait

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 14) {
                        field("Type", "P")
                        field("Code", "VOY")
                        field("Passport No", passportNumber)
                    }
                    field("Surname", "FOCUS")
                    field("Given names", "DEEP WORK")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .top, spacing: 14) {
                field("Nationality", "VOYAGE AIR")
                field("Issued", memberSince.map(Self.stampDate) ?? "—")
                field("Stamps", "\(collectedCount) OF \(records.count)")
            }

            machineReadableZone
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.passportPaper)
    }

    /// The portrait window. A globe stands in for a photograph.
    private var portrait: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Theme.passportCover.opacity(0.06))
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Theme.passportCover.opacity(0.22), lineWidth: 1)
            Image(systemName: "globe.americas.fill")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.passportCover.opacity(0.35))
        }
        .frame(width: 62, height: 80)
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 7, weight: .semibold))
                .kerning(0.9)
                .foregroundStyle(Theme.passportCover.opacity(0.45))
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.passportCover)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The two OCR lines across the foot of every biodata page. Chevrons are
    /// the real filler character.
    private var machineReadableZone: some View {
        let name = "P<VOYFOCUS<<DEEP<WORK".padding(toLength: 36, withPad: "<", startingAt: 0)
        let document = "\(passportNumber)<\(tier.rawValue.uppercased())"
            .padding(toLength: 36, withPad: "<", startingAt: 0)
        return VStack(alignment: .leading, spacing: 3) {
            Rectangle()
                .fill(Theme.passportCover.opacity(0.12))
                .frame(height: 1)
                .padding(.bottom, 5)
            ForEach([name, document], id: \.self) { line in
                Text(line)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .kerning(0.5)
                    .foregroundStyle(Theme.passportCover.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Stamp page

    private var stampPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Arrival stamps")
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.passportCover)
                Spacer()
                Text("MOST RECENT FIRST")
                    .font(.system(size: 8, weight: .semibold))
                    .kerning(1)
                    .foregroundStyle(Theme.passportCover.opacity(0.4))
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                ForEach(records) { record in
                    StampCell(record: record)
                }
            }
        }
        .padding(16)
        .background(
            // A passport page, complete with the faint guilloche tint real
            // documents print to make forgery harder.
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.passportPaper)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.passportCover.opacity(0.10), lineWidth: 1)
                }
        )
        .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
    }

    private struct StampCell: View {
        let record: DestinationRecord

        private var style: StampStyle { StampStyle.forCode(record.airport.code) }
        private var ink: Color { Color(hex: record.airport.accentHex) }

        var body: some View {
            ZStack {
                if record.isCollected {
                    StampMark(style: style, ink: ink, record: record)
                        .rotationEffect(.degrees(style.rotation))
                } else {
                    unstamped
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 126)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
        }

        private var unstamped: some View {
            VStack(spacing: 6) {
                Image(systemName: "airplane.departure")
                    .font(.system(size: 16, weight: .light))
                Text(record.airport.code)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                Text("NOT YET VISITED")
                    .font(.system(size: 7, weight: .semibold))
                    .kerning(0.6)
            }
            .foregroundStyle(Theme.passportCover.opacity(0.25))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        Theme.passportCover.opacity(0.16),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )
            }
        }

        private var accessibilityLabel: String {
            guard let lastVisit = record.lastVisit else {
                return "\(record.airport.city), \(record.airport.code), not yet visited"
            }
            return "\(record.airport.city), \(record.airport.code), stamped, "
                + "\(record.visits) visit\(record.visits == 1 ? "" : "s"), last "
                + lastVisit.formatted(date: .abbreviated, time: .omitted)
        }
    }

    private static func stampDate(_ date: Date) -> String {
        date.formatted(.dateTime.day(.twoDigits).month(.abbreviated).year())
            .uppercased()
            .replacingOccurrences(of: ",", with: "")
    }
}

// MARK: - Stamp design

/// Border treatments borrowed from real immigration stamps: round and oval
/// dies, square-cornered entry rectangles, and scalloped commemorative marks.
private enum StampStyle: CaseIterable {
    case circle, rectangle, oval, scalloped

    /// Deterministic per airport, so a city's stamp never changes between
    /// visits — the whole point of a collection.
    static func forCode(_ code: String) -> StampStyle {
        var hash: UInt64 = 5381
        for byte in code.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        return allCases[Int(hash % UInt64(allCases.count))]
    }

    /// A hand-applied stamp is never quite square to the page.
    var rotation: Double {
        switch self {
        case .circle: return -6
        case .rectangle: return 3.5
        case .oval: return -2.5
        case .scalloped: return 5
        }
    }

    var caption: String {
        switch self {
        case .circle: return "ADMITTED"
        case .rectangle: return "ENTRY"
        case .oval: return "ARRIVAL"
        case .scalloped: return "CLEARED"
        }
    }
}

/// One inked arrival mark. Ink sits slightly transparent and the border is
/// drawn, never filled, so stamps read as pressed onto the page.
private struct StampMark: View {
    let style: StampStyle
    let ink: Color
    let record: PassportView.DestinationRecord

    var body: some View {
        ZStack {
            border
            VStack(spacing: 2) {
                Image(systemName: "airplane")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(-45))
                Text(record.airport.code)
                    .font(.system(size: 20, weight: .black, design: .monospaced))
                    .kerning(1)
                Text(record.airport.city.uppercased())
                    .font(.system(size: 7, weight: .heavy))
                    .kerning(0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 6)
                Rectangle()
                    .fill(ink.opacity(0.5))
                    .frame(width: 34, height: 0.8)
                    .padding(.vertical, 1)
                Text(record.lastVisit.map(Self.shortDate) ?? "")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                Text(record.visits > 1 ? "\(style.caption) ×\(record.visits)" : style.caption)
                    .font(.system(size: 6, weight: .heavy))
                    .kerning(0.8)
            }
            .foregroundStyle(ink.opacity(0.88))
            .padding(.horizontal, 8)
        }
        .frame(width: 112, height: 112)
    }

    @ViewBuilder private var border: some View {
        switch style {
        case .circle:
            ZStack {
                Circle().strokeBorder(ink.opacity(0.75), lineWidth: 2.5)
                Circle().strokeBorder(ink.opacity(0.4), lineWidth: 1).padding(6)
            }
        case .rectangle:
            // Schengen convention: square corners mark an entry.
            ZStack {
                Rectangle().strokeBorder(ink.opacity(0.75), lineWidth: 2.5)
                Rectangle().strokeBorder(ink.opacity(0.35), lineWidth: 1).padding(5)
            }
            .padding(.vertical, 14)
        case .oval:
            ZStack {
                Ellipse().strokeBorder(ink.opacity(0.75), lineWidth: 2.5)
                Ellipse().strokeBorder(ink.opacity(0.35), lineWidth: 1).padding(6)
            }
            .padding(.vertical, 8)
        case .scalloped:
            ZStack {
                ScallopedBorder(teeth: 22)
                    .stroke(ink.opacity(0.75), lineWidth: 2)
                Circle().strokeBorder(ink.opacity(0.35), lineWidth: 1).padding(10)
            }
        }
    }

    private static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day(.twoDigits).month(.abbreviated).year(.twoDigits))
            .uppercased()
            .replacingOccurrences(of: ",", with: "")
    }
}

/// A commemorative die: a circle with a wavy edge.
private struct ScallopedBorder: Shape {
    let teeth: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let base = min(rect.width, rect.height) / 2 - 2
        let steps = teeth * 8

        for step in 0...steps {
            let angle = Double(step) / Double(steps) * 2 * .pi
            let wave = 1 + 0.045 * cos(angle * Double(teeth))
            let point = CGPoint(x: centre.x + cos(angle) * base * wave,
                                y: centre.y + sin(angle) * base * wave)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}
