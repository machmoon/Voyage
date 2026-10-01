import SwiftUI

/// Shown on the arrival that earns the First class reward: the cabin, what
/// earned it, and when it takes effect. Built like `TierUpCard` (same sheet,
/// same chime and haptic at the call site), because it is the same kind of
/// moment: a reward for work already done, shown once, at the gate, never
/// mid-flight.
struct FirstClassUnlockedCard: View {
    @Environment(\.dismiss) private var dismiss
    @State private var shown = false

    var body: some View {
        VStack(spacing: 18) {
            Text("UPGRADE EARNED")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(2)
                .foregroundStyle(Theme.seatFirstGold)
                .padding(.top, 28)
            FirstSeatGlyph()
                .frame(width: 58, height: 62)
                .scaleEffect(shown ? 1.5 : 0.4)
                .rotationEffect(.degrees(shown ? 0 : -20))
                .padding(.vertical, 18)
            Text("First class is yours.")
                .font(.title.bold())
                .foregroundStyle(Theme.textPrimary)
                .accessibilityIdentifier("first-class-unlocked-title")
            Text(Self.reason)
                .font(.headline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Text("Every seat up front, from your next booking. Earned, so it stays.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
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
        .accessibilityIdentifier("first-class-unlocked-card")
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.55)) { shown = true }
        }
    }

    /// "8 focus hours over 5 flying days."
    static var reason: String {
        "\(Int(FirstClassReward.requiredFocusSeconds / 3_600)) focus hours over "
            + "\(FirstClassReward.requiredFlightDays) flying days."
    }
}
