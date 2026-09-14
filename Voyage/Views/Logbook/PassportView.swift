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
    private var rating: RatingProgress { RatingProgress.evaluate(entries: entries) }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                passportBook
                stampPage
                if !endorsedEntries.isEmpty {
                    endorsementsPage
                }
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
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        // The bio page is a scale drawing of a real document: field columns,
        // a printed frame, and a machine-readable zone whose two lines are
        // fixed at 44 characters and cannot reflow. Growing the type shatters
        // the layout, so it is capped instead, which is what
        // wordpress-mobile/WordPress-iOS does on its own fixed cards
        // (Modules/Sources/JetpackStats/Cards/TopListCard.swift) and
        // signalapp/Signal-iOS on fixed screens
        // (Signal/Registration/UserInterface/RegistrationPermissionsView.swift).
        //
        // A cap is honest, not a fix. The passport still bottoms out at
        // 6pt to 8pt type, and several labels here shrink further via
        // minimumScaleFactor(0.6). The accessible answer is a text
        // alternative for the collection, noted in the critique.
        //
        // xLarge rather than large so the page still gains one step for
        // someone who has nudged text up, instead of being frozen outright.
        // NOT visually verified at accessibility sizes: needs a look on
        // device before shipping.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    private var cover: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe.americas.fill")
                .voyageFont(18, weight: .semibold)
            VStack(alignment: .leading, spacing: 2) {
                Text("PASSPORT")
                    .voyageFont(15, weight: .bold, design: .serif)
                    .kerning(3)
                Text("VOYAGE AIR")
                    .voyageFont(9, weight: .semibold)
                    .kerning(2.4)
                    .opacity(0.65)
            }
            Spacer()
            Text(rating.current.title.uppercased())
                .voyageFont(10, weight: .heavy)
                .kerning(1.4)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
        }
        // Foil on navy board, the way the cover of a real passport is blocked
        // rather than printed. Voyage blue rather than gold: the foil is the
        // one piece of color on the cover, so it should be the brand's.
        .foregroundStyle(Theme.passportFoil)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Theme.passportCover)
    }

    // MARK: Stamp page

    private var stampPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                // The page furniture is ordinary UI and scales. Only the
                // stamps themselves are a scale drawing.
                Text("Arrival stamps")
                    .voyageFont(15, weight: .bold, design: .serif)
                    .foregroundStyle(Theme.passportCover)
                Spacer()
                // One earned count in the header, the way Habitica's
                // achievement sections carry a single earned-only chip
                // (HabitRPG/habitica-ios, AchievementHeaderView).
                Text("\(collectedCount) of \(records.count)")
                    .voyageFont(11, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(Theme.passportCover)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(Theme.passportCover.opacity(0.08), in: Capsule())
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                ForEach(records) { record in
                    StampCell(record: record)
                }
            }
            // Each cell is a fixed 112pt die with 6pt to 8pt type inside it.
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
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

        /// One ink for the whole collection. This used to read
        /// `record.airport.accentHex` directly, which put the raw per-airport
        /// palette (nine hues, from hot pink to gold) on one page and made the
        /// grid read as stickers. `Airport.accentColor` exists precisely to
        /// stop that and says so in `Theme.swift`; this cell was going around
        /// it. Cities are told apart here by die shape, caption and code,
        /// which is how a real passport does it. Per-city color is kept for
        /// the arrival moment alone.
        private var ink: Color { Theme.passportInk }

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

        /// One silhouette for every unstamped city: a faint die with the
        /// code, nothing else. Habitica renders every locked achievement
        /// with the same single asset (`achievement-unearned2x`,
        /// HabitRPG/habitica-ios AchievementIconView), which is what keeps a
        /// grid reading as a collection instead of a to-do list.
        private var unstamped: some View {
            ZStack {
                Circle()
                    .strokeBorder(Theme.passportCover.opacity(0.14), lineWidth: 1.5)
                Circle()
                    .strokeBorder(Theme.passportCover.opacity(0.10), lineWidth: 1)
                    .padding(6)
                Text(record.airport.code)
                    .voyageFont(15, weight: .bold, design: .monospaced)
                    .foregroundStyle(Theme.passportCover.opacity(0.22))
            }
            .frame(width: 104, height: 104)
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

    // MARK: Endorsements

    /// Landings that raised the rating, most recent first. `entries` is
    /// already sorted by date descending.
    private var endorsedEntries: [LogbookEntry] {
        entries.filter { $0.endorsement != nil }
    }

    /// The endorsements page follows a real logbook: one dated line per
    /// sign-off, printed under the stamps rather than as a card of its own.
    private var endorsementsPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Endorsements")
                .voyageFont(15, weight: .bold, design: .serif)
                .foregroundStyle(Theme.passportCover)
            ForEach(endorsedEntries) { entry in
                if let rating = entry.endorsement {
                    HStack(spacing: 10) {
                        Text(PilotRatings.endorsementLine(for: rating, on: entry.date))
                            .voyageFont(11, weight: .semibold, design: .monospaced)
                            .foregroundStyle(Theme.passportInk)
                        Spacer()
                        Text("\(entry.originCode) to \(entry.destinationCode)")
                            .voyageFont(9, weight: .semibold)
                            .kerning(0.6)
                            .foregroundStyle(Theme.passportCover.opacity(0.45))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.passportPaper)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.passportCover.opacity(0.10), lineWidth: 1)
                }
        )
        .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
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
                    .voyageFont(9, weight: .bold)
                    .rotationEffect(.degrees(-45))
                Text(record.airport.code)
                    .voyageFont(20, weight: .black, design: .monospaced)
                    .kerning(1)
                Text(record.airport.city.uppercased())
                    .voyageFont(7, weight: .heavy)
                    .kerning(0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 6)
                Rectangle()
                    .fill(ink.opacity(0.5))
                    .frame(width: 34, height: 0.8)
                    .padding(.vertical, 1)
                Text(record.lastVisit.map(Self.shortDate) ?? "")
                    .voyageFont(8, weight: .bold, design: .monospaced)
                Text(record.visits > 1 ? "\(style.caption) ×\(record.visits)" : style.caption)
                    .voyageFont(6, weight: .heavy)
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
