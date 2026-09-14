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
            // The picker strip sat on the plain background while both tabs use
            // the grouped one, which drew a visible seam under the title bar.
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Logbook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(.systemGroupedBackground), for: .navigationBar)
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

            Section("Flights") {
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
            }
        }
    }

    // MARK: Recorder row

    /// Entry point to the flight data recorder. The caption states where the
    /// recorder stands rather than promising insight it may not have.
    private var recorderRow: some View {
        HStack(spacing: 13) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 19))
                .foregroundStyle(Theme.accent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text("Flight data recorder")
                    .font(.subheadline.weight(.semibold))
                Text(recorderCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
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

    private var statusCard: some View {
        VStack(spacing: 16) {
            // The rating card. One rating at a time, one row per requirement,
            // the way MyFlightbook lays out a rating
            // (MyFlightbook.Web/Areas/mvc/Views/Training/_ratingsProgressList.cshtml):
            // a check for AchieveOnce items, a progress bar with the
            // ProgressDisplay text for Count and Time items.
            // One number, one line under it. Hours is the number a student
            // pilot watches; the rating, landings and airports are its caption.
            VStack(alignment: .leading, spacing: 4) {
                Text(PilotRatings.hoursText(LogbookStats.totalFocusSeconds(entries)))
                    .voyageFont(38, weight: .semibold)
                    .monospacedDigit()
                let landings = entries.filter(\.completed)
                Text("\(rating.current.title) · \(landings.count) landings")
                    .font(.subheadline)
                    .opacity(0.72)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Only what is still open. A met requirement is already
            // implied by the rating name, and a list of checks is clutter.
            let openRequirements = rating.nextRequirements.filter { !$0.isSatisfied }
            if !openRequirements.isEmpty, let next = rating.next {
                VStack(spacing: 10) {
                    Text("Toward \(next.title)")
                        .font(.caption.weight(.semibold))
                        .opacity(0.72)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(openRequirements) { requirement in
                        requirementRow(requirement)
                    }
                }
            }

            if !weekEntries.isEmpty {
            Button {
                Haptics.tap()
                replaySelection = ReplaySelection(entries: weekEntries, title: "This Week")
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                        .voyageFont(11, weight: .black)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Replay this week")
                            .font(.subheadline.weight(.bold))
                        Text(weekEntries.isEmpty
                             ? "No completed flights yet"
                             : "\(weekEntries.count) flight\(weekEntries.count == 1 ? "" : "s") · \(Int(LogbookStats.totalMiles(weekEntries)).formatted()) miles")
                            .font(.caption2.weight(.medium))
                            .opacity(0.68)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .opacity(0.6)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                // minHeight, not height: the label inside is two lines of
                // scaling text and a fixed 54 clipped it from AX2 up.
                .frame(minHeight: 54)
                .background(Theme.accent.opacity(weekEntries.isEmpty ? 0.12 : 0.22),
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(Theme.accent.opacity(weekEntries.isEmpty ? 0.12 : 0.34), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(weekEntries.isEmpty)
            .accessibilityLabel("Replay \(weekEntries.count) flights from this week")
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(Theme.surfaceDark, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }

    /// One checklist line: title and progress text over a bar while a
    /// requirement is open, and a check once it is met. A met count row
    /// collapses to the check too, so "44 of 10 landings" never shows, the
    /// way MyFlightbook's ratings progress list marks completed items.
    private func requirementRow(_ requirement: RatingRequirement) -> some View {
        let showsCheck = requirement.kind == .achieveOnce || requirement.isSatisfied
        return VStack(spacing: 5) {
            HStack(spacing: 8) {
                if showsCheck {
                    Image(systemName: requirement.isSatisfied ? "checkmark.circle.fill" : "circle")
                        .voyageFont(12, weight: .semibold)
                        .foregroundStyle(requirement.isSatisfied ? Theme.accent : .white.opacity(0.4))
                }
                Text(requirement.title)
                    .font(.subheadline)
                    .opacity(requirement.isSatisfied ? 0.6 : 0.9)
                Spacer(minLength: 8)
                if !showsCheck {
                    Text(requirement.progressText)
                        .font(.caption)
                        .monospacedDigit()
                        .opacity(0.75)
                }
            }
            if !showsCheck {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.12))
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: geo.size.width * requirement.fraction)
                    }
                }
                .frame(height: 5)
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

    private func entryRow(_ entry: LogbookEntry) -> some View {
        HStack(spacing: 14) {
            // Mini stamp.
            VStack(spacing: 1) {
                Text(entry.destinationCode)
                    .voyageFont(13, weight: .black, design: .monospaced)
                Text(entry.completed ? "ADMITTED" : "STOPPED EARLY")
                    .voyageFont(5.5, weight: .heavy)
                    .kerning(0.5)
            }
            .foregroundStyle(entry.completed ? entry.destination.accentColor : .secondary)
            // The mini stamp is a scale drawing, so it is capped rather than
            // grown: a stamp that doubles in size pushes the route and the
            // miles off the row. Same call WordPress-iOS makes on its fixed
            // cards (Modules/Sources/JetpackStats/Cards/TopListCard.swift).
            .frame(width: 58, height: 44)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(entry.completed ? entry.destination.accentColor : Color(.systemGray4),
                                  lineWidth: 1.5)
            )
            .rotationEffect(.degrees(-4))
            .opacity(entry.completed ? 1 : 0.6)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text("\(entry.originCode) → \(entry.destinationCode)")
                        .font(.subheadline.weight(.semibold))
                    if let via = entry.connectionCode {
                        Text("via \(via)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                // Date and length. Flight number, seat, bags and miles are
                // on the receipt and the stamp, not repeated on every row.
                Text("\(entry.date.formatted(.dateTime.month(.abbreviated).day())) · \(entry.focusSeconds.shortDurationText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if entry.completed {
                LogbookShareButton(entry: entry)
            }
        }
        .padding(.vertical, 4)
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
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.accent)
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
