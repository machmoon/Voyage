import SwiftUI
import WidgetKit

/// Direction B, Orbit (`widget-concepts.html`, `#orbit`): a slice of Home's
/// globe. The earth's limb along the bottom, the route arcing over it, the
/// plane riding the arc. Daytime earth under a pale sky in light mode, city
/// lights and stars in dark.
struct OrbitWidget: View {
    var glance: FlightGlance
    var family: WidgetFamily
    @Environment(\.colorScheme) private var scheme

    struct Palette {
        var top, bottom, fg, dim, e1, e2, e3, rim, glow, glow2, route, dest: Color
        var stars: Bool

        static let light = Palette(
            top: hex(0xBCD3FF), bottom: hex(0xEAF1FF), fg: hex(0x0B0E14), dim: hex(0x0B0E14, 0.6),
            e1: hex(0x5E8FFF), e2: hex(0x2F62D6), e3: hex(0x123A93), rim: .white.opacity(0.85),
            glow: .white.opacity(0.9), glow2: hex(0x78AAFF, 0.55), route: hex(0x0B0E14),
            dest: hex(0x2F62D6), stars: false)
        static let dark = Palette(
            top: hex(0x0D1531), bottom: hex(0x050713), fg: .white, dim: .white.opacity(0.6),
            e1: hex(0x1C3F8F), e2: hex(0x0C2465), e3: hex(0x040B26), rim: hex(0xA0C3FF, 0.9),
            glow: hex(0x6EA0FF, 0.85), glow2: hex(0x5E8FFF, 0.45), route: .white,
            dest: hex(0x7EA6FF), stars: true)
    }

    private var palette: Palette { scheme == .dark ? .dark : .light }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangular.containerBackground(for: .widget) { Color.clear }
        case .accessoryCircular:
            circular.containerBackground(for: .widget) { Color.clear }
        case .systemMedium:
            home(medium: true)
                .containerBackground(for: .widget) { OrbitScene(palette: palette, glance: glance, medium: true) }
        default:
            home(medium: false)
                .containerBackground(for: .widget) { OrbitScene(palette: palette, glance: glance, medium: false) }
        }
    }

    // MARK: Home Screen

    private func home(medium: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow(medium: medium)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.dim)
            big(size: medium ? (glance.isFlying ? 40 : 34) : (glance.isFlying ? 36 : 30))
                .padding(.top, 5)
            Text(sub(medium: medium))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.dim)
                .padding(.top, 4)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(palette.fg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func eyebrow(medium: Bool) -> some View {
        switch glance.mode {
        case .flying: Text("to \(medium ? glance.city : glance.destination)")
        case .scheduled(let boarding):
            if medium {
                Text(boarding ? "Now boarding" : "Next flight")
            } else {
                HStack(spacing: 4) { Text(glance.origin); Plane(size: 9); Text(glance.destination) }
            }
        case .ready: Text("Quick flight")
        }
    }

    private func big(size: CGFloat) -> some View {
        Group {
            switch glance.mode {
            case .scheduled:
                let (time, ampm) = GlanceFormat.clock(glance.start)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(time)
                    Text(ampm).font(.system(size: size * 0.47, weight: .semibold))
                }
            case .flying: Text(GlanceFormat.duration(Double(glance.minutesLeft) * 60))
            case .ready: Text(GlanceFormat.duration(glance.duration))
            }
        }
        .font(.system(size: size, weight: .semibold, design: .rounded))
        .kerning(-size * 0.02)
        .monospacedDigit()
        .lineLimit(1)
    }

    private func sub(medium: Bool) -> String {
        switch glance.mode {
        case .scheduled:
            return medium
                ? [glance.city, GlanceFormat.duration(glance.duration), glance.flightNumber]
                    .compactMap { $0 }.joined(separator: " · ")
                : "Boards · \(GlanceFormat.duration(glance.duration))"
        case .flying: return "Lands \(GlanceFormat.clockText(glance.end))"
        case .ready:
            return glance.hasRoute ? "\(glance.origin) → \(glance.destination) · tap to fly" : "Tap to take off"
        }
    }

    // MARK: Lock Screen

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Group {
                switch glance.mode {
                case .flying:
                    Text("\(glance.minutesLeft)m ").fontWeight(.bold)
                        + Text("to \(glance.destination)").fontWeight(.medium).foregroundColor(.secondary)
                case .scheduled:
                    Text("\(glance.destination) · \(GlanceFormat.clockText(glance.start))").fontWeight(.bold)
                case .ready:
                    Text("\(glance.destination.isEmpty ? "Quick" : glance.destination) · \(GlanceFormat.duration(glance.duration))")
                        .fontWeight(.bold)
                }
            }
            .font(.system(size: 15))
            .lineLimit(1)
            ArcRoute(start: CGPoint(x: 4, y: 26), control: CGPoint(x: 80, y: -6), end: CGPoint(x: 156, y: 26),
                     design: CGSize(width: 160, height: 30), progress: glance.progress,
                     flying: glance.isFlying, color: .primary, dest: .primary, planeSize: 12)
                .frame(height: 30)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            GeometryReader { geo in
                let s = geo.size.width / 72
                Ellipse().fill(.primary.opacity(0.22))
                    .overlay(Ellipse().stroke(.primary.opacity(0.7), lineWidth: 1))
                    .frame(width: 100 * s, height: 100 * s)
                    .position(x: 36 * s, y: 100 * s)
                if glance.isFlying {
                    ArcRoute(start: CGPoint(x: 14, y: 52), control: CGPoint(x: 36, y: 30), end: CGPoint(x: 58, y: 52),
                             design: CGSize(width: 72, height: 72), progress: glance.progress, flying: true,
                             color: .primary, dest: .primary, planeSize: 9, endpoints: false)
                }
            }
            .clipShape(Circle())
            VStack(spacing: 3) {
                if glance.isFlying {
                    Text("\(glance.minutesLeft)m").font(.system(size: 19, weight: .bold, design: .rounded))
                } else {
                    Text(glance.mode == .ready ? GlanceFormat.duration(glance.duration) : GlanceFormat.clock(glance.start).0)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text(glance.mode == .ready ? "QUICK" : "BOARDS").font(.system(size: 10, weight: .semibold))
                }
            }
            .minimumScaleFactor(0.7)
            .offset(y: glance.isFlying ? -16 : -10)
        }
        .widgetAccentable()
    }
}

