import SwiftUI
import SwiftData

/// Passport-style history of every flight, plus miles, streak, and tier progress.
struct LogbookView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LogbookEntry.date, order: .reverse) private var entries: [LogbookEntry]

    private var tier: FlyerTier { LogbookStats.tier(entries) }
    private var totalMiles: Double { LogbookStats.totalMiles(entries) }

    var body: some View {
        NavigationStack {
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
            .navigationTitle("Logbook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
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
                        .font(.system(size: 20, weight: .black))
                        .kerning(2)
                    Text(tier.perkDescription)
                        .font(.caption)
                        .opacity(0.75)
                }
                Spacer()
                Image(systemName: "airplane.circle.fill")
                    .font(.system(size: 34))
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
                            Capsule().fill(.white.opacity(0.25))
                            Capsule()
                                .fill(.white)
                                .frame(width: geo.size.width * tierProgress(to: next))
                        }
                    }
                    .frame(height: 5)
                    Text("\(Int(max(0, next.threshold - totalMiles)).formatted()) mi to \(next.rawValue)")
                        .font(.system(size: 10, weight: .semibold))
                        .opacity(0.75)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(
            LinearGradient(colors: [Color(hex: "23345C"), Color(hex: "101A33")],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
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
                .font(.system(size: 18, weight: .bold, design: .monospaced))
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold))
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
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                Text(entry.completed ? "ADMITTED" : "DIVERTED")
                    .font(.system(size: 5.5, weight: .heavy))
                    .kerning(0.5)
            }
            .foregroundStyle(entry.completed ? entry.destination.accentColor : .secondary)
            .frame(width: 58, height: 44)
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

            VStack(alignment: .trailing, spacing: 3) {
                Text("+\(Int(entry.miles).formatted()) mi")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(entry.completed ? .primary : .secondary)
                Text(entry.focusSeconds.shortDurationText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
