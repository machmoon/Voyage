import SwiftUI
import SwiftData
import UIKit

private struct ReplaySelection: Identifiable {
    let id = UUID()
    let entries: [LogbookEntry]
    let title: String
}

/// Passport-style history of every flight, plus miles, streak, and tier progress.
struct LogbookView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LogbookEntry.date, order: .reverse) private var entries: [LogbookEntry]

    private enum Tab: String, CaseIterable {
        case flights = "Flights"
        case passport = "Passport"
    }

    @State private var tab: Tab = .flights
    @State private var replaySelection: ReplaySelection?

    private var tier: FlyerTier { LogbookStats.tier(entries) }
    private var rating: RatingProgress { RatingProgress.evaluate(entries: entries) }
    private var weekEntries: [LogbookEntry] { LogbookStats.completedFlights(entries) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)

                switch tab {
                case .flights:
                    flightsList
                case .passport:
                    PassportView()
                }
            }
            // One warm page under the bar, the picker and both tabs, the way
            // ramp.com sets a section on --grayLight (#f4f2f0). See RampDesign.swift.
            .background(Ramp.page.ignoresSafeArea())
            .navigationTitle("Logbook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Ramp.page, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        LogbookExportButtons(entries: entries)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Export logbook")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            // The app accent, the same as every other sheet.
            .tint(Theme.tint)
        }
        .fullScreenCover(item: $replaySelection) { selection in
            FlightReplayView(entries: selection.entries, title: selection.title)
        }
    }

    private var flightsList: some View {
        List {
            if VoyageApp.logbookIsEphemeral {
                Section {
                    LogbookStorageWarning()
                }
                .listRowBackground(Ramp.surface)
            }

            Section {
                statusCard
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                NavigationLink { FlightDataRecorderView() } label: { recorderRow }
                    .accessibilityIdentifier("open-recorder")
            }
            .listRowBackground(Ramp.surface)

            Section {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No flights yet",
                        systemImage: "airplane",
                        description: Text("Book your first flight from the globe. Every completed session lands here.")
                    )
                } else {
                    ForEach(entries) { entry in
                        entryRow(entry)
                    }
                }
            } header: {
                // A ramp.com table header: body-xs in --text-hushed, sentence
                // case, no tracking.
                HStack {
                    Text("Flights")
                    Spacer()
                    Text("Time")
                        .accessibilityHidden(true)
                }
                .voyageFont(Ramp.TypeScale.bodyXS)
                .foregroundStyle(Ramp.hushed)
                .textCase(nil)
                .padding(.trailing, 44)
            }
            .listRowBackground(Ramp.surface)
            // Row rules are Airbnb's divider (#EBEBEB / #2C2C2C), one step
            // lighter than the card hairline (#DDDDDD), as client.css splits
            // --palette-bg-divider from --palette-border-secondary.
            .listRowSeparatorTint(Ramp.divider)
        }
        .scrollContentBackground(.hidden)
        .background(Ramp.page)
        .environment(\.defaultMinListRowHeight, 56)
    }

    // MARK: Recorder row

    /// Entry point to the flight data recorder. The caption states where the
    /// recorder stands rather than promising insight it may not have.
    ///
    /// Laid out like an Airbnb feature callout: a 48-grid two-tone glyph
    /// (IcFeatureGraphUpAlt48, see LogbookGlyphs.swift) on a 12pt tile
    /// (client.css `--corner-radius-medium`), a 16/20 semibold title and a
    /// 14/18 secondary line (client.css title / body scale).
    ///
    /// Deviation, stated: Airbnb's 20% layer is the outline color at .2. On
    /// the grey tile that is grey on grey, so the area under the line is the
    /// accent at 25% instead: a tint fill under an ink stroke.
    private var recorderRow: some View {
        HStack(spacing: 14) {
            InsightsGlyph(line: Ramp.ink, area: Theme.tint, areaOpacity: 0.25)
                .frame(width: 30, height: 30)
                .frame(width: 48, height: 48)
                .background(Ramp.tile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Insights")
                    .voyageFont(16, weight: .semibold)
                    .kerning(-0.16)
                    .foregroundStyle(Ramp.ink)
                Text(recorderCaption)
                    .voyageFont(Ramp.TypeScale.bodyS)
                    .foregroundStyle(Ramp.hushed)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
    }

    private var recorderCaption: String {
        let report = FlightDataRecorder.report(entries: entries)
        guard report.isReporting else {
            return "\(report.flightsUntilReporting) more flights until it reports"
        }
        switch report.findings.count {
        case 0: return "Nothing separates yet across \(report.flightsAnalyzed) flights"
        case 1: return "1 finding from \(report.flightsAnalyzed) flights"
        default: return "\(report.findings.count) findings from \(report.flightsAnalyzed) flights"
        }
    }

    // MARK: Status card

    /// Laid out like a balance card on ramp.com: a hushed label, one large
    /// number in regular weight (headline-xl), a hushed caption, then the
    /// single filled call to action, in the app accent (rounded-md).
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 24) {
            // The rating card. One rating at a time, one row per requirement,
            // the way MyFlightbook lays out a rating
            // (MyFlightbook.Web/Areas/mvc/Views/Training/_ratingsProgressList.cshtml):
            // a check for AchieveOnce items, a progress bar with the
            // ProgressDisplay text for Count and Time items.
            // One number, one line under it. Hours is the number a student
            // pilot watches; the rating, landings and airports are its caption.
            VStack(alignment: .leading, spacing: 8) {
                Text("Total focus time")
                    .voyageFont(Ramp.TypeScale.bodyS)
                    .foregroundStyle(Ramp.hushed)
                // Airbnb sets its large numerals in MEDIUM weight with -2%
                // tracking (the 4.98 hero: 100px / 500 / -2px, read live off
                // airbnb.com/rooms/…; "Guest favorite" 22px / 500 / -0.44px).
                Text(PilotRatings.hoursText(LogbookStats.totalFocusSeconds(entries)))
                    .voyageFont(Ramp.TypeScale.headlineXL, weight: .medium)
                    .kerning(-0.8)
                    .monospacedDigit()
                    .foregroundStyle(Ramp.ink)
                let landings = entries.filter(\.completed)
                let streak = LogbookStats.streakDays(entries)
                Text("\(rating.current.title) · \(landings.count) landings\(streak >= 2 ? " · \(streak)-day streak" : "")")
                    .voyageFont(Ramp.TypeScale.bodyM)
                    .foregroundStyle(Ramp.hushed)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Only what is still open. A met requirement is already
            // implied by the rating name, and a list of checks is clutter.
            let openRequirements = rating.nextRequirements.filter { !$0.isSatisfied }
            if !openRequirements.isEmpty, let next = rating.next {
                VStack(spacing: 12) {
                    Text("Toward \(next.title)")
                        .voyageFont(Ramp.TypeScale.bodyXS)
                        .foregroundStyle(Ramp.hushed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(openRequirements) { requirement in
                        requirementRow(requirement)
                    }
                }
                .padding(.top, 16)
                .overlay(alignment: .top) {
                    Rectangle().fill(Ramp.rule).frame(height: 1)
                }
            }

            if !weekEntries.isEmpty {
            Button {
                Haptics.tap()
                replaySelection = ReplaySelection(entries: weekEntries, title: "This Week")
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                        .voyageFont(11, weight: .bold)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Replay this week")
                            .voyageFont(Ramp.TypeScale.bodyM, weight: .semibold)
                            .kerning(-0.15)
                        Text(weekEntries.isEmpty
                             ? "No completed flights yet"
                             : "\(weekEntries.count) flight\(weekEntries.count == 1 ? "" : "s") · \(Int(LogbookStats.totalMiles(weekEntries)).formatted()) miles")
                            .voyageFont(Ramp.TypeScale.bodyXS)
                            // Full white: 5.15:1 on AccentFill #2F66DE.
                            // At 85% it would drop to 4.19:1, under 4.5:1
                            // for 12pt, so the size carries the hierarchy.
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                        .voyageFont(Ramp.TypeScale.bodyS, weight: .medium)
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 16)
                // minHeight, not height: the label inside is two lines of
                // scaling text and a fixed 54 clipped it from AX2 up.
                .frame(minHeight: 54)
            }
            .buttonStyle(AccentFillButtonStyle())
            .disabled(weekEntries.isEmpty)
            .accessibilityLabel("Replay \(weekEntries.count) flights from this week")
            }
        }
        .padding(.horizontal, Ramp.Space.cardH)
        .padding(.vertical, Ramp.Space.cardV)
        .background(Ramp.surface, in: RoundedRectangle(cornerRadius: Ramp.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Ramp.Radius.card, style: .continuous)
                .strokeBorder(Ramp.rule, lineWidth: 1)
        )
    }

    /// One checklist line: title and progress text over a bar while a
    /// requirement is open, and a check once it is met. A met count row
    /// collapses to the check too, so "44 of 10 landings" never shows, the
    /// way MyFlightbook's ratings progress list marks completed items.
    private func requirementRow(_ requirement: RatingRequirement) -> some View {
        let showsCheck = requirement.kind == .achieveOnce || requirement.isSatisfied
        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                if showsCheck {
                    // ramp.com/pricing marks an included feature with a filled
                    // check_circle in #5AB570.
                    Image(systemName: requirement.isSatisfied ? "checkmark.circle.fill" : "circle")
                        .voyageFont(14)
                        .foregroundStyle(requirement.isSatisfied ? Ramp.positive : Ramp.hushed)
                }
                Text(requirement.title)
                    .voyageFont(Ramp.TypeScale.bodyS)
                    .foregroundStyle(requirement.isSatisfied ? Ramp.hushed : Ramp.ink)
                Spacer(minLength: 8)
                if !showsCheck {
                    Text(requirement.progressText)
                        .voyageFont(Ramp.TypeScale.bodyXS, design: .monospaced)
                        .foregroundStyle(Ramp.hushed)
                }
            }
            if !showsCheck {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Ramp.track)
                        Capsule()
                            .fill(Ramp.mark)
                            .frame(width: geo.size.width * requirement.fraction)
                    }
                }
                .frame(height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            showsCheck
                ? "\(requirement.title), \(requirement.isSatisfied ? "done" : "not yet")"
                : "\(requirement.title), \(requirement.progressText)"
        )
    }

    // MARK: Entry row

    /// A ramp.com transaction line: a leading tile, name over a hushed date,
    /// and the amount (here, focus time) right-aligned in tabular figures.
    /// The tile is a ticket (LogbookGlyphs.swift, after IcSystemTicket32):
    /// the shape carries the meaning, so the old "ADMITTED" caption is gone.
    private func entryRow(_ entry: LogbookEntry) -> some View {
        HStack(spacing: 12) {
            // Fixed geometry with its own 13pt code, so it does not grow with
            // Dynamic Type: a tile that doubles in size pushes the route and
            // the time off the row. Same call WordPress-iOS makes on its
            // fixed cards (Modules/Sources/JetpackStats/Cards/TopListCard.swift).
            TicketTile(code: entry.destinationCode, landed: entry.completed)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    // Airbnb's card title: 15px / 500 / #222222 (live
                    // computed style of a search result card).
                    Text("\(entry.originCode) → \(entry.destinationCode)")
                        .voyageFont(Ramp.TypeScale.bodyM, weight: .medium)
                        .foregroundStyle(Ramp.ink)
                    if let via = entry.connectionCode {
                        Text("via \(via)")
                            .voyageFont(Ramp.TypeScale.bodyXS)
                            .foregroundStyle(Ramp.hushed)
                    }
                }
                // Date, and the outcome when it was not a landing. Flight
                // number, seat, bags and miles are on the receipt and the
                // stamp, not repeated on every row.
                Text("\(entry.date.formatted(.dateTime.month(.abbreviated).day()))\(entry.completed ? "" : " · Stopped early")")
                    .voyageFont(Ramp.TypeScale.bodyXS)
                    // Stopped early reads from the grey ticket and the words;
                    // the caption stays secondary text. (Ramp's #E96516 was
                    // 3.2:1 on white, under AA for 12pt.) Airbnb lets neutrals
                    // do this work and keeps color for the one accent.
                    .foregroundStyle(Ramp.hushed)
            }

            Spacer(minLength: 8)

            Text(entry.focusSeconds.shortDurationText)
                .voyageFont(Ramp.TypeScale.bodyM)
                .monospacedDigit()
                .foregroundStyle(entry.completed ? Ramp.ink : Ramp.hushed)

            Group {
                if entry.completed {
                    LogbookShareButton(entry: entry)
                } else {
                    Color.clear
                }
            }
            .frame(width: 30)
        }
        .padding(.vertical, 6)
        // The row itself replays the flight. One control per row, the
        // share glyph, instead of two.
        .contentShape(Rectangle())
        .onTapGesture {
            guard entry.completed else { return }
            Haptics.tap()
            replaySelection = ReplaySelection(entries: [entry], title: "Flight \(entry.flightNumber)")
        }
        .accessibilityAction(named: "Replay") {
            guard entry.completed else { return }
            replaySelection = ReplaySelection(entries: [entry], title: "Flight \(entry.flightNumber)")
        }
    }
}

