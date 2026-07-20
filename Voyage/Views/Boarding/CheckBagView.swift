import SwiftUI
import SwiftData

/// Optional intentions step: "check a bag" with up to three things
/// you're working on this flight. Fully skippable; recent bags come back
/// as one-tap chips so regulars never retype them.
struct CheckBagView: View {
    @Bindable var session: FlightSession
    let onContinue: () -> Void

    @State private var items = ["", "", ""]
    @FocusState private var focusedIndex: Int?
    @Query(sort: \LogbookEntry.date, order: .reverse) private var entries: [LogbookEntry]

    private var packedCount: Int {
        items.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    /// Up to six distinct intentions from recent flights, newest first,
    /// excluding ones already packed this time.
    private var recentBags: [String] {
        var seen = Set(items.map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        var result: [String] = []
        for entry in entries.prefix(20) {
            for intention in entry.intentions {
                let key = intention.lowercased()
                if !seen.contains(key) {
                    seen.insert(key)
                    result.append(intention)
                    if result.count == 6 { return result }
                }
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Image(systemName: "suitcase.rolling.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.accentColor)
                    .padding(.bottom, 4)
                Text("Check a bag?")
                    .font(.title2.bold())
                Text("Pack up to three things you're working on this flight. You'll pick them up at baggage claim when you land.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.top, 24)

            VStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { index in
                    bagField(index)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)

            if !recentBags.isEmpty {
                recentBagsRow
                    .padding(.top, 14)
            }

            Spacer()

            VStack(spacing: 10) {
                Button {
                    session.intentions = items
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    Haptics.success()
                    onContinue()
                } label: {
                    Text(packedCount > 0 ? "Check \(packedCount) \(packedCount == 1 ? "bag" : "bags")" : "Continue")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.accentColor,
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                Button("Travel light — skip") {
                    session.intentions = []
                    onContinue()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
        .onAppear { focusedIndex = 0 }
    }

    /// One-tap chips for bags you've flown with before.
    private var recentBagsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(recentBags, id: \.self) { bag in
                    Button {
                        guard let slot = items.firstIndex(where: {
                            $0.trimmingCharacters(in: .whitespaces).isEmpty
                        }) else { return }
                        Haptics.tap()
                        items[slot] = bag
                    } label: {
                        Label(bag, systemImage: "plus")
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Theme.accent.opacity(0.12), in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .accessibilityLabel("Recent bags")
    }

    private func bagField(_ index: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "tag.fill")
                .font(.caption)
                .foregroundStyle(items[index].isEmpty ? Color(.tertiaryLabel) : Color.accentColor)
            TextField("Bag \(index + 1) — e.g. \"Finish chapter 4 notes\"", text: $items[index])
                .focused($focusedIndex, equals: index)
                .submitLabel(index < 2 ? .next : .done)
                .onSubmit {
                    focusedIndex = index < 2 ? index + 1 : nil
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.cardBackground,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
