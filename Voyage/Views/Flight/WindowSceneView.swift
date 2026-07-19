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

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: frameInterval, paused: isPaused)) { timeline in
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

    /// ~30fps for motion-heavy phases; ~13fps for cruise; ~18fps on descent.
    private var frameInterval: Double {
        switch phase {
        case .takeoffRoll, .landing, .climb: return 1.0 / 30.0
        case .cruise: return 1.0 / 13.0
        case .descent: return 1.0 / 18.0
        }
    }

    private var isPaused: Bool {
        scenePhase != .active || reduceMotion
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
        // Far → near: slower/smaller → faster/larger. Far layer alone gets soft blur.
        let layerCount = 4
        for layer in 0..<layerCount {
            let opacity = cloudOpacity(layer: layer, layerCount: layerCount)
            guard opacity > 0.01 else { continue }

            let layerT = Double(layer) / Double(layerCount - 1)
            let layerScale = 0.55 + layerT * 1.35
            let drift = time * (3.5 + Double(layer) * 5.5)
            let vertical = verticalCloudOffset(time: time, layer: layer)
            let cloudCount = cloudsPerLayer(layer: layer)

            var rng = SeededRandom(seed: UInt64(101 + layer * 37))
            for cloudIndex in 0..<cloudCount {
                let baseX = rng.next() * (size.width + 280) - 120
                let baseY = cloudBaseY(rng: &rng, size: size, layer: layer)
                let width = (70 + rng.next() * 130) * layerScale * cruiseScale
                let height = width * (0.28 + rng.next() * 0.14)

                let wrapW = size.width + 320
                let wrapH = size.height * 1.8
                let x = (baseX - drift).truncatingRemainder(dividingBy: wrapW)
                let wrappedX = x < -140 ? x + wrapW : x
                let y = (baseY + vertical).truncatingRemainder(dividingBy: wrapH)
                let wrappedY = y < 0 ? y + wrapH : y

                let seed = UInt64(cloudIndex * 91 + layer * 1301 + 17)
                drawCloudVolume(
                    context: context,
                    at: CGPoint(x: wrappedX, y: wrappedY - size.height * cloudVerticalBias),
                    width: width,
                    height: height,
                    opacity: opacity,
                    seed: seed,
                    blurFarLayer: layer == 0
                )
            }
        }
    }

    /// Cruise keeps undercast low and thin; climb fills the pane.
    private var cruiseScale: Double {
        switch phase {
        case .cruise: return condition == .cloudy ? 0.85 : 0.55
        case .descent: return 0.9
        default: return 1.0
        }
    }

    private var cloudVerticalBias: Double {
        switch phase {
        case .cruise: return 0.05   // thin deck sitting low / distant
        case .climb: return 0.35
        case .descent: return 0.25
        case .takeoffRoll, .landing: return 0.15
        }
    }

    private func cloudsPerLayer(layer: Int) -> Int {
        switch phase {
        case .takeoffRoll:
            return condition == .cloudy ? (layer == 0 ? 3 : 2) : 0
        case .landing:
            return condition == .cloudy ? 3 : (layer < 2 ? 2 : 1)
        case .cruise:
            return condition == .cloudy ? 4 : 3
        case .climb:
            return 5 + (layer == 1 || layer == 2 ? 1 : 0)
        case .descent:
            return 4
        }
    }

    private func cloudBaseY(rng: inout SeededRandom, size: CGSize, layer: Int) -> Double {
        switch phase {
        case .cruise:
            // Distant undercast clustered in the lower third.
            return size.height * (0.55 + rng.next() * 0.55) + Double(layer) * 20
        case .climb:
            return rng.next() * size.height * 1.7
        default:
            return rng.next() * size.height * 1.5
        }
    }

    private func verticalCloudOffset(time: Double, layer: Int) -> Double {
        let speed = 32.0 + Double(layer) * 28
        switch phase {
        case .takeoffRoll: return 0
        case .climb: return time * speed
        case .cruise: return sin(time * 0.08 + Double(layer)) * 4
        case .descent, .landing: return -time * speed * 0.65
        }
    }

    private func cloudOpacity(layer: Int, layerCount: Int) -> Double {
        let base: Double
        switch phase {
        case .takeoffRoll: base = condition == .cloudy ? 0.22 : 0.0
        case .climb: base = 0.78
        case .cruise: base = condition == .cloudy ? 0.45 : 0.22
        case .descent: base = 0.62
        case .landing: base = condition == .cloudy ? 0.32 : 0.12
        }
        let layerT = Double(layer) / Double(max(layerCount - 1, 1))
        let layerFactor = 0.4 + layerT * 0.55
        let nightFactor = isNight ? 0.55 : 1.0
        return base * layerFactor * nightFactor
    }

    /// Soft multi-lobe volume: overlapping fills; blur only on the farthest layer.
    private func drawCloudVolume(
        context: GraphicsContext,
        at center: CGPoint,
        width: Double,
        height: Double,
        opacity: Double,
        seed: UInt64,
        blurFarLayer: Bool
    ) {
        var rng = SeededRandom(seed: seed)
        let lobeCount = 5 + Int(rng.next() * 3.99) // 5…8

        let fillColor: Color
        let highlight: Color
        if isNight {
            fillColor = Color(hex: "2A3558")
            highlight = Color(hex: "4A5A82")
        } else if showSunset && phase == .cruise {
            fillColor = Color(hex: "FFE4D0")
            highlight = Color(hex: "FFF6EE")
        } else {
            fillColor = Color(hex: "F4F7FC")
            highlight = .white
        }

        var layerContext = context
        if blurFarLayer {
            layerContext.addFilter(.blur(radius: max(1.5, height * 0.12)))
        }

        for lobe in 0..<lobeCount {
            let ox = (rng.next() - 0.5) * width * 0.72
            let oy = (rng.next() - 0.45) * height * 0.55
            let w = width * (0.32 + rng.next() * 0.48)
            let h = height * (0.5 + rng.next() * 0.55)
            let rect = CGRect(
                x: center.x + ox - w / 2,
                y: center.y + oy - h / 2,
                width: w,
                height: h
            )
            let isHighlight = lobe % 3 == 0
            let color = isHighlight ? highlight : fillColor
            let lobeAlpha = opacity * (isHighlight ? 0.55 : 0.72)
            layerContext.fill(Path(ellipseIn: rect), with: .color(color.opacity(lobeAlpha)))
        }
    }

    // MARK: Runway

    private func drawRunway(context: GraphicsContext, size: CGSize, time: Double) {
        let horizon = size.height * 0.58
        let groundHeight = size.height - horizon
        let cx = size.width / 2
        let scroll = reduceMotion ? 0 : (time * runwayScrollSpeed).truncatingRemainder(dividingBy: 1.0)

        drawGroundPlane(context: context, size: size, horizon: horizon)

        // Asphalt trapezoid vanishing to a point on the horizon.
        let nearHalf = size.width * 0.46
        let farHalf = size.width * 0.028
        var asphalt = Path()
        asphalt.move(to: CGPoint(x: cx - nearHalf, y: size.height))
        asphalt.addLine(to: CGPoint(x: cx - farHalf, y: horizon))
        asphalt.addLine(to: CGPoint(x: cx + farHalf, y: horizon))
        asphalt.addLine(to: CGPoint(x: cx + nearHalf, y: size.height))
        asphalt.closeSubpath()

        let asphaltTop = isNight ? Color(hex: "1A1D24") : Color(hex: "3A3F48")
        let asphaltBottom = isNight ? Color(hex: "0C0E14") : Color(hex: "2A2E36")
        context.fill(asphalt, with: .linearGradient(
            Gradient(colors: [asphaltTop, asphaltBottom]),
            startPoint: CGPoint(x: cx, y: horizon),
            endPoint: CGPoint(x: cx, y: size.height)
        ))

        // Soft shoulder / edge fade into ground.
        drawRunwayShoulders(context: context, size: size, horizon: horizon, cx: cx,
                            nearHalf: nearHalf, farHalf: farHalf)

        // Painted edge lines.
        drawPerspectiveEdgeLines(context: context, size: size, horizon: horizon, cx: cx,
                                 nearHalf: nearHalf * 0.92, farHalf: farHalf * 0.85)

        // Approach / threshold bars near the vanishing point.
        drawThresholdBars(context: context, size: size, horizon: horizon, cx: cx,
                          nearHalf: nearHalf, farHalf: farHalf)

        // Foreshortened centerline dashes + edge lights scrolling with speed.
        let sampleCount = 22
        for i in 0..<sampleCount {
            let raw = (Double(i) / Double(sampleCount) + scroll).truncatingRemainder(dividingBy: 1.0)
            let depth = max(0.002, raw) // 0 = horizon, 1 = near
            let y = horizon + pow(depth, 2.05) * groundHeight
            let halfW = farHalf + (nearHalf - farHalf) * pow(depth, 1.12)
            let alpha = 0.2 + depth * 0.8

            // Centerline dash — length/width scale with depth.
            let dashW = 1.4 + depth * 5.5
            let dashH = 3.0 + depth * 22
            let gapFactor = abs(sin(Double(i) * 1.7 + scroll * .pi))
            if gapFactor > 0.22 {
                context.fill(
                    Path(CGRect(x: cx - dashW / 2, y: y - dashH / 2, width: dashW, height: dashH)),
                    with: .color(Color.white.opacity(alpha * 0.85))
                )
            }

            // Edge lights: warm bloom + bright core.
            let coreR = 0.9 + depth * 3.4
            let bloomR = coreR * (isNight ? 3.2 : 2.2)
            let lightAlpha = (isNight ? 0.35 : 0.22) + depth * (isNight ? 0.65 : 0.45)
            let warm = Color(hex: isNight ? "FFD27A" : "FFE8A8")
            for side in [-1.0, 1.0] {
                let x = cx + side * halfW * 0.98
                // Bloom
                context.fill(
                    Path(ellipseIn: CGRect(x: x - bloomR, y: y - bloomR * 0.7,
                                           width: bloomR * 2, height: bloomR * 1.4)),
                    with: .color(warm.opacity(lightAlpha * 0.28))
                )
                // Core
                context.fill(
                    Path(ellipseIn: CGRect(x: x - coreR, y: y - coreR,
                                           width: coreR * 2, height: coreR * 2)),
                    with: .color(warm.opacity(min(1, lightAlpha + 0.15)))
                )
            }
        }
    }

    private var runwayScrollSpeed: Double {
        phase == .takeoffRoll ? 2.6 : 2.1
    }

    private func drawGroundPlane(context: GraphicsContext, size: CGSize, horizon: Double) {
        let groundRect = CGRect(x: 0, y: horizon, width: size.width, height: size.height - horizon)
        if isNight {
            context.fill(Path(groundRect), with: .linearGradient(
                Gradient(colors: [
                    Color(hex: "0A1018"),
                    Color(hex: "06080E"),
                    Color(hex: "04050A")
                ]),
                startPoint: CGPoint(x: 0, y: horizon),
                endPoint: CGPoint(x: 0, y: size.height)
            ))
            // Sparse distant field / taxiway glints.
            var rng = SeededRandom(seed: 501)
            for _ in 0..<18 {
                let x = rng.next() * size.width
                let d = 0.15 + rng.next() * 0.85
                let y = horizon + pow(d, 2.1) * (size.height - horizon)
                let r = 0.4 + d * 1.2
                // Keep glints off the runway corridor.
                let offCenter = abs(x - size.width / 2) / size.width
                guard offCenter > 0.22 else { continue }
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                    with: .color(Color(hex: "C9D4E8").opacity(0.12 + d * 0.2))
                )
            }
        } else {
            context.fill(Path(groundRect), with: .linearGradient(
                Gradient(colors: [
                    Color(hex: "5A6B52"),  // muted near-horizon scrub
                    Color(hex: "4A5A44"),
                    Color(hex: "3D4A38")   // darker near camera — not lime
                ]),
                startPoint: CGPoint(x: 0, y: horizon),
                endPoint: CGPoint(x: 0, y: size.height)
            ))
            // Subtle field patches for texture (no cards / no noise bitmap).
            var rng = SeededRandom(seed: 502)
            for _ in 0..<10 {
                let x = rng.next() * size.width
                let d = rng.next()
                let y = horizon + pow(d, 1.8) * (size.height - horizon)
                let w = 28 + rng.next() * 70
                let h = 8 + rng.next() * 18
                let offCenter = abs(x - size.width / 2) / size.width
                guard offCenter > 0.2 else { continue }
                context.fill(
                    Path(ellipseIn: CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h)),
                    with: .color(Color(hex: "465440").opacity(0.35))
                )
            }
        }

        // Haze band just under the horizon.
        let hazeH = size.height * 0.06
        context.fill(
            Path(CGRect(x: 0, y: horizon, width: size.width, height: hazeH)),
            with: .linearGradient(
                Gradient(colors: [
                    (isNight ? Color(hex: "1A2238") : Color(hex: "9BB5C9")).opacity(0.35),
                    .clear
                ]),
                startPoint: CGPoint(x: 0, y: horizon),
                endPoint: CGPoint(x: 0, y: horizon + hazeH)
            )
        )
    }

    private func drawRunwayShoulders(
        context: GraphicsContext,
        size: CGSize,
        horizon: Double,
        cx: Double,
        nearHalf: Double,
        farHalf: Double
    ) {
        let shoulder = isNight ? Color(hex: "141820") : Color(hex: "4A5348")
        for side in [-1.0, 1.0] {
            var path = Path()
            let nearOuter = nearHalf * 1.12
            let farOuter = farHalf * 1.8
            path.move(to: CGPoint(x: cx + side * nearHalf, y: size.height))
            path.addLine(to: CGPoint(x: cx + side * farHalf, y: horizon))
            path.addLine(to: CGPoint(x: cx + side * farOuter, y: horizon))
            path.addLine(to: CGPoint(x: cx + side * nearOuter, y: size.height))
            path.closeSubpath()
            context.fill(path, with: .color(shoulder.opacity(isNight ? 0.55 : 0.4)))
        }
    }

    private func drawPerspectiveEdgeLines(
        context: GraphicsContext,
        size: CGSize,
        horizon: Double,
        cx: Double,
        nearHalf: Double,
        farHalf: Double
    ) {
        let lineColor = Color.white.opacity(isNight ? 0.55 : 0.7)
        for side in [-1.0, 1.0] {
            var path = Path()
            path.move(to: CGPoint(x: cx + side * nearHalf, y: size.height))
            path.addLine(to: CGPoint(x: cx + side * farHalf, y: horizon))
            context.stroke(path, with: .color(lineColor), lineWidth: 1.6)
        }
    }

    private func drawThresholdBars(
        context: GraphicsContext,
        size: CGSize,
        horizon: Double,
        cx: Double,
        nearHalf: Double,
        farHalf: Double
    ) {
        // A few white bars just below the vanishing point (approach markings).
        for bar in 0..<4 {
            let depth = 0.04 + Double(bar) * 0.028
            let y = horizon + pow(depth, 2.05) * (size.height - horizon)
            let halfW = farHalf + (nearHalf - farHalf) * pow(depth, 1.12)
            let barHalf = halfW * 0.55
            let thickness = 1.2 + depth * 4
            context.fill(
                Path(CGRect(x: cx - barHalf, y: y - thickness / 2,
                            width: barHalf * 2, height: thickness)),
                with: .color(.white.opacity(0.35 + Double(bar) * 0.08))
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