/// The Logbook's one filled action: `Theme.accentFill` behind white text,
/// Ramp's 6pt `rounded-md` corner. Pressed dims the fill, as
/// `VoyageAccentButtonStyle` does.
struct AccentFillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Theme.accentFill.opacity(configuration.isPressed ? 0.85 : 1),
                        in: RoundedRectangle(cornerRadius: Ramp.Radius.button, style: .continuous))
            .opacity(isEnabled ? 1 : 0.5)
            .animation(.easeInOut(duration: 0.3), value: configuration.isPressed)
    }
}

/// Share affordance for one logbook row.
///
/// This exists as its own view so it can own `@State`. `entryRow` is a method,
/// and a method cannot hold per-row state, which is why the receipt used to be
/// rasterised inline in the row body: `List` re-evaluates that body constantly
/// while scrolling, so every visible completed flight was re-rendering a whole
/// SwiftUI card at 3x and PNG-encoding it, tens of times a second. That is the
/// same shape of fix `ArrivalFlowView` already uses, where the receipt is
/// rendered once into `@State` and the body only reads the stored value.
///
/// The icon is rendered unconditionally so the row's layout does not shift when
/// the receipt arrives; only the `ShareLink` waits.
private struct LogbookShareButton: View {
    let entry: LogbookEntry

