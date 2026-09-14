import PhotosUI
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
    private var memberSince: Date? { completedEntries.map(\.date).min() }
    private var streak: Int { LogbookStats.streakDays(entries) }

    @State private var photo: UIImage? = PassportPhotoStore.load()
    @State private var photoItem: PhotosPickerItem?

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

    // MARK: Pilot card

    /// The page opens on a card, the way FocusFlight opens its club page on a
    /// membership card over one thin progress bar with two numbers under it.
    /// Here the card is the pilot certificate: photo, rating, member since.
    private var passportBook: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "airplane")
                    .font(.caption2.weight(.semibold))
                Text(memberLine)
                    .font(.footnote)
                Spacer()
                if streak >= 2 {
                    Text("\(streak)-day streak")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(.secondary)

            pilotCard

            progressLine
        }
    }

    private var memberLine: String {
        guard let memberSince else { return "No flights yet" }
        let days = max(1, Calendar.current.dateComponents([.day], from: memberSince, to: .now).day ?? 0)
        return days == 1 ? "First flight today" : "Flying for \(days) days"
    }

    private var pilotCard: some View {
        HStack(spacing: 16) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                ZStack {
                    Circle().fill(.white.opacity(0.10))
                    if let photo {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(photo == nil ? "Add a passport photo" : "Change passport photo")

            VStack(alignment: .leading, spacing: 4) {
                Text("VOYAGE AIR")
                    .font(.caption2.weight(.semibold))
                    .kerning(1.2)
                    .foregroundStyle(Theme.passportFoil.opacity(0.7))
                Text(rating.current.title)
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(.white)
                Text("\(collectedCount) of \(records.count) cities · \(completedEntries.count) landings")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.65))
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Theme.passportCover, Color(hex: "0E1424")],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    PassportPhotoStore.save(image)
                    photo = PassportPhotoStore.load()
                }
            }
        }
    }

    /// One bar, two numbers: total time on the left, what is left to the
    /// next rating on the right.
    @ViewBuilder
    private var progressLine: some View {
        let total = LogbookStats.totalFocusSeconds(entries)
        if let next = rating.next, let open = rating.firstOpenRequirement {
            VStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.passportCover.opacity(0.10))
                        Capsule().fill(Theme.accent)
                            .frame(width: max(4, geo.size.width * open.fraction))
                    }
                }
                .frame(height: 4)
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(PilotRatings.hoursText(total))
                            .font(.headline).monospacedDigit()
                        Text("Total time").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(open.remainingText)
                            .font(.headline).monospacedDigit()
                        Text("To \(next.title)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
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
