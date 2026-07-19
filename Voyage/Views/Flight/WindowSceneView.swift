import SwiftUI

/// Everything visible through the airplane window, drawn procedurally:
/// runway lights, climb through cloud layers with parallax, cruise skies
/// (day / sunset / night / aurora), weather on approach, touchdown.
struct WindowSceneView: View {
    let phase: LegPhase
    /// 0 = on the ground, 1 = cruise altitude.
    let altitudeFraction: Double
    let isNight: Bool
    let condition: SkyCondition
    let showSunset: Bool
    let showAurora: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                drawSky(context: context, size: size, time: t)
                if isNight {
                    drawStars(context: context, size: size, time: t)
                }
                if showAurora && isNight && phase == .cruise {
                    drawAurora(context: context, size: size, time: t)
                }
                drawClouds(context: context, size: size, time: t)
                if phase == .takeoffRoll || phase == .landing {
                    drawRunway(context: context, size: size, time: t)
                }
                if condition == .rain && (phase == .descent || phase == .landing) {
                    drawRain(context: context, size: size, time: t)
                }
                if condition == .snow && (phase == .descent || phase == .landing) {
                    drawSnow(context: context, size: size, time: t)
                }
            }
        }
    }

    // MARK: Sky

    private func drawSky(context: GraphicsContext, size: CGSize, time: Double) {
        let top: Color
        let bottom: Color

        if isNight {
            top = Color(hex: "05070F")
            bottom = altitudeFraction > 0.5 ? Color(hex: "141C3A") : Color(hex: "232B4A")
        } else if showSunset && phase == .cruise {
            top = Color(hex: "2B3A67")
            bottom = Color(hex: "FF9E5E")
        } else {
            // Higher altitude = deeper blue.
            let deep = Color(hex: "1B63C4")
            let high = Color(hex: "0A2E6E")
            top = altitudeFraction > 0.6 ? high : deep
            bottom = Color(hex: altitudeFraction < 0.2 ? "AFCBE8" : "7FB2E8")
        }

        let gradient = Gradient(colors: [top, bottom])
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .linearGradient(gradient,
                                  startPoint: .zero,
                                  endPoint: CGPoint(x: 0, y: size.height))
        )
    }

    private func drawStars(context: GraphicsContext, size: CGSize, time: Double) {
        var rng = SeededRandom(seed: 77)
        for _ in 0..<46 {
            let x = rng.next() * size.width
            let y = rng.next() * size.height * 0.7
            let radius = 0.6 + rng.next() * 1.2
            let twinkle = 0.45 + 0.55 * abs(sin(time * (0.6 + rng.next()) + rng.next() * 6.28))
            let alpha = min(1, twinkle) * min(1, altitudeFraction + 0.25)
            context.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
                with: .color(.white.opacity(alpha))
            )
        }
    }

    private func drawAurora(context: GraphicsContext, size: CGSize, time: Double) {
        for band in 0..<3 {
            var path = Path()
            let baseY = size.height * (0.18 + Double(band) * 0.09)
            path.move(to: CGPoint(x: 0, y: baseY))
            let step = size.width / 24
            for i in 0...24 {
                let x = Double(i) * step
                let y = baseY + sin(x / 46 + time * 0.35 + Double(band) * 1.7) * 16
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.addLine(to: CGPoint(x: size.width, y: baseY + 110))
            path.addLine(to: CGPoint(x: 0, y: baseY + 110))
            path.closeSubpath()

            let colors: [Color] = [.green, .mint, .purple]
            context.fill(path, with: .linearGradient(
                Gradient(colors: [colors[band].opacity(0.28), .clear]),
                startPoint: CGPoint(x: 0, y: baseY),
                endPoint: CGPoint(x: 0, y: baseY + 110)
            ))
        }
    }

    // MARK: Clouds

    private func drawClouds(context: GraphicsContext, size: CGSize, time: Double) {
        // Three parallax layers; nearer layers are bigger, faster, more opaque.
        for layer in 0..<3 {
            let layerScale = 1.0 + Double(layer) * 0.8
            let drift = time * (6 + Double(layer) * 7)      // horizontal cruise drift
            let vertical = verticalCloudOffset(time: time, layer: layer)
            let opacity = cloudOpacity(layer: layer)
            guard opacity > 0.01 else { continue }

            var rng = SeededRandom(seed: UInt64(101 + layer * 37))
            for _ in 0..<5 {
                let baseX = rng.next() * (size.width + 200) - 100
                let baseY = rng.next() * size.height * 1.6
                let width = (60 + rng.next() * 110) * layerScale
                let height = width * 0.34

                let x = (baseX - drift).truncatingRemainder(dividingBy: size.width + 240)
                let wrappedX = x < -120 ? x + size.width + 240 : x
                let y = (baseY + vertical).truncatingRemainder(dividingBy: size.height * 1.6)
                let wrappedY = y < 0 ? y + size.height * 1.6 : y

                drawCloudBlob(context: context,
                              at: CGPoint(x: wrappedX, y: wrappedY - size.height * 0.3),
                              width: width, height: height,
                              opacity: opacity)
            }
        }
    }

    private func verticalCloudOffset(time: Double, layer: Int) -> Double {
        let speed = 40.0 + Double(layer) * 36
        switch phase {
        case .takeoffRoll: return 0
        case .climb: return time * speed          // we rise → clouds sink past us
        case .cruise: return 0
        case .descent, .landing: return -time * speed * 0.7
        }
    }

    private func cloudOpacity(layer: Int) -> Double {
        let base: Double
        switch phase {
        case .takeoffRoll: base = condition == .cloudy ? 0.25 : 0.0
        case .climb: base = 0.85
        case .cruise: base = condition == .cloudy ? 0.7 : 0.35
        case .descent: base = 0.75
        case .landing: base = condition == .cloudy ? 0.4 : 0.15
        }
        let layerFactor = 0.5 + Double(layer) * 0.25
        return base * layerFactor * (isNight ? 0.4 : 1.0)
    }

    private func drawCloudBlob(context: GraphicsContext, at center: CGPoint,
                               width: Double, height: Double, opacity: Double) {
        let color = isNight ? Color(hex: "3A4468") : .white
        var blob = context
        blob.addFilter(.blur(radius: height * 0.28))
        // Three overlapping ellipses read as one soft cloud.
        let rects = [
            CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height),
            CGRect(x: center.x - width * 0.30, y: center.y - height * 0.95, width: width * 0.6, height: height),
            CGRect(x: center.x - width * 0.05, y: center.y - height * 0.6, width: width * 0.5, height: height * 0.9),
        ]
        for rect in rects {
            blob.fill(Path(ellipseIn: rect), with: .color(color.opacity(opacity)))
        }
    }

    // MARK: Runway

    private func drawRunway(context: GraphicsContext, size: CGSize, time: Double) {
        let horizon = size.height * 0.62

        // Ground plane.
        let ground = Path(CGRect(x: 0, y: horizon, width: size.width, height: size.height - horizon))
        let groundColor = isNight ? Color(hex: "0A0D14") : Color(hex: "3E4A3E")
        context.fill(ground, with: .color(groundColor))

        // Edge lights rushing past with perspective.
        let scroll = (time * 2.2).truncatingRemainder(dividingBy: 1.0)
        for i in 0..<9 {
            let depth = (Double(i) / 9.0 + scroll).truncatingRemainder(dividingBy: 1.0)
            let y = horizon + pow(depth, 2.2) * (size.height - horizon)
            let spread = 18 + pow(depth, 2.0) * (size.width * 0.55)
            let radius = 1.0 + depth * 3.2
            let alpha = 0.25 + depth * 0.75
            let lightColor: Color = isNight ? Color(hex: "FFD97A") : .white
            for side in [-1.0, 1.0] {
                let x = size.width / 2 + side * spread
                context.fill(
                    Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                                           width: radius * 2, height: radius * 2)),
                    with: .color(lightColor.opacity(alpha))
                )
            }
            // Center-line stripe.
            let stripeWidth = 2.0 + depth * 5
            let stripeHeight = 4.0 + depth * 16
            context.fill(
                Path(CGRect(x: size.width / 2 - stripeWidth / 2, y: y - stripeHeight / 2,
                            width: stripeWidth, height: stripeHeight)),
                with: .color(.white.opacity(alpha * 0.6))
            )
        }
    }

    // MARK: Weather

    private func drawRain(context: GraphicsContext, size: CGSize, time: Double) {
        var rng = SeededRandom(seed: 913)
        for _ in 0..<34 {
            let laneX = rng.next() * size.width
            let speed = 260 + rng.next() * 220
            let length = 10 + rng.next() * 14
            let offset = rng.next() * size.height
            let y = (time * speed + offset).truncatingRemainder(dividingBy: size.height + length) - length
            var path = Path()
            path.move(to: CGPoint(x: laneX, y: y))
            path.addLine(to: CGPoint(x: laneX - 3, y: y + length))
            context.stroke(path, with: .color(.white.opacity(0.35)), lineWidth: 1.2)
        }
    }

    private func drawSnow(context: GraphicsContext, size: CGSize, time: Double) {
        var rng = SeededRandom(seed: 414)
        for _ in 0..<30 {
            let baseX = rng.next() * size.width
            let speed = 26 + rng.next() * 34
            let offset = rng.next() * size.height
            let y = (time * speed + offset).truncatingRemainder(dividingBy: size.height + 8) - 4
            let x = baseX + sin(time * 1.3 + offset) * 9
            let radius = 1.2 + rng.next() * 1.8
            context.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
                with: .color(.white.opacity(0.8))
            )
        }
    }
}

/// Tiny deterministic PRNG so scene elements are stable frame to frame.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 6364136223846793005 &+ 1442695040888963407
    }

    /// Uniform in 0..<1.
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 11) & 0xFFFFFFFF) / Double(UInt32.max)
    }
}
