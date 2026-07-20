import SwiftUI

/// Everything visible through a **side-facing** airplane window, drawn
/// procedurally: the airport rushing past on the takeoff roll, punching
/// through the cloud deck on climb, an undercast far below at cruise
/// (with the wing, if you're seated over it), real-weather skies, and
/// runway lights streaking past at touchdown.
struct WindowSceneView: View {
    let phase: LegPhase
    /// 0 = on the ground, 1 = cruise altitude.
    let altitudeFraction: Double
    let isNight: Bool
    let condition: SkyCondition
    let showSunset: Bool
    let showAurora: Bool
    var showWing: Bool = false

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Wall-clock moment the current phase began — gives every frame a
    /// smooth, continuous per-phase elapsed time for kinematics.
    @State private var phaseStart = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: frameInterval, paused: isPaused)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let tPhase = max(0, timeline.date.timeIntervalSince(phaseStart))
                let scene = SceneModel(
                    phase: phase,
                    altitude: altitudeFraction,
                    isNight: isNight,
                    condition: condition,
                    golden: goldenHour,
                    time: t,
                    tPhase: reduceMotion ? 0.35 : tPhase,
                    size: size
                )

                drawSky(context, scene)
                drawSunOrMoon(context, scene)
                if isNight { drawStars(context, scene) }
                if showAurora && isNight && phase == .cruise { drawAurora(context, scene) }
                drawCirrus(context, scene)

                if scene.onGround {
                    // Landing: the airport rises into view over the first
                    // moments of the flare instead of popping in.
                    let appear = phase == .landing ? min(1.0, scene.tPhase / 1.6) : 1.0
                    // Runway rumble: the ground judders more the faster we roll.
                    let speedT = reduceMotion ? 0 : min(1.0, scene.groundScroll / (920 * max(1, scene.tPhase)))
                    let shake = sin(scene.time * 31) * 1.4 * speedT
                        + sin(scene.time * 53 + 1.3) * 0.7 * speedT
                    if appear >= 1 {
                        var ctx = context
                        ctx.translateBy(x: 0, y: shake)
                        drawAirportGround(ctx, scene)
                    } else {
                        var ctx = context
                        ctx.opacity = appear
                        ctx.translateBy(x: 0, y: scene.size.height * (1 - appear) * 0.35 + shake)
                        drawAirportGround(ctx, scene)
                    }
                } else if phase == .climb {
                    // Rotation: the airport sinks away below and fades out
                    // rather than cutting straight to sky.
                    let recedeSpan = FlightSession.shortFlightsEnabled ? 2.0 : 6.0
                    let recede = min(1.0, scene.tPhase / recedeSpan)
                    if recede < 1 {
                        var ctx = context
                        ctx.opacity = (1 - recede) * (1 - recede)
                        ctx.translateBy(x: 0, y: scene.size.height * recede * 0.9)
                        drawAirportGround(ctx, scene)
                    }
                } else if phase == .cruise || phase == .descent {
                    drawFarTerrain(context, scene)
                }

                drawClouds(context, scene)

                if scene.showsPrecipitation {
                    if condition == .snow { drawSnow(context, scene) }
                    else { drawRain(context, scene) }
                }
                if condition == .storm && scene.showsPrecipitation {
                    drawLightning(context, scene)
                }
                if condition == .fog && scene.onGround {
                    drawFogBank(context, scene)
                }

                if showWing && !scene.onGround {
                    drawWing(context, scene)
                }
            }
            .overlay { hazeOverlay(time: timeline.date.timeIntervalSinceReferenceDate) }
        }
        .onChange(of: phase) { _, _ in phaseStart = Date() }
        .onAppear { phaseStart = Date() }
    }

    // MARK: Frame pacing

    private var frameInterval: Double {
        switch phase {
        case .takeoffRoll, .landing, .climb: return 1.0 / 30.0
        case .cruise: return 1.0 / 14.0
        case .descent: return 1.0 / 20.0
        }
    }

    private var isPaused: Bool { scenePhase != .active }

    private var goldenHour: Bool {
        if showSunset && phase == .cruise { return true }
        guard !isNight else { return false }
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 17 && hour < 20 || hour >= 5 && hour < 8
    }

    // MARK: Scene model

    /// Precomputed per-frame values shared by the draw passes.
    private struct SceneModel {
        let phase: LegPhase
        let altitude: Double
        let isNight: Bool
        let condition: SkyCondition
        let golden: Bool
        let time: Double
        let tPhase: Double
        let size: CGSize

        var onGround: Bool { phase == .takeoffRoll || phase == .landing }

        /// Where the ground meets the sky, as a height fraction.
        var horizonY: Double {
            if onGround { return 0.60 }
            // Higher altitude pushes the horizon toward the upper third.
            return 0.60 - 0.18 * min(1, altitude)
        }

        var showsPrecipitation: Bool {
            guard condition.isPrecipitating else { return false }
            switch phase {
            case .takeoffRoll, .landing: return true
            case .climb: return altitude < 0.35
            case .descent: return altitude < 0.5
            case .cruise: return false // above the weather
            }
        }

        /// Horizontal scroll distance of the nearest ground layer, in px.
        /// Takeoff accelerates, landing decelerates — real kinematics so the
        /// streaking speed feels physical.
        var groundScroll: Double {
            let vMax = 920.0
            switch phase {
            case .takeoffRoll:
                let roll = max(0.5, FlightSession.takeoffRollDuration)
                let t = tPhase
                if t < roll { return vMax * t * t / (2 * roll) }
                return vMax * roll / 2 + vMax * (t - roll)
            case .climb:
                // Continue from where the takeoff roll left off so the
                // receding runway doesn't jump at rotation.
                let roll = max(0.5, FlightSession.takeoffRollDuration)
                return vMax * roll / 2 + vMax * tPhase
            case .landing:
                let t = tPhase
                let brake = max(0.5, FlightSession.landingDuration * 0.85)
                let v = max(130.0, vMax - (vMax - 130.0) * min(1, t / brake))
                // Integrate the linear deceleration.
                let tc = min(t, brake)
                var d = vMax * tc - (vMax - 130.0) * tc * tc / (2 * brake)
                if t > brake { d += 130.0 * (t - brake) }
                return d
            default:
                return vMax * tPhase
            }
        }
    }

    // MARK: Sky

    private struct SkyPalette {
        let top: Color
        let bottom: Color
    }

    private func skyPalette(_ s: SceneModel) -> SkyPalette {
        let overcast = s.condition.cloudAmount > 0.7 && (s.onGround || s.phase != .cruise)
        if s.isNight {
            return overcast
                ? SkyPalette(top: Color(hex: "0A0D18"), bottom: Color(hex: "202638"))
                : SkyPalette(top: Color(hex: "04060F"),
                             bottom: s.altitude > 0.5 ? Color(hex: "111A38") : Color(hex: "1A2340"))
        }
        if s.golden {
            return overcast
                ? SkyPalette(top: Color(hex: "4A4458"), bottom: Color(hex: "B57E62"))
                : SkyPalette(top: Color(hex: "35406F"), bottom: Color(hex: "FF9E5E"))
        }
        if overcast {
            return SkyPalette(top: Color(hex: "6A7688"), bottom: Color(hex: "9AA6B5"))
        }
        // Clear day: deeper blue with altitude.
        let top = s.altitude > 0.6 ? Color(hex: "082B66") : Color(hex: "1B63C4")
        let bottom = s.altitude < 0.2 ? Color(hex: "AFCBE8") : Color(hex: "7FB2E8")
        return SkyPalette(top: top, bottom: bottom)
    }

    private func drawSky(_ context: GraphicsContext, _ s: SceneModel) {
        let palette = skyPalette(s)
        context.fill(
            Path(CGRect(origin: .zero, size: s.size)),
            with: .linearGradient(
                Gradient(colors: [palette.top, palette.bottom]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: s.size.height * max(0.65, s.horizonY + 0.25))
            )
        )
    }

    private func drawSunOrMoon(_ context: GraphicsContext, _ s: SceneModel) {
        // Heavy overcast hides the disc.
        guard s.condition.cloudAmount < 0.85 else { return }
        let w = s.size.width, h = s.size.height

        if s.isNight {
            let center = CGPoint(x: w * 0.72, y: h * 0.16)
            let r: CGFloat = 16
            context.fill(Path(ellipseIn: CGRect(x: center.x - r * 2.4, y: center.y - r * 2.4,
                                                width: r * 4.8, height: r * 4.8)),
                         with: .color(.white.opacity(0.05)))
            context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r,
                                                width: r * 2, height: r * 2)),
                         with: .color(Color(hex: "E8ECF5").opacity(0.9)))
            // Crescent shadow bite.
            context.fill(Path(ellipseIn: CGRect(x: center.x - r + 7, y: center.y - r - 2,
                                                width: r * 2, height: r * 2)),
                         with: .color(Color(hex: "04060F").opacity(0.85)))
        } else {
            let center = s.golden
                ? CGPoint(x: w * 0.62, y: h * (s.horizonY - 0.10))
                : CGPoint(x: w * 0.74, y: h * 0.15)
            let r: CGFloat = s.golden ? 26 : 18
            let core = s.golden ? Color(hex: "FFD98A") : Color(hex: "FFF4D6")
            for (mult, alpha) in [(4.2, 0.10), (2.4, 0.16), (1.0, 0.95)] {
                let rr = r * mult
                context.fill(Path(ellipseIn: CGRect(x: center.x - rr, y: center.y - rr,
                                                    width: rr * 2, height: rr * 2)),
                             with: .color(core.opacity(alpha)))
            }
        }
    }

    private func drawStars(_ context: GraphicsContext, _ s: SceneModel) {
        var rng = SeededRandom(seed: 77)
        let ceiling = s.size.height * max(0.3, s.horizonY - 0.05)
        for _ in 0..<44 {
            let x = rng.next() * s.size.width
            let y = rng.next() * ceiling
            let radius = 0.6 + rng.next() * 1.1
            let twinkle = 0.45 + 0.55 * abs(sin(s.time * (0.6 + rng.next()) + rng.next() * 6.28))
            let alpha = min(1, twinkle) * min(1, s.altitude + 0.3)
            context.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
                with: .color(.white.opacity(alpha))
            )
        }
    }

    private func drawAurora(_ context: GraphicsContext, _ s: SceneModel) {
        for band in 0..<3 {
            var path = Path()
            let baseY = s.size.height * (0.14 + Double(band) * 0.08)
            path.move(to: CGPoint(x: 0, y: baseY))
            let step = s.size.width / 24
            for i in 0...24 {
                let x = Double(i) * step
                let y = baseY + sin(x / 46 + s.time * 0.35 + Double(band) * 1.7) * 16
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.addLine(to: CGPoint(x: s.size.width, y: baseY + 110))
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

    /// Thin high ice streaks drifting slowly aft — sells forward motion at cruise.
    private func drawCirrus(_ context: GraphicsContext, _ s: SceneModel) {
        guard s.phase == .cruise || s.phase == .descent else { return }
        var rng = SeededRandom(seed: 314)
        let color = s.isNight ? Color(hex: "56618A") : .white
        for i in 0..<3 {
            let baseY = s.size.height * (0.10 + rng.next() * 0.22)
            let length = s.size.width * (0.3 + rng.next() * 0.4)
            let speed = 9.0 + Double(i) * 5
            let wrap = s.size.width + length
            var x = (rng.next() * wrap - s.time * speed).truncatingRemainder(dividingBy: wrap)
            if x < -length { x += wrap }
            let rect = CGRect(x: x, y: baseY, width: length, height: 2.2 + rng.next() * 2)
            var ctx = context
            ctx.addFilter(.blur(radius: 2.5))
            ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color.opacity(0.22)))
        }
    }

    // MARK: Airport ground (takeoff roll / landing)

    private func drawAirportGround(_ context: GraphicsContext, _ s: SceneModel) {
        let w = s.size.width, h = s.size.height
        let horizon = h * s.horizonY

        // Ground plane.
        let groundColors: [Color] = s.isNight
            ? [Color(hex: "0A1018"), Color(hex: "06080E")]
            : [Color(hex: "58684F"), Color(hex: "3D4A38")]
        context.fill(Path(CGRect(x: 0, y: horizon, width: w, height: h - horizon)),
                     with: .linearGradient(Gradient(colors: groundColors),
                                           startPoint: CGPoint(x: 0, y: horizon),
                                           endPoint: CGPoint(x: 0, y: h)))

        // Far band: terminal, tower, tails — slow parallax.
        drawTerminalBand(context, s, horizon: horizon)

        // Mid band: taxiway signs + grass, medium parallax.
        drawMidfieldBand(context, s, horizon: horizon)

        // Near band: our runway/taxiway edge streaking at full speed.
        drawNearRunwayBand(context, s, horizon: horizon)

        // Haze line at the horizon.
        let hazeColor = s.isNight ? Color(hex: "1A2238") : Color(hex: "9BB5C9")
        context.fill(Path(CGRect(x: 0, y: horizon - 1, width: w, height: h * 0.05)),
                     with: .linearGradient(Gradient(colors: [hazeColor.opacity(0.4), .clear]),
                                           startPoint: CGPoint(x: 0, y: horizon),
                                           endPoint: CGPoint(x: 0, y: horizon + h * 0.05)))
    }

    private func drawTerminalBand(_ context: GraphicsContext, _ s: SceneModel, horizon: Double) {
        let w = s.size.width
        let scroll = s.groundScroll * 0.22
        let wrap = w * 2.4
        var rng = SeededRandom(seed: 42)
        let bodyColor = s.isNight ? Color(hex: "141A26") : Color(hex: "8B95A3")
        let glassColor = s.isNight ? Color(hex: "F5C36B").opacity(0.5) : Color(hex: "C7D3E0")

        for i in 0..<7 {
            let baseX = rng.next() * wrap
            var x = (baseX - scroll).truncatingRemainder(dividingBy: wrap)
            if x < -260 { x += wrap }
            let width = 120.0 + rng.next() * 160
            let height = 16.0 + rng.next() * 22
            let y = horizon - height

            // Terminal block.
            context.fill(Path(CGRect(x: x, y: y, width: width, height: height)),
                         with: .color(bodyColor))
            // Window strip.
            context.fill(Path(CGRect(x: x + 4, y: y + height * 0.3, width: width - 8, height: 4)),
                         with: .color(glassColor))
            // Control tower on one block.
            if i == 3 {
                let towerX = x + width * 0.5
                context.fill(Path(CGRect(x: towerX - 3, y: y - 34, width: 6, height: 34)),
                             with: .color(bodyColor))
                context.fill(Path(ellipseIn: CGRect(x: towerX - 9, y: y - 44, width: 18, height: 13)),
                             with: .color(bodyColor))
                if s.isNight {
                    let blink = sin(s.time * 2.2) > 0
                    context.fill(Path(ellipseIn: CGRect(x: towerX - 2, y: y - 49, width: 4, height: 4)),
                                 with: .color(blink ? .red : .red.opacity(0.25)))
                }
            }
            // Parked tail fin between blocks.
            if i % 2 == 0 {
                let finX = x + width + 26
                var fin = Path()
                fin.move(to: CGPoint(x: finX, y: horizon))
                fin.addLine(to: CGPoint(x: finX + 6, y: horizon - 18))
                fin.addLine(to: CGPoint(x: finX + 14, y: horizon - 18))
                fin.addLine(to: CGPoint(x: finX + 12, y: horizon))
                fin.closeSubpath()
                context.fill(fin, with: .color(s.isNight ? Color(hex: "222B3C") : .white.opacity(0.85)))
            }
        }
    }

    private func drawMidfieldBand(_ context: GraphicsContext, _ s: SceneModel, horizon: Double) {
        let w = s.size.width, h = s.size.height
        let bandTop = horizon + (h - horizon) * 0.18
        let scroll = s.groundScroll * 0.5
        let wrap = w * 1.8
        var rng = SeededRandom(seed: 88)

        for _ in 0..<6 {
            let baseX = rng.next() * wrap
            var x = (baseX - scroll).truncatingRemainder(dividingBy: wrap)
            if x < -40 { x += wrap }
            let y = bandTop + rng.next() * (h - bandTop) * 0.3

            if s.isNight {
                // Blue taxiway edge lights.
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 5, height: 5)),
                             with: .color(Color(hex: "4F8BFF").opacity(0.85)))
                context.fill(Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 11, height: 11)),
                             with: .color(Color(hex: "4F8BFF").opacity(0.2)))
            } else {
                // Yellow taxiway signage.
                context.fill(Path(roundedRect: CGRect(x: x, y: y, width: 16, height: 9), cornerRadius: 2),
                             with: .color(Color(hex: "E8C33A").opacity(0.9)))
            }
        }
    }

    private func drawNearRunwayBand(_ context: GraphicsContext, _ s: SceneModel, horizon: Double) {
        let w = s.size.width, h = s.size.height
        let bandTop = h - (h - horizon) * 0.42

        // Asphalt.
        let asphalt: [Color] = s.isNight
            ? [Color(hex: "191D26"), Color(hex: "0D1017")]
            : [Color(hex: "3F444E"), Color(hex: "2B2F38")]
        context.fill(Path(CGRect(x: 0, y: bandTop, width: w, height: h - bandTop)),
                     with: .linearGradient(Gradient(colors: asphalt),
                                           startPoint: CGPoint(x: 0, y: bandTop),
                                           endPoint: CGPoint(x: 0, y: h)))

        // Painted edge line along the top of the asphalt.
        context.fill(Path(CGRect(x: 0, y: bandTop, width: w, height: 2.5)),
                     with: .color(.white.opacity(s.isNight ? 0.5 : 0.75)))

        let scroll = s.groundScroll
        // Speed stretches the light/dash streaks.
        let speed = min(1.0, s.groundScroll / max(1, s.tPhase * 920))
        let streak = 6.0 + speed * 46.0

        // Centerline dashes.
        let dashWrap = 160.0
        let dashY = bandTop + (h - bandTop) * 0.55
        var x = -(scroll.truncatingRemainder(dividingBy: dashWrap))
        while x < w {
            context.fill(Path(roundedRect: CGRect(x: x, y: dashY, width: 54 + streak * 0.4, height: 5),
                              cornerRadius: 2.5),
                         with: .color(.white.opacity(0.55)))
            x += dashWrap
        }

        // Runway edge lights streaking past.
        let lightWrap = 210.0
        let lightY = bandTop + 7.0
        let warm = Color(hex: s.isNight ? "FFD27A" : "FFE8A8")
        var lx = -(scroll.truncatingRemainder(dividingBy: lightWrap))
        while lx < w {
            let rect = CGRect(x: lx, y: lightY - 2.5, width: 5 + streak, height: 5)
            context.fill(Path(roundedRect: rect, cornerRadius: 2.5),
                         with: .color(warm.opacity(s.isNight ? 0.95 : 0.8)))
            if s.isNight {
                context.fill(Path(ellipseIn: rect.insetBy(dx: -6, dy: -6)),
                             with: .color(warm.opacity(0.18)))
            }
            lx += lightWrap
        }
    }

    // MARK: Terrain far below (cruise / descent)

    private func drawFarTerrain(_ context: GraphicsContext, _ s: SceneModel) {
        // Visible only through thinner decks.
        guard s.condition.cloudAmount < 0.75 else { return }
        let w = s.size.width, h = s.size.height
        let top = h * (s.horizonY + 0.03)
        let drift = s.time * 5.5

        if s.isNight {
            // City light clusters crawling below.
            var rng = SeededRandom(seed: 913)
            for _ in 0..<9 {
                let wrap = w * 1.9
                var x = (rng.next() * wrap - drift).truncatingRemainder(dividingBy: wrap)
                if x < -60 { x += wrap }
                let y = top + rng.next() * (h - top) * 0.85
                let clusterSize = 3 + Int(rng.next() * 8)
                var cluster = rng
                for _ in 0..<clusterSize {
                    let dx = (cluster.next() - 0.5) * 44
                    let dy = (cluster.next() - 0.5) * 16
                    let r = 0.7 + cluster.next() * 1.2
                    context.fill(Path(ellipseIn: CGRect(x: x + dx, y: y + dy, width: r * 2, height: r * 2)),
                                 with: .color(Color(hex: "FFCF8A").opacity(0.35 + cluster.next() * 0.4)))
                }
            }
        } else {
            // Patchwork fields and a winding river, desaturated by distance.
            let ground = Path(CGRect(x: 0, y: top, width: w, height: h - top))
            context.fill(ground, with: .linearGradient(
                Gradient(colors: [Color(hex: "8FA382").opacity(0.5), Color(hex: "6E8266").opacity(0.65)]),
                startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: h)))

            var rng = SeededRandom(seed: 555)
            for _ in 0..<10 {
                let wrap = w * 1.9
                var x = (rng.next() * wrap - drift).truncatingRemainder(dividingBy: wrap)
                if x < -90 { x += wrap }
                let y = top + rng.next() * (h - top) * 0.8
                let pw = 34 + rng.next() * 80
                let ph = 10 + rng.next() * 22
                let tone = [Color(hex: "A3B08A"), Color(hex: "7E9169"), Color(hex: "B5A878")][Int(rng.next() * 2.99)]
                context.fill(Path(roundedRect: CGRect(x: x, y: y, width: pw, height: ph), cornerRadius: 2),
                             with: .color(tone.opacity(0.4)))
            }

            var river = Path()
            let riverY = top + (h - top) * 0.45
            river.move(to: CGPoint(x: -20, y: riverY))
            for i in 0...16 {
                let x = Double(i) / 16 * (w + 40) - 20
                river.addLine(to: CGPoint(x: x, y: riverY + sin(x / 60 + drift / 90) * 12))
            }
            context.stroke(river, with: .color(Color(hex: "7FA8C9").opacity(0.5)), lineWidth: 3)
        }
    }

    // MARK: Clouds

    private func drawClouds(_ context: GraphicsContext, _ s: SceneModel) {
        let layerCount = 4
        for layer in 0..<layerCount {
            let opacity = cloudOpacity(s, layer: layer, layerCount: layerCount)
            guard opacity > 0.01 else { continue }

            let layerT = Double(layer) / Double(layerCount - 1)
            let layerScale = 0.55 + layerT * 1.35
            // Side view: clouds drift aft (right → left); near layers faster.
            let drift = s.time * (6.0 + Double(layer) * 9.0) * driftFactor(s)
            let vertical = verticalCloudOffset(s, layer: layer)
            let count = cloudsPerLayer(s, layer: layer)

            var rng = SeededRandom(seed: UInt64(101 + layer * 37))
            for cloudIndex in 0..<count {
                let baseX = rng.next() * (s.size.width + 280) - 120
                let baseY = cloudBaseY(rng: &rng, s: s, layer: layer)
                let width = (70 + rng.next() * 130) * layerScale * cloudScale(s)
                let height = width * (0.28 + rng.next() * 0.14)

                let wrapW = s.size.width + 320
                let wrapH = s.size.height * 1.8
                let x = (baseX - drift).truncatingRemainder(dividingBy: wrapW)
                let wrappedX = x < -140 ? x + wrapW : x
                let y = (baseY + vertical).truncatingRemainder(dividingBy: wrapH)
                let wrappedY = y < 0 ? y + wrapH : y

                drawCloudVolume(
                    context,
                    s: s,
                    at: CGPoint(x: wrappedX, y: wrappedY),
                    width: width,
                    height: height,
                    opacity: opacity,
                    seed: UInt64(cloudIndex * 91 + layer * 1301 + 17),
                    blurFarLayer: layer == 0
                )
            }
        }
    }

    private func driftFactor(_ s: SceneModel) -> Double {
        switch s.phase {
        case .takeoffRoll: return 0.4   // distant clouds barely move on the roll
        case .climb: return 1.6
        case .cruise: return 1.0
        case .descent: return 1.8
        case .landing: return 2.2
        }
    }

    private func cloudScale(_ s: SceneModel) -> Double {
        switch s.phase {
        case .cruise: return s.condition.cloudAmount > 0.7 ? 0.9 : 0.6
        case .descent: return 0.95
        default: return 1.0
        }
    }

    private func cloudsPerLayer(_ s: SceneModel, layer: Int) -> Int {
        let amount = s.condition.cloudAmount
        switch s.phase {
        case .takeoffRoll, .landing:
            return amount > 0.7 ? 3 : (amount > 0.3 ? 1 : 0)
        case .climb:
            return 5 + (layer == 1 || layer == 2 ? 1 : 0)
        case .cruise:
            return amount > 0.7 ? 5 : (amount > 0.3 ? 3 : 2)
        case .descent:
            return 4
        }
    }

    private func cloudBaseY(rng: inout SeededRandom, s: SceneModel, layer: Int) -> Double {
        let h = s.size.height
        switch s.phase {
        case .cruise:
            // Undercast deck: clustered below the high horizon.
            return h * (s.horizonY + 0.10 + rng.next() * 0.65) + Double(layer) * 14
        case .climb:
            return rng.next() * h * 1.7
        case .descent:
            return h * (0.25 + rng.next() * 1.1)
        case .takeoffRoll, .landing:
            // Sky only — keep clear of the airport ground band.
            return rng.next() * h * s.horizonY * 0.8
        }
    }

    private func verticalCloudOffset(_ s: SceneModel, layer: Int) -> Double {
        let speed = 32.0 + Double(layer) * 28
        switch s.phase {
        case .takeoffRoll: return 0
        case .climb: return s.time * speed          // deck sinks past the window
        case .cruise: return sin(s.time * 0.08 + Double(layer)) * 4
        case .descent, .landing: return -s.time * speed * 0.65
        }
    }

    private func cloudOpacity(_ s: SceneModel, layer: Int, layerCount: Int) -> Double {
        let amount = s.condition.cloudAmount
        let base: Double
        switch s.phase {
        case .takeoffRoll: base = amount > 0.7 ? 0.30 : amount * 0.25
        case .climb:
            // Deck eases in as the ground falls away, so rotation reads as
            // one continuous moment instead of a scene swap.
            base = 0.78 * min(1.0, 0.25 + s.tPhase / 2.5)
        case .cruise: base = 0.2 + amount * 0.35
        case .descent: base = 0.62
        case .landing: base = amount > 0.7 ? 0.35 : 0.15
        }
        let layerT = Double(layer) / Double(max(layerCount - 1, 1))
        let layerFactor = 0.4 + layerT * 0.55
        let nightFactor = s.isNight ? 0.55 : 1.0
        return base * layerFactor * nightFactor
    }

    private func drawCloudVolume(
        _ context: GraphicsContext,
        s: SceneModel,
        at center: CGPoint,
        width: Double,
        height: Double,
        opacity: Double,
        seed: UInt64,
        blurFarLayer: Bool
    ) {
        var rng = SeededRandom(seed: seed)
        let lobeCount = 5 + Int(rng.next() * 3.99)

        let fillColor: Color
        let highlight: Color
        if s.isNight {
            fillColor = Color(hex: "2A3558")
            highlight = Color(hex: "4A5A82")
        } else if s.golden {
            fillColor = Color(hex: "FFE4D0")
            highlight = Color(hex: "FFF6EE")
        } else if s.condition == .storm || s.condition == .rain {
            fillColor = Color(hex: "94A0B2")
            highlight = Color(hex: "C3CCD8")
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
            let rect = CGRect(x: center.x + ox - w / 2, y: center.y + oy - h / 2,
                              width: w, height: h)
            let isHighlight = lobe % 3 == 0
            let color = isHighlight ? highlight : fillColor
            let lobeAlpha = opacity * (isHighlight ? 0.55 : 0.72)
            layerContext.fill(Path(ellipseIn: rect), with: .color(color.opacity(lobeAlpha)))
        }
    }

    // MARK: Weather

    private func drawRain(_ context: GraphicsContext, _ s: SceneModel) {
        var rng = SeededRandom(seed: 913)
        // Airspeed slants the streaks aft.
        let speedT = s.onGround ? min(1, s.groundScroll / 2400) : 0.9
        let slant = 4.0 + speedT * 26.0
        let count = s.condition == .storm ? 46 : 32
        for _ in 0..<count {
            let laneX = rng.next() * (s.size.width + 60) - 30
            let speed = 300 + rng.next() * 240
            let length = 12 + rng.next() * 15
            let offset = rng.next() * s.size.height
            let y = (s.time * speed + offset).truncatingRemainder(dividingBy: s.size.height + length) - length
            var path = Path()
            path.move(to: CGPoint(x: laneX, y: y))
            path.addLine(to: CGPoint(x: laneX - slant, y: y + length))
            context.stroke(path, with: .color(.white.opacity(0.32)), lineWidth: 1.2)
        }
    }

    private func drawSnow(_ context: GraphicsContext, _ s: SceneModel) {
        var rng = SeededRandom(seed: 414)
        let speedT = s.onGround ? min(1, s.groundScroll / 2400) : 0.7
        for _ in 0..<30 {
            let baseX = rng.next() * s.size.width
            let speed = 26 + rng.next() * 34
            let offset = rng.next() * s.size.height
            let y = (s.time * speed + offset).truncatingRemainder(dividingBy: s.size.height + 8) - 4
            let x = baseX + sin(s.time * 1.3 + offset) * 9 - speedT * 30 * (y / s.size.height)
            let radius = 1.2 + rng.next() * 1.8
            context.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
                with: .color(.white.opacity(0.8))
            )
        }
    }

    private func drawLightning(_ context: GraphicsContext, _ s: SceneModel) {
        // A flash window a few times a minute, keyed off wall-clock time.
        let cycle = s.time.truncatingRemainder(dividingBy: 7.3)
        guard cycle < 0.16 else { return }
        let alpha = 0.30 * (1 - cycle / 0.16)
        context.fill(Path(CGRect(origin: .zero, size: s.size)),
                     with: .color(Color(hex: "E8EDFF").opacity(alpha)))
    }

    private func drawFogBank(_ context: GraphicsContext, _ s: SceneModel) {
        let h = s.size.height
        let top = h * (s.horizonY - 0.22)
        context.fill(Path(CGRect(x: 0, y: top, width: s.size.width, height: h - top)),
                     with: .linearGradient(
                        Gradient(colors: [.clear,
                                          Color(hex: s.isNight ? "39415A" : "D5DCE4").opacity(0.75),
                                          Color(hex: s.isNight ? "2A3048" : "C3CBD5").opacity(0.9)]),
                        startPoint: CGPoint(x: 0, y: top),
                        endPoint: CGPoint(x: 0, y: h)))
    }

    // MARK: Wing

    private func drawWing(_ context: GraphicsContext, _ s: SceneModel) {
        let w = s.size.width, h = s.size.height
        // Gentle flex; a touch more in weather.
        let turbulence = s.condition.isPrecipitating ? 3.4 : 1.6
        let flex = sin(s.time * 1.1) * turbulence

        let rootY = h * 0.98
        let tipX = w * 0.88
        let tipY = h * 0.66 + flex

        var wing = Path()
        wing.move(to: CGPoint(x: -4, y: rootY - h * 0.16))          // leading edge root
        wing.addQuadCurve(to: CGPoint(x: tipX, y: tipY),
                          control: CGPoint(x: w * 0.42, y: h * 0.70))
        wing.addLine(to: CGPoint(x: tipX, y: tipY + 7))              // tip chord
        wing.addQuadCurve(to: CGPoint(x: -4, y: h + 8),
                          control: CGPoint(x: w * 0.38, y: h * 0.95))
        wing.closeSubpath()

        let top: Color = s.isNight ? Color(hex: "10131C") : Color(hex: "9AA4B2")
        let bottom: Color = s.isNight ? Color(hex: "070910") : Color(hex: "5F6975")
        context.fill(wing, with: .linearGradient(
            Gradient(colors: [top, bottom]),
            startPoint: CGPoint(x: 0, y: tipY - 20),
            endPoint: CGPoint(x: 0, y: h)))

        // Leading-edge glint.
        var edge = Path()
        edge.move(to: CGPoint(x: -4, y: rootY - h * 0.16))
        edge.addQuadCurve(to: CGPoint(x: tipX, y: tipY),
                          control: CGPoint(x: w * 0.42, y: h * 0.70))
        context.stroke(edge, with: .color(.white.opacity(s.isNight ? 0.10 : 0.5)), lineWidth: 1.4)

        // Navigation light (green, starboard) + white strobe at the tip.
        let navOn = sin(s.time * 2.6) > -0.2
        let navAlpha = navOn ? 0.95 : 0.35
        context.fill(Path(ellipseIn: CGRect(x: tipX - 3, y: tipY - 2, width: 5, height: 5)),
                     with: .color(Color(hex: "3AE86B").opacity(navAlpha)))
        context.fill(Path(ellipseIn: CGRect(x: tipX - 9, y: tipY - 8, width: 17, height: 17)),
                     with: .color(Color(hex: "3AE86B").opacity(navAlpha * 0.2)))

        let strobePhase = s.time.truncatingRemainder(dividingBy: 1.4)
        if strobePhase < 0.06 || (strobePhase > 0.12 && strobePhase < 0.18) {
            context.fill(Path(ellipseIn: CGRect(x: tipX - 12, y: tipY - 12, width: 24, height: 24)),
                         with: .color(.white.opacity(0.75)))
        }
    }

    // MARK: Haze shader overlay

    @ViewBuilder
    private func hazeOverlay(time: Double) -> some View {
        let density: Double = {
            switch condition {
            case .fog: return phase == .cruise ? 0.10 : 0.42
            case .cloudy, .rain, .storm: return 0.16
            case .snow: return 0.20
            case .partlyCloudy: return 0.10
            case .clear: return 0.06
            }
        }()
        Rectangle()
            .fill(.white)
            .colorEffect(ShaderLibrary.atmosphericHaze(
                .float(Float(time.truncatingRemainder(dividingBy: 4096))),
                .float(Float(density)),
                .float(isNight ? 1 : 0)
            ))
            .allowsHitTesting(false)
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
