import SwiftUI

/// Everything visible through a side-facing airplane window, drawn rather than
/// streamed: real skies for the forecast condition (clear, cloud, rain, storm,
/// snow, fog), sun/moon, stars, aurora, and the wing. Authored airport worlds
/// handle supported departures; the procedural renderer covers everything else.
///
/// This is the "Illustrated" half of the window-mode choice — see
/// `WindowWorldMode`. It needs no network and never shows a half-loaded tile.
struct IllustratedWindowSceneView: View {
    let airport: Airport
    let phase: LegPhase
    /// 0 = on the ground, 1 = cruise altitude.
    let altitudeFraction: Double
    let isNight: Bool
    let condition: SkyCondition
    let showSunset: Bool
    let showAurora: Bool
    var showWing: Bool = false
    var isLeftSide: Bool = false
    var legElapsed: TimeInterval = 0
    var phaseElapsed: TimeInterval = 0
    var aircraft: AircraftProfile = .voyageClassic
    var weatherSnapshot: WeatherSnapshot?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let frame = AirportWorldSimulation(
            airport: airport,
            aircraft: aircraft,
            seat: isLeftSide ? "A1" : "C1",
            weather: weatherSnapshot
        ).frame(
            phase: phase,
            legElapsed: legElapsed,
            altitudeFeet: Int(max(0, altitudeFraction) * 36_000)
        )
        WindowWorldRenderer(
            frame: frame,
            phase: phase,
            isNight: isNight,
            condition: condition,
            reduceMotion: reduceMotion
        ) {
            ZStack {
                proceduralScene
                if realSceneryActive {
                    realSceneryLayer
                }
            }
        }
    }

    // MARK: Real scenery (satellite flyover)

    /// Illustrated mode never mounts streamed tiles — that path lives on
    /// `WindowSceneView`'s `.real` branch. Keeping this off avoids low-poly
    /// satellite bleeding through the drawn cloud deck during climb.
    private var realSceneryActive: Bool { false }

    /// Crossfade to the procedural renderer as the ground stops reading:
    /// fully real below ~15% of cruise altitude, fully procedural by ~30%.
    private var realSceneryOpacity: Double {
        let t = (altitudeFraction - 0.15) / 0.15
        return 1 - min(1, max(0, t))
    }

    private var realSceneryLayer: some View {
        RealWorldSceneView(
            airport: airport,
            phase: phase,
            altitudeFraction: altitudeFraction,
            isLeftSide: isLeftSide
        )
        .overlay {
            // Satellite tiles are daytime-only; retint them for the scene.
            if isNight {
                Color(hex: "0A1226").opacity(0.62).blendMode(.multiply)
            } else if condition == .cloudy {
                Color(hex: "AEB6C2").opacity(0.22)
            }
        }
        .saturation(isNight ? 0.45 : 1)
        .opacity(realSceneryOpacity)
        .allowsHitTesting(false)
    }

    // MARK: Procedural scene

    private var proceduralScene: some View {
            TimelineView(.animation(minimumInterval: frameInterval, paused: isPaused)) { timeline in
            Canvas { context, size in
                let t = legElapsed
                let tPhase = phaseElapsed
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

                let airportOpacity = scene.airportGroundOpacity
                if airportOpacity > 0.01 {
                    var ctx = context
                    if scene.onGround && phase == .landing {
                        // Glassy-smooth rollout: the runway rises into frame but
                        // never jitters — owners flagged the old shake as bumpy.
                        let appear = min(1.0, scene.tPhase / 1.6)
                        ctx.opacity = appear * airportOpacity
                        ctx.translateBy(x: 0, y: scene.size.height * (1 - appear) * 0.35)
                    } else if phase == .climb {
                        let recedeSpan = FlightSession.shortFlightsEnabled ? 2.5 : 8.0
                        let recede = min(1.0, scene.tPhase / recedeSpan)
                        ctx.opacity = airportOpacity
                        ctx.translateBy(x: 0, y: scene.size.height * recede * 0.9)
                    } else {
                        // Takeoff roll: the ground sits rock-steady, no shake.
                        ctx.opacity = airportOpacity
                    }
                    drawAirportGround(ctx, scene)
                }

                let terrainOpacity = scene.farTerrainOpacity
                if terrainOpacity > 0.01 {
                    var ctx = context
                    ctx.opacity = terrainOpacity
                    drawFarTerrain(ctx, scene)
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
            .rotationEffect(.degrees(bankAngle))
            .scaleEffect(1 + abs(bankAngle) * 0.014)
            .overlay { hazeOverlay(time: legElapsed) }
            }
    }

    /// Climb-out attitude: the nose pitches up, so the view tips so the seat
    /// side of the window rises — you feel the aircraft elevate rather than sit
    /// level. Eases back to level as we approach cruise altitude. The slight
    /// scale-up hides the window corners while rotated.
    private var bankAngle: Double {
        guard !reduceMotion, phase == .climb else { return 0 }
        let rise = min(1, phaseElapsed / 1.4)
        let levelOff = 1 - min(1, max(0, altitudeFraction) / 0.85)
        return 8.0 * rise * levelOff
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
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = airport.timeZone
        let hour = calendar.component(.hour, from: Date())
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

        /// Opacity for the airport ground layers (runway, terminal band).
        var airportGroundOpacity: Double {
            if onGround { return 1 }
            if phase == .climb {
                let recedeSpan = FlightSession.shortFlightsEnabled ? 2.5 : 8.0
                let recede = min(1.0, tPhase / recedeSpan)
                return max(0, (1 - recede) * (1 - recede))
            }
            if phase == .descent {
                // Terrain hands off to the airport during the last part of descent.
                let blend = min(1, max(0, (0.50 - altitude) / 0.22))
                return blend * blend
            }
            return 0
        }

        /// Opacity for the patchwork terrain visible from cruise altitude.
        var farTerrainOpacity: Double {
            switch phase {
            case .cruise: return 1
            case .descent:
                return min(1, max(0, (altitude - 0.18) / 0.28))
            case .climb:
                // Crossfade terrain in as the airport recedes.
                let recedeSpan = FlightSession.shortFlightsEnabled ? 2.5 : 8.0
                let recede = min(1.0, tPhase / recedeSpan)
                let altitudeBlend = min(1, max(0, (altitude - 0.12) / 0.25))
                return max(recede * 0.55, altitudeBlend)
            default:
                return 0
            }
        }

        /// Where the ground meets the sky, as a height fraction.
        var horizonY: Double {
            if onGround {
                // Ease between cruise-like horizon during landing approach and
                // the low runway sightline.
                if phase == .landing {
                    let settle = min(1, max(0, (0.42 - altitude) / 0.22))
                    let cruiseLevel = 0.60 - 0.18 * min(1, altitude)
                    return cruiseLevel + (0.60 - cruiseLevel) * settle
                }
                return 0.60
            }
            // Higher altitude pushes the horizon toward the upper third.
            let level = 0.60 - 0.18 * min(1, altitude)
            guard phase == .climb else { return level }
            // Hold a nose-up sightline (horizon low, sky filling the pane) for
            // the bulk of the climb, easing to the cruise horizon only near
            // top-of-climb. Keying the wash-out to altitude/0.55 (as before)
            // let the horizon rise through the frame for ~60% of the climb —
            // because climbAltitudeFraction front-loads altitude — which read
            // as a descent. Ease in only after 70% altitude instead.
            // Horizon sits low (ground tilting away below, sky filling most of
            // the pane) but stays *visible* so the climb tilt reads, then eases
            // up to the cruise horizon near top-of-climb.
            let noseUp = 0.80
            let ease = min(1, max(0, (altitude - 0.70) / 0.25))
            return noseUp + (level - noseUp) * ease * ease
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
        if s.phase == .climb {
            drawClimbCloudDeck(context, s)
            return
        }

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
            // Deck eases in as the ground falls away; keep opacity bounded so
            // overlapping lobes never stack past full white.
            let recedeSpan = FlightSession.shortFlightsEnabled ? 2.5 : 8.0
            let recede = min(1.0, s.tPhase / recedeSpan)
            let ramp = min(1.0, 0.22 + s.tPhase / (recedeSpan * 1.6))
            base = min(0.62, 0.28 + recede * 0.34) * ramp
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
        let lobeCount = 4 + Int(rng.next() * 2.99)

        let fillColor: Color
        if s.isNight {
            fillColor = Color(hex: "D8DFF0")
        } else if s.golden {
            fillColor = Color(hex: "FFF6EE")
        } else if s.condition == .storm || s.condition == .rain {
            fillColor = Color(hex: "E8EDF5")
        } else {
            fillColor = .white
        }

        var layerContext = context
        layerContext.addFilter(.blur(radius: max(2.0, height * (blurFarLayer ? 0.16 : 0.10))))

        for lobe in 0..<lobeCount {
            let ox = (rng.next() - 0.5) * width * 0.68
            let oy = (rng.next() - 0.45) * height * 0.5
            let w = width * (0.36 + rng.next() * 0.42)
            let h = height * (0.55 + rng.next() * 0.45)
            let rect = CGRect(x: center.x + ox - w / 2, y: center.y + oy - h / 2,
                              width: w, height: h)
            let lobeAlpha = opacity * (0.22 + rng.next() * 0.18)
            layerContext.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(
                    Gradient(colors: [fillColor.opacity(lobeAlpha), fillColor.opacity(0)]),
                    center: CGPoint(x: rect.midX, y: rect.midY - h * 0.08),
                    startRadius: 0,
                    endRadius: max(w, h) * 0.55
                )
            )
        }
    }

    /// Soft, continuous cloud deck for the climb phase — avoids the harsh
    /// stacked-ellipse artifacts that read as overlapping ovals in the pane.
    private func drawClimbCloudDeck(_ context: GraphicsContext, _ s: SceneModel) {
        let w = s.size.width
        let h = s.size.height
        let recedeSpan = FlightSession.shortFlightsEnabled ? 2.5 : 8.0
        let deckStrength = min(1.0, max(0, (s.tPhase - 0.35) / (recedeSpan * 0.55)))
        guard deckStrength > 0.02 else { return }

        let drift = s.time * 18 * driftFactor(s)
        let fillColor: Color = s.isNight ? Color(hex: "C8D0E4") : .white

        for band in 0..<5 {
            let bandT = Double(band) / 4
            let bandHeight = h * (0.16 + bandT * 0.10)
            let baseY = h * (0.18 + bandT * 0.42) + s.time * (24 + bandT * 18)
            let wrappedY = baseY.truncatingRemainder(dividingBy: h * 1.35)

            var bandPath = Path()
            bandPath.move(to: CGPoint(x: -40, y: wrappedY + bandHeight))
            for index in 0...14 {
                let x = (Double(index) / 14) * (w + 80) - 40
                let wave = sin((x + drift) / (58 + bandT * 22) + Double(band) * 1.7) * bandHeight * 0.34
                bandPath.addLine(to: CGPoint(x: x, y: wrappedY + wave))
            }
            bandPath.addLine(to: CGPoint(x: w + 40, y: wrappedY + bandHeight))
            bandPath.closeSubpath()

            let bandAlpha = deckStrength * (0.14 + bandT * 0.10) * (s.isNight ? 0.72 : 1.0)
            var bandContext = context
            bandContext.addFilter(.blur(radius: 6 + bandT * 4))
            bandContext.fill(
                bandPath,
                with: .linearGradient(
                    Gradient(colors: [fillColor.opacity(bandAlpha), fillColor.opacity(bandAlpha * 0.35)]),
                    startPoint: CGPoint(x: 0, y: wrappedY),
                    endPoint: CGPoint(x: 0, y: wrappedY + bandHeight)
                )
            )
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

    /// Over-wing view, drawn like the real thing: a broad foreshortened
    /// surface with a near-horizontal leading edge, flap-track fairings
    /// trailing off it, and an upturned winglet with the nav light.
    private func drawWing(_ context: GraphicsContext, _ s: SceneModel) {
        let w = s.size.width, h = s.size.height
        // Gentle flex; a touch more in weather.
        let turbulence = s.condition.isPrecipitating ? 3.0 : 1.4
        let flex = sin(s.time * 1.1) * turbulence

        // The root sits below the sill so the wing reads as bolted to a
        // fuselage just out of frame, and the sweep is shallow — a steep
        // diagonal makes the wing look like a blade laid across the view.
        let rootLead = CGPoint(x: -10, y: h * 0.86)
        let tip = CGPoint(x: w * 0.86, y: h * 0.60 + flex)
        // Real wingtips are blunt: a chord this deep never tapers to a point.
        let tipChord = h * 0.055

        // Wing surface: leading edge out to the tip, square across the tip
        // chord, then the trailing edge sweeping back to the root.
        var wing = Path()
        wing.move(to: rootLead)
        wing.addQuadCurve(to: tip, control: CGPoint(x: w * 0.42, y: h * 0.735))
        wing.addLine(to: CGPoint(x: tip.x + w * 0.008, y: tip.y + tipChord))
        wing.addQuadCurve(to: CGPoint(x: -10, y: h * 1.16),
                          control: CGPoint(x: w * 0.36, y: h * 1.00))
        wing.closeSubpath()

        // Lit from above: the upper surface catches sky, the chord falls into
        // shadow toward the trailing edge.
        let top: Color = s.isNight ? Color(hex: "1A1F2C") : Color(hex: "D3D9E1")
        let mid: Color = s.isNight ? Color(hex: "12151E") : Color(hex: "9BA5B2")
        let bottom: Color = s.isNight ? Color(hex: "070910") : Color(hex: "5F6874")
        context.fill(wing, with: .linearGradient(
            Gradient(colors: [top, mid, bottom]),
            startPoint: CGPoint(x: 0, y: tip.y - h * 0.04),
            endPoint: CGPoint(x: 0, y: h * 1.05)))

        // Engine nacelle slung under the inboard wing — without it the wing
        // floats, with no sense of the aircraft it belongs to.
        let nacX = rootLead.x + (tip.x - rootLead.x) * 0.30
        let nacY = rootLead.y + (tip.y - rootLead.y) * 0.30 + h * 0.055
        let nacW = w * 0.30, nacH = h * 0.085
        let nacelle = Path(roundedRect: CGRect(x: nacX - nacW * 0.42, y: nacY,
                                               width: nacW, height: nacH),
                           cornerSize: CGSize(width: nacH * 0.5, height: nacH * 0.5))
        context.fill(nacelle, with: .linearGradient(
            Gradient(colors: [s.isNight ? Color(hex: "141824") : Color(hex: "B6BEC9"),
                              s.isNight ? Color(hex: "05070C") : Color(hex: "4E5763")]),
            startPoint: CGPoint(x: 0, y: nacY),
            endPoint: CGPoint(x: 0, y: nacY + nacH)))
        // Dark intake lip at the front of the nacelle.
        context.fill(
            Path(ellipseIn: CGRect(x: nacX - nacW * 0.42, y: nacY + nacH * 0.06,
                                   width: nacW * 0.17, height: nacH * 0.88)),
            with: .color(s.isNight ? Color(hex: "020306") : Color(hex: "2C333D")))

        // Flap-track fairings: slender pods trailing back off the surface.
        let fairing: Color = s.isNight ? Color(hex: "060810") : Color(hex: "525B66")
        for f in [0.34, 0.54, 0.72] {
            let baseX = rootLead.x + (tip.x - rootLead.x) * f
            let baseY = rootLead.y + (tip.y - rootLead.y) * f + h * (0.085 - 0.025 * f)
            // Pods shrink outboard with the chord.
            let scale = 1.0 - f * 0.45
            var pod = Path()
            pod.move(to: CGPoint(x: baseX - 13 * scale, y: baseY))
            pod.addQuadCurve(to: CGPoint(x: baseX + 28 * scale, y: baseY + 13 * scale),
                             control: CGPoint(x: baseX + 11 * scale, y: baseY + 2))
            pod.addQuadCurve(to: CGPoint(x: baseX - 13 * scale, y: baseY + 7 * scale),
                             control: CGPoint(x: baseX + 7 * scale, y: baseY + 11 * scale))
            pod.closeSubpath()
            context.fill(pod, with: .color(fairing.opacity(0.85)))
        }

        // Spoiler panel line along the surface.
        var panel = Path()
        panel.move(to: CGPoint(x: 0, y: h * 0.96))
        panel.addQuadCurve(to: CGPoint(x: tip.x * 0.9, y: tip.y + tipChord * 0.6),
                           control: CGPoint(x: w * 0.38, y: h * 0.855))
        context.stroke(panel, with: .color(.black.opacity(s.isNight ? 0.35 : 0.16)), lineWidth: 1)

        // Leading-edge glint — the brightest line on the wing, and the thing
        // that sells the surface as metal rather than a flat cutout.
        var edge = Path()
        edge.move(to: rootLead)
        edge.addQuadCurve(to: tip, control: CGPoint(x: w * 0.42, y: h * 0.735))
        context.stroke(edge, with: .color(.white.opacity(s.isNight ? 0.14 : 0.72)), lineWidth: 2)

        // Winglet: a blunt upturned blade, raked back, with real width — the
        // tip of a wing is a slab, never a needle.
        let wgH = h * 0.135
        let rake = w * 0.045
        var winglet = Path()
        winglet.move(to: CGPoint(x: tip.x - w * 0.005, y: tip.y + tipChord))
        winglet.addQuadCurve(to: CGPoint(x: tip.x + rake, y: tip.y - wgH),
                             control: CGPoint(x: tip.x + rake * 0.35, y: tip.y - wgH * 0.45))
        winglet.addLine(to: CGPoint(x: tip.x + rake + w * 0.032, y: tip.y - wgH * 0.94))
        winglet.addQuadCurve(to: CGPoint(x: tip.x + w * 0.030, y: tip.y + tipChord),
                             control: CGPoint(x: tip.x + rake * 0.75, y: tip.y - wgH * 0.35))
        winglet.closeSubpath()
        context.fill(winglet, with: .linearGradient(
            Gradient(colors: [s.isNight ? Color(hex: "171B26") : Color(hex: "C2CAD4"),
                              s.isNight ? Color(hex: "0A0D14") : Color(hex: "78828F")]),
            startPoint: CGPoint(x: 0, y: tip.y - wgH),
            endPoint: CGPoint(x: 0, y: tip.y + tipChord)))

        // Navigation light (green, starboard) + white strobe at the winglet tip.
        let navX = tip.x + rake + w * 0.012
        let navY = tip.y - wgH * 0.92
        let navOn = sin(s.time * 2.6) > -0.2
        let navAlpha = navOn ? 0.95 : 0.35
        context.fill(Path(ellipseIn: CGRect(x: navX - 2.5, y: navY - 2.5, width: 5, height: 5)),
                     with: .color(Color(hex: "3AE86B").opacity(navAlpha)))
        context.fill(Path(ellipseIn: CGRect(x: navX - 8, y: navY - 8, width: 16, height: 16)),
                     with: .color(Color(hex: "3AE86B").opacity(navAlpha * 0.2)))

        let strobePhase = s.time.truncatingRemainder(dividingBy: 1.4)
        if strobePhase < 0.06 || (strobePhase > 0.12 && strobePhase < 0.18) {
            context.fill(Path(ellipseIn: CGRect(x: navX - 11, y: navY - 11, width: 22, height: 22)),
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
