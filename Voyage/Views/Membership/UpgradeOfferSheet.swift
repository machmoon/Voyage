import SwiftUI

/// The upgrade prompt a locked First seat raises: both ways to the front of
/// the plane, side by side. Free first ("Earn it", with the real miles and a
/// real route), paid second ("Fly First today"). It is shaped like the
/// upgrade offer an airline app shows at seat selection: the seat, the
/// cabin, what it would take, and a way to keep the seat you have.
///
/// The paywall is RevenueCat's dashboard paywall (`firstClassPaywall`),
/// attached here rather than on the seat map because a sheet cannot present
/// from under another sheet. When the entitlement turns active the sheet
/// closes itself and `onUpgraded` runs, which is where the seat map plays
/// the unlock.
struct UpgradeOfferSheet: View {
    let seat: String
    /// The seat the traveler holds now, if any ("Keep 14C").
    let currentSeat: String?
    let progress: MilesProgress
    let suggestion: MilesRouteSuggestion?
    let onUpgraded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var membership = Membership.shared
    @State private var showsPaywall = false
    @State private var barFill: Double = 0
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                earnCard
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 14)
                flyFirstCard
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 24)
                Text("Status can't be bought. Voyage First only buys the seat, never miles or tiers.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 20)
            .padding(.top, 26)
            .padding(.bottom, 24)
        }
        .background(Theme.boardingBackdrop.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("upgrade-offer-sheet")
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.85).delay(0.05)) { appeared = true }
            withAnimation(.easeOut(duration: 1.1).delay(0.35)) { barFill = 1 }
        }
        .onChange(of: membership.isFirstClass) { _, isMember in
            guard isMember else { return }
            showsPaywall = false
            // Let the paywall slide away before this sheet does, so the seat
            // map's unlock is the next thing on screen, not a double dismiss.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 450_000_000)
                dismiss()
                try? await Task.sleep(nanoseconds: 350_000_000)
                onUpgraded()
            }
        }
        .firstClassPaywall(isPresented: $showsPaywall)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            FirstSeatGlyph()
                .frame(width: 58, height: 62)
            VStack(alignment: .leading, spacing: 4) {
                Text("UPGRADE OFFER")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(Theme.seatFirstGold)
                Text("Seat \(seat) is in First.")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityIdentifier("upgrade-offer-title")
            }
        }
    }

    // MARK: Earn it

    private var earnCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardLabel("EARN IT", trailing: "free, always")
            if progress.next != nil {
                Text(progress.headline + ".")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(progress.isAlmostThere ? Theme.seatFirstGold : Theme.textPrimary)
                    .accessibilityIdentifier("upgrade-offer-miles")
                Text(suggestion?.sentence ?? MilesRouteSuggestion.hoursSentence(remaining: progress.remaining))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                MilesBar(progress: progress, fill: barFill)
                    .frame(height: 12)
                HStack {
                    if progress.bonusMiles > 0 {
                        Label("500 welcome bonus", systemImage: "gift.fill")
                    }
                    Spacer()
                    if let next = progress.next {
                        Text("\(next.rawValue) at \(MilesFormat.number(next.threshold))")
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            } else {
                Text("Your status already opens this cabin.")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .padding(18)
        .background(cardBackground(highlight: false))
    }

    // MARK: Fly First

    private var flyFirstCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardLabel("FLY FIRST TODAY", trailing: "Voyage First")
            Text("Any seat up front, on every flight.")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            VStack(alignment: .leading, spacing: 6) {
                perk("carseat.right.fill", "Every First seat on every aircraft")
                perk("tag.fill", "Priority bag tags and carrier liveries")
                perk("heart.fill", "Keeps Voyage free and open source")
            }
            HStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    _ = Membership.shared.requireFirstClass(from: "seat-\(seat)", paywall: $showsPaywall)
                } label: {
                    Text("See Voyage First")
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            LinearGradient(colors: [Theme.seatFirstGoldLight, Theme.seatFirstGold],
                                           startPoint: .top, endPoint: .bottom),
                            in: Capsule())
                }
                .accessibilityIdentifier("upgrade-see-voyage-first")
                .disabled(!membership.isConfigured)

                Button {
                    Haptics.softTick()
                    dismiss()
                } label: {
                    Text(currentSeat.map { "Keep \($0)" } ?? "Not now")
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Theme.surfaceSubtle, in: Capsule())
                }
                .accessibilityIdentifier("upgrade-keep-seat")
            }
            if !membership.isConfigured {
                Text("Voyage First isn't available in this build.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(18)
        .background(cardBackground(highlight: true))
    }

    // MARK: Pieces

    private func cardLabel(_ title: String, trailing: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(trailing)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func perk(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).foregroundStyle(Theme.textPrimary)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Theme.seatFirstGold)
        }
        .font(.subheadline)
    }

    private func cardBackground(highlight: Bool) -> some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Theme.surfaceElevated)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(highlight ? Theme.seatFirstGold.opacity(0.55) : Color.white.opacity(0.08),
                                  lineWidth: highlight ? 1.2 : 1)
            }
    }
}

/// The progress bar with the welcome bonus as its own first segment.
struct MilesBar: View {
    let progress: MilesProgress
    /// 0...1, animated by the caller so the bar fills on appear.
    var fill: Double = 1
    var tint: Color = Theme.accent

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let total = progress.fraction * fill
            let bonus = min(total, progress.bonusFraction * fill)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                Capsule()
                    .fill(progress.isAlmostThere ? Theme.seatFirstGold : tint)
                    .frame(width: max(0, width * total))
                if bonus > 0 {
                    Capsule()
                        .fill(Theme.seatFirstGoldLight)
                        .frame(width: max(0, width * bonus))
                        .overlay(alignment: .trailing) {
                            Rectangle().fill(Theme.ink.opacity(0.6)).frame(width: 1.5)
                        }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(Int((progress.fraction * 100).rounded())) percent of the way to \(progress.next?.rawValue ?? "the top tier")")
    }
}

/// A First seat seen from above, drawn with a slow gold sheen.
struct FirstSeatGlyph: View {
    @State private var sheen = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [Theme.seatFirstGoldLight, Theme.seatFirstGold],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Capsule()
                .fill(.white.opacity(0.6))
                .frame(width: 26, height: 4)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 8)
            LinearGradient(colors: [.clear, .white.opacity(0.55), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 22)
                .rotationEffect(.degrees(20))
                .offset(x: sheen ? 60 : -60)
                .blendMode(.plusLighter)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Theme.seatFirstGold.opacity(0.45), radius: 14)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: false).delay(0.4)) {
                sheen = true
            }
        }
        .accessibilityHidden(true)
    }
}
