import PhotosUI
import SwiftData
import SwiftUI

/// A collectible record of every Voyage destination.
///
/// Laid out as a profile page in the Meta (Facebook Comet) design language:
/// a cover, an overlapping round photo, a bold name with a stats line, detail
/// rows, and then full-bleed sections on the wash for the stamps and the
/// endorsements. Tokens and their sources are in `MetaStyle.swift`
/// (DESIGN-NOTES).
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
            VStack(spacing: MetaStyle.sectionGap) {
                profileHeader
                stampPage
                if !endorsedEntries.isEmpty {
                    endorsementsPage
                }
            }
            .padding(.bottom, 24)
        }
        .background(MetaStyle.webWash.ignoresSafeArea())
    }

    // MARK: Profile header

    private static let coverHeight: CGFloat = 132
    private static let photoDiameter: CGFloat = 112
    /// The card-colored ring Comet draws round a profile photo where it
    /// overlaps the cover.
    private static let photoRing: CGFloat = 4

    /// The page opens on the pilot, the way a profile opens on its owner:
    /// cover, photo, name (the rating), one stats line, detail rows, and the
    /// one progress bar toward the next rating.
    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            cover
            photoPicker
                .padding(.top, -Self.photoDiameter / 2 - Self.photoRing)
                .padding(.leading, MetaStyle.gutter)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(rating.current.title)
                        .metaTitle()
                        .foregroundStyle(MetaStyle.primaryText)
                    statsLine
                }

                detailRows

                progressLine
            }
            .padding(.horizontal, MetaStyle.gutter)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MetaStyle.cardBackground)
    }

    /// An empty cover, in the pale highlight blue, with a faint globe where a
    /// cover photo would go.
    private var cover: some View {
        ZStack(alignment: .topTrailing) {
            Rectangle().fill(MetaStyle.highlightBackground)
            Image(systemName: "globe.americas.fill")
                .font(.system(size: 150))
                .foregroundStyle(MetaStyle.deemphasizedButtonText.opacity(0.12))
                .offset(x: 24, y: -18)
                .accessibilityHidden(true)
        }
        .frame(height: Self.coverHeight)
        .clipped()
    }

    private var photoPicker: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Circle().fill(MetaStyle.wash)
                    if let photo {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(MetaStyle.cardBackground)
                    }
                }
                .frame(width: Self.photoDiameter, height: Self.photoDiameter)
                .clipShape(Circle())
                .padding(Self.photoRing)
                .background(MetaStyle.cardBackground, in: Circle())

                // The camera badge on the photo's lower edge.
                MetaIconCircle(systemName: "camera.fill", diameter: 32)
                    .padding(3)
                    .background(MetaStyle.cardBackground, in: Circle())
                    .offset(x: -4, y: -4)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(photo == nil ? "Add a passport photo" : "Change passport photo")
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

    /// Bold counts in a gray line, the way a profile shows "1.2K friends".
    private var statsLine: some View {
        (Text("\(collectedCount)").fontWeight(.semibold).foregroundColor(MetaStyle.primaryText)
         + Text(" of \(records.count) cities · ")
         + Text("\(completedEntries.count)").fontWeight(.semibold).foregroundColor(MetaStyle.primaryText)
         + Text(" landings"))
            .metaBody()
            .monospacedDigit()
            .foregroundStyle(MetaStyle.secondaryText)
    }

    /// Profile "Details" rows: a gray glyph and one line of 15pt text.
    private var detailRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            detailRow("airplane", memberLine)
            if streak >= 2 {
                detailRow("flame.fill", "\(streak)-day streak")
            }
        }
    }

    private func detailRow(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .metaBody(.semibold)
                .foregroundStyle(MetaStyle.secondaryIcon)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(text)
                .metaBody()
                .monospacedDigit()
                .foregroundStyle(MetaStyle.primaryText)
        }
    }

    private var memberLine: String {
        guard let memberSince else { return "No flights yet" }
        let days = max(1, Calendar.current.dateComponents([.day], from: memberSince, to: .now).day ?? 0)
        return days == 1 ? "First flight today" : "Flying for \(days) days"
    }

    /// One bar, two numbers: total time on the left, what is left to the
    /// next rating on the right.
    @ViewBuilder
    private var progressLine: some View {
        let total = LogbookStats.totalFocusSeconds(entries)
        if let next = rating.next, let open = rating.firstOpenRequirement {
            VStack(spacing: 8) {
                MetaProgressBar(fraction: open.fraction, height: 6)
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(PilotRatings.hoursText(total))
                            .metaHeadline()
                            .monospacedDigit()
                            .foregroundStyle(MetaStyle.primaryText)
                        Text("Total time")
                            .metaMeta()
                            .foregroundStyle(MetaStyle.secondaryText)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(open.remainingText)
                            .metaHeadline()
                            .monospacedDigit()
                            .foregroundStyle(MetaStyle.primaryText)
                        Text("To \(next.title)")
                            .metaMeta()
                            .foregroundStyle(MetaStyle.secondaryText)
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    // MARK: Stamp page

    /// A three-across grid of square tiles with a name and a count under
    /// each, the way a profile's friends and photos sections are drawn.
    private var stampPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            MetaSectionHeader(title: "Arrival stamps",
                              trailing: "\(collectedCount) of \(records.count)")

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 3),
                spacing: 14
            ) {
                ForEach(records) { record in
                    StampCell(record: record)
                }
            }
            // Each tile holds a fixed 112pt die with 6pt to 8pt type inside it.
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
        }
        .metaSection(vertical: 14)
    }

    private struct StampCell: View {
        let record: DestinationRecord

        private var style: StampStyle { StampStyle.forCode(record.airport.code) }

        /// One ink for the whole collection, so the grid reads as one
        /// document rather than a sticker sheet. Comet's link blue
        /// (--blue-link), which holds its contrast on both the light and the
        /// dark flat card.
        private var ink: Color { MetaStyle.blueLink }

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: MetaStyle.cardCornerRadius, style: .continuous)
                    .fill(MetaStyle.cardBackgroundFlat)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if record.isCollected {
                            StampMark(style: style, ink: ink, record: record)
                                .rotationEffect(.degrees(style.rotation))
                                .scaleEffect(0.86)
                        } else {
                            unstamped
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: MetaStyle.cardCornerRadius, style: .continuous)
                            .strokeBorder(MetaStyle.divider.opacity(0.6), lineWidth: 0.5)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(record.airport.city)
                        .metaMeta(.semibold)
                        .foregroundStyle(record.isCollected ? MetaStyle.primaryText : MetaStyle.secondaryText)
                        .lineLimit(1)
                    Text(record.isCollected
                         ? "\(record.visits) visit\(record.visits == 1 ? "" : "s")"
                         : "Not yet")
                        .metaMeta()
                        .foregroundStyle(MetaStyle.secondaryText)
                        .lineLimit(1)
                }
            }
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
                    .strokeBorder(MetaStyle.disabledIcon, lineWidth: 1.5)
                Circle()
                    .strokeBorder(MetaStyle.disabledIcon.opacity(0.7), lineWidth: 1)
                    .padding(6)
                Text(record.airport.code)
                    .voyageFont(15, weight: .bold, design: .monospaced)
                    .foregroundStyle(MetaStyle.disabledIcon)
            }
            .frame(width: 84, height: 84)
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

    /// One Comet list cell per sign-off: gray icon circle, the endorsement on
    /// the first line, the route that earned it under it.
    private var endorsementsPage: some View {
        VStack(alignment: .leading, spacing: 4) {
            MetaSectionHeader(title: "Endorsements")
                .padding(.bottom, 4)
            ForEach(endorsedEntries) { entry in
                if let rating = entry.endorsement {
                    HStack(spacing: 12) {
                        MetaIconCircle(systemName: "checkmark.seal.fill")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(PilotRatings.endorsementLine(for: rating, on: entry.date))
                                .metaBody(.semibold)
                                .foregroundStyle(MetaStyle.primaryText)
                            Text("\(entry.originCode) to \(entry.destinationCode)")
                                .metaMeta()
                                .foregroundStyle(MetaStyle.secondaryText)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: MetaStyle.listCellMinHeight)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .metaSection(vertical: 14)
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
