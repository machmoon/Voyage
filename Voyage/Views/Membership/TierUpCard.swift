import SwiftUI

/// Shown on the arrival that crosses a tier: the new status and its perk,
/// then immediately the next tier's bar with the surplus miles on it. People
/// slow down, and are most likely to quit, right after a reward (Kivetz,
/// Urminsky & Zheng 2006), so the bar never reads zero here.
struct TierUpCard: View {
    let progress: MilesProgress
    @Environment(\.dismiss) private var dismiss
    @State private var shown = false
    @State private var fill: Double = 0

    var body: some View {
        VStack(spacing: 18) {
            Text("NEW STATUS")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(2)
                .foregroundStyle(Theme.seatFirstGold)
                .padding(.top, 28)
            TierBadge(tier: progress.tier, large: true)
                .scaleEffect(shown ? 1.6 : 0.4)
                .rotationEffect(.degrees(shown ? 0 : -20))
                .padding(.vertical, 14)
            Text("Welcome to \(progress.tier.rawValue).")
                .font(.title.bold())
                .foregroundStyle(Theme.textPrimary)
            Text(progress.tier.perkDescription + ". Yours now.")
                .font(.headline)
                .foregroundStyle(Theme.textSecondary)
            if let line = progress.carryOverLine {
                VStack(alignment: .leading, spacing: 8) {
                    MilesBar(progress: progress, fill: fill).frame(height: 10)
                    Text(line)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .padding(16)
                .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 24)
            }
            Spacer(minLength: 0)
            Button("Onward") { dismiss() }
                .buttonStyle(VoyagePrimaryButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.boardingBackdrop.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("tier-up-card")
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.55)) { shown = true }
            withAnimation(.easeOut(duration: 1.0).delay(0.5)) { fill = 1 }
        }
    }
}
