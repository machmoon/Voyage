import SwiftUI

/// Full-screen "cleared for departure" beat shown after the boarding pass
/// tears and before the in-flight timer appears.
struct DepartureCurtainOverlay: View {
    let originCode: String
    let destinationCode: String
    let durationText: String
    var compact: Bool = false

    @State private var progress: CGFloat = 0.5
    @State private var pulse = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "0D1531"), Color(hex: "050713")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [Theme.accent.opacity(0.24), Theme.accent.opacity(0.04), .clear],
                center: .center,
                startRadius: 8,
                endRadius: 330
            )
            .scaleEffect(pulse ? 1.2 : 0.75)
            .opacity(pulse ? 1 : 0.35)
            .ignoresSafeArea()

            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.14))
                        .frame(width: 82, height: 82)
                    Circle()
                        .strokeBorder(Theme.accent.opacity(0.3), lineWidth: 1)
                        .frame(width: 66, height: 66)
                    Image(systemName: "airplane.departure")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.pulse, value: pulse)
                }

                VStack(spacing: 8) {
                    Text("CLEARED FOR DEPARTURE")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .kerning(1.7)
                        .foregroundStyle(Theme.accent.opacity(0.95))

                    HStack(spacing: 14) {
                        Text(originCode)
                        routeTrack
                        Text(destinationCode)
                    }
                    .font(.system(size: 28, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)

                    Text("\(durationText) focus flight")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.52))
                }
            }
            .padding(.horizontal, 28)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cleared for departure, \(originCode) to \(destinationCode)")
        .onAppear {
            withAnimation(.smooth(duration: compact ? 0.28 : 0.65)) {
                progress = 1
                pulse = true
            }
        }
    }

    private var routeTrack: some View {
        GeometryReader { geo in
            let travel = max(0, geo.size.width - 14)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.18))
                    .frame(height: 2)
                Capsule()
                    .fill(Theme.accent.opacity(0.95))
                    .frame(width: max(2, geo.size.width * progress), height: 2)
                Circle()
                    .fill(.white.opacity(0.9))
                    .frame(width: 5, height: 5)
                Image(systemName: "airplane")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: Theme.accent.opacity(0.8), radius: 5)
                    .offset(x: travel * progress)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: 84, height: 18)
    }
}
