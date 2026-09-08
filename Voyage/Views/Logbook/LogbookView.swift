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
    private var totalMiles: Double { LogbookStats.totalMiles(entries) }
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
            Section {
                statusCard
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
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

    // MARK: Status card

    private var statusCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tier.rawValue.uppercased())
                        .voyageFont(20, weight: .black)
                        .kerning(2)
                    Text(tier.perkDescription)
                        .font(.caption)
                        .opacity(0.75)
                }
                Spacer()
                Image(systemName: "airplane.circle.fill")
                    .voyageFont(34)
                    .opacity(0.9)
            }

            HStack(spacing: 0) {
                statusStat("\(Int(totalMiles).formatted())", "lifetime miles")
                statusStat("\(entries.filter(\.completed).count)", "flights flown")
                statusStat("\(LogbookStats.streakDays(entries))", "day streak")
            }

            if let next = tier.next {
                VStack(spacing: 5) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.12))
                            Capsule()
                                .fill(Theme.accent)
                                .frame(width: geo.size.width * tierProgress(to: next))
                        }
                    }
                    .frame(height: 5)
                    Text("\(Int(max(0, next.threshold - totalMiles)).formatted()) mi to \(next.rawValue)")
                        .voyageFont(10, weight: .semibold)
                        .opacity(0.75)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

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
            .accessibilityLabel(weekEntries.isEmpty
                                ? "No flights to replay this week"
                                : "Replay \(weekEntries.count) flights from this week")
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(
            LinearGradient(colors: [Theme.surfaceSubtle, Theme.surfaceDark],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func tierProgress(to next: FlyerTier) -> Double {
        let span = next.threshold - tier.threshold
        guard span > 0 else { return 0 }
        return min(1, max(0, (totalMiles - tier.threshold) / span))
    }

    private func statusStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .voyageFont(18, weight: .bold, design: .monospaced)
            Text(label.uppercased())
                .voyageFont(8, weight: .bold)
                .kerning(0.8)
                .opacity(0.65)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Entry row

    private func entryRow(_ entry: LogbookEntry) -> some View {
        HStack(spacing: 14) {
            // Mini stamp.
            VStack(spacing: 1) {
                Text(entry.destinationCode)
                    .voyageFont(13, weight: .black, design: .monospaced)
                Text(entry.completed ? "ADMITTED" : "DIVERTED")
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
                Text("\(entry.date.formatted(date: .abbreviated, time: .shortened)) · \(entry.flightNumber) · seat \(entry.seat)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !entry.intentions.isEmpty {
                    let done = zip(entry.intentions, entry.intentionsCompleted).filter { $1 }.count
                    Text("\(done)/\(entry.intentions.count) bags claimed")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if entry.completed {
                Button {
                    Haptics.tap()
                    replaySelection = ReplaySelection(entries: [entry], title: "Flight \(entry.flightNumber)")
                } label: {
                    Image(systemName: "play.fill")
                        .voyageFont(12, weight: .bold)
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Theme.accent, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Replay flight to \(entry.destinationCode)")
            }

            if entry.completed, let png = FlightReceiptRenderer.pngData(entry: entry),
               let uiImage = UIImage(data: png) {
                ShareLink(
                    item: ReceiptShareItem(pngData: png),
                    preview: SharePreview("Flight to \(entry.destinationCode)", image: Image(uiImage: uiImage))
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .trailing, spacing: 3) {
                Text("+\(Int(entry.miles).formatted()) mi")
                    .voyageFont(13, weight: .bold, design: .monospaced)
                    .foregroundStyle(entry.completed ? .primary : .secondary)
                Text(entry.focusSeconds.shortDurationText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
