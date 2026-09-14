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
    @State private var focus = FocusIntegration.shared

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
            // Scrolls so the intro copy wraps instead of truncating when the
            // three fields plus the keyboard leave it no room at large text sizes.
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 6) {
                        Image(systemName: "suitcase.rolling.fill")
                            .voyageFont(34)
                            .foregroundStyle(Theme.accent)
                            .padding(.bottom, 4)
                        Text("Check a bag")
                            .font(.title2.bold())
                            .foregroundStyle(Theme.seatMapInk)
                        Text("Up to three things to finish on this flight.")
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

                    focusNote
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .contentMargins(.bottom, 16, for: .scrollContent)
            // At large text sizes the third field scrolls under the footer.
            // Fading the list's last 28pt says "there is more below" instead
            // of looking like the footer cut it off (QA/e2e-ax-05-checkbag.png).
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 28)
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button {
                    session.intentions = items
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    Haptics.success()
                    CabinAudioEngine.shared.playScanBeep()
                    onContinue()
                } label: {
                    // "Skip for now" is load-bearing: ScreenshotTourUITests taps
                    // it by label. Do not rename it without updating the test.
                    Text(packedCount > 0
                         ? "Check \(packedCount) \(packedCount == 1 ? "bag" : "bags")"
                         : "Skip for now")
                }
                .buttonStyle(VoyageAccentButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
        .onAppear {
            Task {
                await focus.refresh()
            }
        }
    }

    private var focusNote: some View {
        HStack(spacing: 8) {
            Image(systemName: focus.boardingStatusSymbol)
                .voyageFont(11, weight: .bold)
                .foregroundStyle(Theme.accent)
            Text(focus.boardingStatusText)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.seatMapInk.opacity(0.65))
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.seatMapInk.opacity(0.05), in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
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

    /// One paper luggage label per bag, the pre-thermal kind with an eyelet
    /// and a ruled line you write on. Modelled on the SFO Museum's c. 1965
    /// paper destination tag (collection.sfomuseum.org/objects/1511928635):
    /// carrier mark and destination in the head, blank rule below. The
    /// thermal IATA strip was rejected: its proportion is one enormous
    /// airport code, and three lines of a student's own words have nowhere
    /// to sit on it.
    private func bagField(_ index: Int) -> some View {
        let filled = !items[index].trimmingCharacters(in: .whitespaces).isEmpty
        return HStack(spacing: 0) {
            // Eyelet and the string through it.
            ZStack {
                Circle()
                    .strokeBorder(Theme.seatMapInk.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 14, height: 14)
                Circle()
                    .fill(Color(.systemGroupedBackground))
                    .frame(width: 7, height: 7)
            }
            .frame(width: 34)
            Rectangle()
                .fill(Theme.seatMapInk.opacity(0.12))
                .frame(width: 1)
                .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("VOYAGE AIR")
                    Text("·")
                    Text(session.itinerary.destination.code)
                    Spacer()
                    Text("BAG \(index + 1)")
                }
                .font(.system(size: 8, weight: .semibold))
                .kerning(1)
                .foregroundStyle(Theme.seatMapInk.opacity(0.4))
                TextField("Bag \(index + 1), e.g. Review chapter 4", text: $items[index])
                    .font(.body)
                    .focused($focusedIndex, equals: index)
                    .submitLabel(index < 2 ? .next : .done)
                    .onSubmit {
                        focusedIndex = index < 2 ? index + 1 : nil
                    }
                Rectangle()
                    .fill(filled ? Theme.accent.opacity(0.7) : Theme.seatMapInk.opacity(0.18))
                    .frame(height: 1)
            }
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .padding(.vertical, 11)
        }
        .background(
            Theme.passportPaper,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.seatMapInk.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }
}
