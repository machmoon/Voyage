import SwiftUI

/// A location-authored exterior plate with real-time aircraft motion layered
/// over it. SFO is the first bespoke world: runway 28 departure, bay reveal,
/// and the city rising through the climb. Other airports continue through the
/// procedural weather renderer until they receive their own licensed plates.
struct AirportWorldSceneView: View {
    let airport: Airport
    let phase: LegPhase
    let altitudeFraction: Double
    let isNight: Bool
    let condition: SkyCondition
    let isLeftSide: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phaseStart = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 / 12.0 : 1.0 / 30.0)) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSince(phaseStart))
            let climb = climbProgress(elapsed: elapsed)
            let roll = rollProgress(elapsed: elapsed)

            ZStack {
                Image("SFOClimbWorld")
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(worldScale(climb: climb, roll: roll))
                    .offset(worldOffset(climb: climb, roll: roll))
                    .rotationEffect(.degrees(bankDegrees(climb: climb)))
                    .scaleEffect(x: isLeftSide ? -1 : 1, y: 1)
                    .saturation(isNight ? 0.45 : 1)
                    .brightness(isNight ? -0.32 : 0)
                    .overlay(atmosphere(climb: climb))

                if phase == .takeoffRoll || phase == .landing {
                    runwayMotion(elapsed: elapsed, roll: roll)
                }

                if phase == .climb || phase == .descent {
                    cloudPass(elapsed: elapsed, climb: climb)
                }

                windowReflection
            }
            .clipped()
        }
        .onChange(of: phase) { _, _ in phaseStart = Date() }
        .onAppear { phaseStart = Date() }
        .accessibilityLabel("View outside over \(airport.city)")
    }

    private func rollProgress(elapsed: TimeInterval) -> Double {
        guard phase == .takeoffRoll || phase == .landing else { return 1 }
        let duration = phase == .takeoffRoll ? FlightSession.takeoffRollDuration : FlightSession.landingDuration
        return min(1, elapsed / max(0.1, duration))
    }

    private func climbProgress(elapsed: TimeInterval) -> Double {
        switch phase {
        case .takeoffRoll: return 0
        case .climb:
            let span = max(0.1, FlightSession.climbEndsAt - FlightSession.takeoffRollDuration)
            return min(1, elapsed / span)
        case .cruise: return 1
        case .descent: return max(0.25, altitudeFraction)
        case .landing: return 0
        }
    }

    private func worldScale(climb: Double, roll: Double) -> CGFloat {
        switch phase {
        case .takeoffRoll, .landing: return 1.32 + 0.12 * roll
        case .climb: return 1.32 + 0.58 * climb
        case .cruise: return 1.9
        case .descent: return 1.72
        }
    }

    private func worldOffset(climb: Double, roll: Double) -> CGSize {
        switch phase {
        case .takeoffRoll:
            return CGSize(width: -CGFloat(roll * 92), height: CGFloat(28 + roll * 110))
        case .landing:
            return CGSize(width: CGFloat(roll * 50), height: CGFloat(75 - roll * 30))
        case .climb:
            // The airport drops away, exposing the bay then skyline.
            return CGSize(width: CGFloat(-climb * 24), height: CGFloat(120 + climb * 185))
        case .cruise:
            return CGSize(width: 0, height: 330)
        case .descent:
            return CGSize(width: 0, height: 245)
        }
    }

    private func bankDegrees(climb: Double) -> Double {
        guard phase == .climb, !reduceMotion else { return 0 }
        return isLeftSide ? 3.2 * sin(climb * .pi) : -3.2 * sin(climb * .pi)
    }

    private func atmosphere(climb: Double) -> some View {
        LinearGradient(
            colors: [
                .clear,
                Color(hex: isNight ? "0A1020" : "B8D1E5").opacity(0.08 + climb * 0.18),
                Color(hex: isNight ? "02050B" : "E7F1F7").opacity(climb * 0.20)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .blendMode(.screen)
    }

    private func runwayMotion(elapsed: TimeInterval, roll: Double) -> some View {
        Canvas { context, size in
            let velocity = 10 + roll * 68
            let stripeY = size.height * 0.79
            var x = -CGFloat((elapsed * velocity).truncatingRemainder(dividingBy: 86))
            while x < size.width {
                let length = 12 + roll * 52
                context.fill(
                    Path(roundedRect: CGRect(x: x, y: stripeY, width: length, height: 2.5), cornerRadius: 1.25),
                    with: .color(.white.opacity(0.18 + roll * 0.24))
                )
                x += 86
            }
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
    }

    private func cloudPass(elapsed: TimeInterval, climb: Double) -> some View {
        Canvas { context, size in
            let phaseT = phase == .climb ? climb : 1 - climb
            let baseY = size.height * (0.23 + phaseT * 0.55)
            var layer = context
            layer.addFilter(.blur(radius: 15))
            for index in 0..<8 {
                let x = CGFloat(index) * size.width / 7 - CGFloat(elapsed * (12 + Double(index) * 5)).truncatingRemainder(dividingBy: 90)
                let y = baseY + CGFloat((index % 3) * 42)
                let w = size.width * CGFloat(0.28 + Double(index % 3) * 0.08)
                let h = size.height * CGFloat(0.12 + Double(index % 2) * 0.06)
                let opacity = max(0, min(0.55, phaseT * 0.62))
                layer.fill(Path(ellipseIn: CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h)),
                           with: .color(.white.opacity(opacity)))
            }
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
    }

    private var windowReflection: some View {
        LinearGradient(
            colors: [.white.opacity(0.12), .clear, .white.opacity(0.05)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .blendMode(.screen)
        .allowsHitTesting(false)
    }
}