/// The sky, the earth's limb and the route, drawn at the mockup's coordinates
/// (158 x 158 small, 338 x 158 medium) and scaled to the real widget.
struct OrbitScene: View {
    var palette: OrbitWidget.Palette
    var glance: FlightGlance
    var medium: Bool

    var body: some View {
        GeometryReader { geo in
            let design = CGSize(width: medium ? 338 : 158, height: 158)
            let sx = geo.size.width / design.width, sy = geo.size.height / design.height
            let earth: (d: CGFloat, x: CGFloat, y: CGFloat) = medium ? (760, -211, 118) : (360, -101, 116)
            ZStack {
                LinearGradient(colors: [palette.top, palette.bottom], startPoint: .top, endPoint: .bottom)
                if palette.stars {
                    ForEach(Array([(0.18, 0.22), (0.72, 0.14), (0.88, 0.38), (0.56, 0.30), (0.34, 0.46), (0.94, 0.08)]
                        .enumerated()), id: \.offset) { _, p in
                        Circle().fill(.white.opacity(0.75)).frame(width: 1.4, height: 1.4)
                            .position(x: geo.size.width * p.0, y: geo.size.height * p.1)
                    }
                }
                Circle()
                    .fill(RadialGradient(stops: [
                        .init(color: palette.e1, location: 0), .init(color: palette.e2, location: 0.3),
                        .init(color: palette.e3, location: 0.65),
                    ], center: UnitPoint(x: 0.5, y: 0), startRadius: 0, endRadius: earth.d * sx * 0.7))
                    .overlay(Circle().stroke(palette.rim, lineWidth: 1))
                    .shadow(color: palette.glow, radius: 4, y: -2)
                    .shadow(color: palette.glow2, radius: 18, y: -12)
                    .frame(width: earth.d * sx, height: earth.d * sx)
                    .position(x: (earth.x + earth.d / 2) * sx, y: (earth.y + earth.d / 2) * sy + (earth.d * (sx - sy)) / 2)
                ArcRoute(start: medium ? CGPoint(x: 150, y: 122) : CGPoint(x: 30, y: 122),
                         control: medium ? CGPoint(x: 240, y: 50) : CGPoint(x: 79, y: 74),
                         end: medium ? CGPoint(x: 316, y: 106) : CGPoint(x: 128, y: 116),
                         design: design, progress: glance.progress, flying: glance.isFlying,
                         color: palette.route, dest: palette.dest, planeSize: medium ? 15 : 13)
                if medium, glance.hasRoute {
                    Text(glance.origin).position(x: 150 * sx, y: 137 * sy)
                    Text(glance.destination).position(x: 316 * sx, y: 122 * sy)
                }
            }
            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(palette.dim)
        }
    }
}

/// A quadratic route: solid where flown, dotted ahead, the plane on the curve
/// pointing along it.
struct ArcRoute: View {
    var start: CGPoint
    var control: CGPoint
    var end: CGPoint
    var design: CGSize
    var progress: Double
    var flying: Bool
    var color: Color
    var dest: Color
    var planeSize: CGFloat
    var endpoints = true

    var body: some View {
        GeometryReader { geo in
            let sx = geo.size.width / design.width, sy = geo.size.height / design.height
            let p0 = CGPoint(x: start.x * sx, y: start.y * sy)
            let p1 = CGPoint(x: control.x * sx, y: control.y * sy)
            let p2 = CGPoint(x: end.x * sx, y: end.y * sy)
            let t = flying ? progress : 0
            let at = Self.point(p0, p1, p2, t)
            ZStack {
                Path { p in
                    p.move(to: at)
                    p.addQuadCurve(to: p2, control: Self.lerp(p1, p2, t))
                }
                .stroke(color.opacity(0.6), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, dash: [1.5, 3.5]))
                if flying {
                    Path { p in
                        p.move(to: p0)
                        p.addQuadCurve(to: at, control: Self.lerp(p0, p1, t))
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    Plane(size: planeSize, angle: Self.angle(p0, p1, p2, t))
                        .foregroundStyle(color)
                        .position(at)
                }
                if endpoints {
                    Circle().fill(color).frame(width: 5.2, height: 5.2).position(p0)
                    Circle().stroke(dest, lineWidth: 1.6).frame(width: 7.2, height: 7.2).position(p2)
                    Circle().fill(dest).frame(width: 2.6, height: 2.6).position(p2)
                }
            }
        }
        .accessibilityHidden(true)
    }

    static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    static func point(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ t: Double) -> CGPoint {
        lerp(lerp(p0, p1, t), lerp(p1, p2, t), t)
    }

    static func angle(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ t: Double) -> Double {
        let dx = 2 * (1 - t) * (p1.x - p0.x) + 2 * t * (p2.x - p1.x)
        let dy = 2 * (1 - t) * (p1.y - p0.y) + 2 * t * (p2.y - p1.y)
        return atan2(dy, dx) * 180 / .pi
    }
}
