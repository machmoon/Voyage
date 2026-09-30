import SwiftUI

/// The frequent-flyer card on Home: tier, a progress bar whose first segment
/// is the welcome bonus, and the distance left translated into a flight
/// ("412 miles to Silver. SFO–LAX gets you there."). Goal gradient: people
/// speed up as the reward gets closer, so the finish line is shown as
/// something bookable (Kivetz, Urminsky & Zheng 2006). Tapping it opens the
/// membership card.
struct VoyageMilesCard: View {
    let progress: MilesProgress
    let suggestion: MilesRouteSuggestion?
    let hasDeparted: Bool
    /// The streak with its banked weather delays, shown as umbrella chips.
    var streak: LogbookStats.Streak = .none
    let action: () -> Void

    @State private var fill: Double = 0

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TierBadge(tier: progress.tier)
                    Text(MilesFormat.number(progress.statusMiles))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("VOYAGE MILES")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .tracking(1.2)
                        .opacity(0.6)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .opacity(0.5)
                }
                if progress.next != nil {
                    MilesBar(progress: progress, fill: fill)
                        .frame(height: 6)
                }
                if streak.days >= 1 || streak.tokens > 0 {
                    streakRow
                }
                Text(line)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(progress.isAlmostThere ? Theme.seatFirstGold : .white.opacity(0.8))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(.white)
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(progress.isAlmostThere ? Theme.seatFirstGold.opacity(0.7) : .white.opacity(0.14),
                                  lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(progress.tier.rawValue), \(MilesFormat.miles(progress.statusMiles)). \(streak.days)-day streak, \(streak.tokens) weather delays banked. \(line)")
        .accessibilityHint("Opens your membership card")
        .accessibilityIdentifier("voyage-miles-card")
        .onAppear {
            withAnimation(.easeOut(duration: 1.0).delay(0.4)) { fill = 1 }
        }
    }

    /// "🔥 6-day streak  ☂︎ ☂︎": each banked weather delay is a chip.
    private var streakRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.orange)
            Text(streak.delayedYesterday
                 ? "\(streak.days)-day streak · delayed, not cancelled"
                 : "\(streak.days)-day streak")
                .font(.caption2.weight(.semibold))
                .opacity(0.85)
            Spacer(minLength: 4)
            ForEach(0..<streak.tokens, id: \.self) { _ in
                Image(systemName: "umbrella.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.18), in: Capsule())
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(streak.days)-day streak, \(streak.tokens) weather \(streak.tokens == 1 ? "delay" : "delays") banked")
        .accessibilityIdentifier("streak-weather-delays")
    }

    private var line: String {
        guard hasDeparted else {
            return "Tear your first boarding pass for a 500-mile welcome bonus."
        }
        guard progress.next != nil else { return progress.headline }
        let route = suggestion?.sentence ?? MilesRouteSuggestion.hoursSentence(remaining: progress.remaining)
        return "\(progress.headline). \(route)"
    }
}

/// The tier as a small metal chip.
struct TierBadge: View {
    let tier: FlyerTier
    var large = false

    var body: some View {
        Text(tier.rawValue.uppercased())
            .font(.system(size: large ? 12 : 9, weight: .heavy, design: .rounded))
            .tracking(1)
            .foregroundStyle(tier == .platinum ? .white : Theme.ink)
            .padding(.horizontal, large ? 10 : 7)
            .padding(.vertical, large ? 5 : 3)
            .background(TierStyle.metal(tier), in: Capsule())
    }
}

enum TierStyle {
    static func metal(_ tier: FlyerTier) -> LinearGradient {
        let colors: [Color]
        switch tier {
        case .member: colors = [Color(hex: "C9D6F2"), Color(hex: "8FA6D6")]
        case .silver: colors = [Color(hex: "F1F3F6"), Color(hex: "AEB6C2")]
        case .gold: colors = [Theme.seatFirstGoldLight, Theme.seatFirstGold]
        case .platinum: colors = [Color(hex: "5A6272"), Color(hex: "1C212B")]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The membership card's face.
    static func card(_ tier: FlyerTier) -> [Color] {
        switch tier {
        case .member: return [Color(hex: "1D2F5C"), Color(hex: "0E1730")]
        case .silver: return [Color(hex: "8C96A6"), Color(hex: "3C4452")]
        case .gold: return [Color(hex: "B8913E"), Color(hex: "5E4515")]
        case .platinum: return [Color(hex: "2A2F38"), Color(hex: "07090C")]
        }
    }
}
