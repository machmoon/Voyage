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
    private var streak: Int { LogbookStats.streak(entries).days }

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
            // No streak row: streaks are hidden for now (2026-09-30).
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

    /// The Meta grid, three across, now holding Airbnb-style stamps
    /// (PassportStamp.swift): the stamp itself, then live-text captions.
    private var stampPage: some View {
        let list = records
        let mostVisitedCode = Self.mostVisitedCode(in: list)
        return VStack(alignment: .leading, spacing: 16) {
            MetaSectionHeader(title: "Arrival stamps",
                              trailing: "\(collectedCount) of \(list.count)")

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 3),
                spacing: 20
            ) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, record in
                    StampCell(record: record, index: index, isMostVisited: record.id == mostVisitedCode)
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        }
        .metaSection(vertical: 14)
    }

    /// The one badged stamp: the most-visited city, and only once it has
    /// been visited three times. Ties go to the most recent visit (records
    /// are sorted newest first). One badge in the grid, in the accent.
    private static func mostVisitedCode(in records: [DestinationRecord]) -> String? {
        guard let top = records.map(\.visits).max(), top >= 3 else { return nil }
        return records.first { $0.visits == top }?.id
    }

    private struct StampCell: View {
        let record: DestinationRecord
        let index: Int
        let isMostVisited: Bool

        private static let diameter: CGFloat = 100

        private var state: PassportStamp.StampState {
            guard record.isCollected else { return .uncollected }
            return isMostVisited ? .mostVisited : .collected
        }

        var body: some View {
            let tilt = PassportStamp.tilt(forIndex: index)
            VStack(spacing: 0) {
                PassportStamp(code: record.airport.code, state: state, diameter: Self.diameter)
                    .rotationEffect(.degrees(tilt))
                    .scaleEffect(PassportStamp.tiltScale(degrees: tilt))
                    .overlay(alignment: .bottom) {
                        if isMostVisited {
                            MostVisitedPill().offset(y: 8)
                        }
                    }
                    .frame(maxWidth: .infinity)

                // Airbnb's caption: 16px under a 120px stamp (scaled to
                // 13 for this 100pt one), city 14/18 text-primary, date
                // 12/16 text-secondary (S7, S11).
                VStack(spacing: 2) {
                    Text(record.airport.city)
                        .voyageFont(14, relativeTo: .subheadline)
                        .foregroundStyle(record.isCollected ? MetaStyle.primaryText : MetaStyle.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(subtitle)
                        .voyageFont(12, relativeTo: .caption)
                        .monospacedDigit()
                        .foregroundStyle(MetaStyle.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .multilineTextAlignment(.center)
                .padding(.top, isMostVisited ? 22 : 13)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
        }

        private var subtitle: String {
            guard let lastVisit = record.lastVisit else { return "Not yet" }
            let date = lastVisit.formatted(.dateTime.month(.abbreviated).day())
            return record.visits > 1 ? "\(date) · ×\(record.visits)" : date
        }

        private var accessibilityLabel: String {
            guard let lastVisit = record.lastVisit else {
                return "\(record.airport.city), \(record.airport.code), not yet visited"
            }
            return "\(record.airport.city), \(record.airport.code), stamped, "
                + "\(record.visits) visit\(record.visits == 1 ? "" : "s"), last "
                + lastVisit.formatted(date: .abbreviated, time: .omitted)
                + (isMostVisited ? ", most visited" : "")
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
}
