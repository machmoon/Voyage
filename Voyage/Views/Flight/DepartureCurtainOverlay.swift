import SwiftUI

/// Full-screen "cleared for departure" beat shown after the boarding pass
/// tears and before the in-flight timer appears.
struct DepartureCurtainOverlay: View {
    let originCode: String
    let destinationCode: String
    let durationText: String
    var compact: Bool = false
    /// How long the curtain is expected to hold at minimum. The route track
    /// paces its sweep to this, so the plane is still travelling when the
    /// hand-off normally happens instead of parking at the end.
    var sweepDuration: TimeInterval = 2.8

    @State private var progress: CGFloat = 0.5
    @State private var pulse = false
    /// Set once the first sweep lands. The curtain may hold past its minimum
    /// while the satellite window finishes loading, so the track keeps taxiing
    /// rather than sitting still and reading as a freeze.
    @State private var isHolding = false

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
                    // Deliberately NOT scaled: this glyph sits inside a fixed
                    // 66pt ring inside a fixed 82pt disc, so growing it with the
                    // text size pushes it through both.
                    Image(systemName: "airplane.departure")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.pulse, value: pulse)
                }

                VStack(spacing: 8) {
                    Text("CLEARED FOR DEPARTURE")
                        .voyageFont(11, weight: .heavy, design: .monospaced)
                        .kerning(1.7)
                        .foregroundStyle(Theme.accent.opacity(0.95))

                    HStack(spacing: 14) {
                        Text(originCode)
                        routeTrack
                        Text(destinationCode)
                    }
                    .voyageFont(28, weight: .heavy, design: .monospaced)
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
            // Breathing glow, not a one-shot: whatever the hold turns out to
            // be, the screen is always moving.
            withAnimation(.easeInOut(duration: compact ? 1.1 : 1.7).repeatForever(autoreverses: true)) {
                pulse = true
            }
            // Pace the sweep to the expected hold rather than finishing in a
            // fraction of it.
            withAnimation(.easeInOut(duration: max(0.28, sweepDuration * 0.86))) {
                progress = 1
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(Int(max(0.28, sweepDuration * 0.86) * 1_000)))
                withAnimation(.easeInOut(duration: compact ? 0.5 : 0.9).repeatForever(autoreverses: true)) {
                    isHolding = true
                }
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
                    .fill(Theme.accent.opacity(isHolding ? 0.55 : 0.95))
                    .frame(width: max(2, geo.size.width * progress), height: 2)
                Circle()
                    .fill(.white.opacity(0.9))
                    .frame(width: 5, height: 5)
                // Deliberately NOT scaled: this glyph rides a 2pt progress
                // track and its x offset is computed from the track geometry.
                // Scaling it desynchronises the plane from the line it flies.
                Image(systemName: "airplane")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: Theme.accent.opacity(isHolding ? 1 : 0.8), radius: isHolding ? 8 : 5)
                    // A gentle hold-short bob keeps the track alive if the
                    // curtain waits past its minimum for the window to load.
                    .offset(x: travel * progress + (isHolding ? 2.5 : 0))
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: 84, height: 18)
    }
}