    @State private var receipt: RenderedReceipt?

    var body: some View {
        Group {
            if let receipt {
                ShareLink(
                    item: ReceiptShareItem(pngData: receipt.pngData),
                    preview: SharePreview(
                        "Flight to \(entry.destinationCode)",
                        image: Image(uiImage: receipt.image)
                    )
                ) {
                    icon
                }
                .buttonStyle(.plain)
            } else {
                icon.opacity(0.35)
                    .accessibilityHidden(true)
            }
        }
        .task(id: entry.persistentModelID) {
            receipt = await LogbookReceiptStore.shared.receipt(for: entry)
        }
    }

    private var icon: some View {
        Image(systemName: "square.and.arrow.up")
            .voyageFont(Ramp.TypeScale.bodyM, weight: .regular)
            .foregroundStyle(Ramp.ink)
            .frame(width: 30, height: 30)
    }
}

/// Renders logbook receipts once each and remembers them for the session.
///
/// A receipt is a pure function of its entry, so a row that scrolls out and
/// back must not pay for it twice. The rasterisation itself has to run on the
/// main actor, because that is where `ImageRenderer` and SwiftUI layout live,
/// so the only thing that can be done about its cost is to pay it as rarely as
/// possible and never while a frame is due: the `Task.yield()` below lets the
/// row present itself before the render starts.
///
/// Bounded, because a long logbook would otherwise hold every receipt bitmap
/// alive at 3x for the life of the process.
@MainActor
final class LogbookReceiptStore {
    static let shared = LogbookReceiptStore()

    private var cache: [PersistentIdentifier: RenderedReceipt] = [:]
    private var order: [PersistentIdentifier] = []

    /// Roughly a screenful of rows either side of the visible range.
    private static let capacity = 24

    private init() {}

    func receipt(for entry: LogbookEntry) async -> RenderedReceipt? {
        let key = entry.persistentModelID
        if let cached = cache[key] { return cached }

        // Let the row draw first. Without this the render lands inside the
        // same turn as the row's first layout and stalls its appearance.
        await Task.yield()
        if Task.isCancelled { return nil }
        if let cached = cache[key] { return cached }

        guard let rendered = FlightReceiptRenderer.receipt(entry: entry) else { return nil }

        cache[key] = rendered
        order.append(key)
        if order.count > Self.capacity {
            let evicted = order.removeFirst()
            cache.removeValue(forKey: evicted)
        }
        return rendered
    }
}
