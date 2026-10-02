import SwiftUI

/// The "Landed" beat: a short full-screen moment at touchdown, before the
/// welcome screen, and the arrival bookend to `DepartureCurtainOverlay`. Same
/// navy curtain, same breathing accent glow, same glyph disc (the arrival
/// airplane instead of the departure one), so the trip opens and closes on
/// one shape.
///
/// One headline, one phrase, one small line, then it lifts by itself after
/// `holdDuration` or on a tap. The phrase is drawn from `LandingPhrases`.
///
/// Design notes. Flighty's landed push and Apple Fitness's ring close both put
/// one fact first ("Landed", the closed ring) and keep the celebration to a
/// single beat; Duolingo's lesson-complete screen adds a randomised cheer
/// line under the result. All three are closed source, so this follows what
/// they show, not their code. The rotating line follows Gemini CLI's phrase
/// cycler (see `LandingPhrases`).
struct LandedCurtainOverlay: View {
    let destinationCode: String
    let durationText: String
    let phrase: String
    /// Lifts on its own after this long; a tap lifts it sooner.
    var holdDuration: TimeInterval = 2.6
    /// QA captures keep the curtain up until a tap.
    var holds: Bool = false
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pulse = false
    @State private var revealed = false
    @State private var finished = false

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
            .scaleEffect(reduceMotion ? 1 : (pulse ? 1.2 : 0.75))
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
                    // Fixed size inside fixed rings, as on the departure curtain.
                    Image(systemName: "airplane.arrival")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: revealed)
                }

                VStack(spacing: 10) {
                    Text("Landed \(Text(destinationCode).foregroundStyle(Theme.accent))")
                        .foregroundStyle(.white)
                        .voyageFont(40, weight: .heavy, design: .monospaced)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text(phrase)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(revealed ? 1 : 0)
                        .offset(y: revealed || reduceMotion ? 0 : 10)

                    Text("\(durationText) focused")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.52))
                        .padding(.top, 2)
                        .opacity(revealed ? 1 : 0)
                }
            }
            .padding(.horizontal, 28)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: finish)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Landed in \(destinationCode). \(phrase) \(durationText) focused.")
        .accessibilityHint("Double-tap to continue")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("landed-curtain")
        .onAppear {
            Haptics.success()
            if reduceMotion {
                pulse = true
            } else {
                withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
            withAnimation(.smooth(duration: 0.6).delay(0.25)) { revealed = true }
        }
        .task {
            guard !holds else { return }
            try? await Task.sleep(for: .milliseconds(Int(holdDuration * 1_000)))
            finish()
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }
}

#Preview {
    LandedCurtainOverlay(destinationCode: "SFO", durationText: "1h 25m",
                         phrase: "Time to deplane!", holds: true) {}
}
