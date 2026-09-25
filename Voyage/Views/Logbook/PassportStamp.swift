import SwiftUI

// MARK: - DESIGN-NOTES (passport stamps, after Airbnb's PassportStamp)
//
// Airbnb ships real passport stamps on its profiles ("Where I've been"). The
// construction below follows that component; none of its artwork is used.
// Sources, fetched 2026-09-24 (local copies and a full write-up in
// scratchpad/airbnb/airbnb-design-research.md §6a):
//   S7  component `PassportStamp` / `PassportStampsScroller`
//       https://a0.muscache.com/airbnb/static/packages/web/en/frontend/user-profile-next/components/sections/UserProfilePastTripsSection.f8ccd39859.js
//   S10 the default stamp image (Paris, 480 x 480, the only public one)
//       https://a0.muscache.com/im/pictures/airbnb-platform-assets/AirbnbPlatformAssets-PassportOnboarding/original/1f379de0-0962-4ab1-af1d-e038e0ab10d6.png
//   S11 passport-spa stylesheet (caption type, hidden-stamp filter)
//       https://a0.muscache.com/airbnb/static/packages/web/common/frontend/passport-spa/entrypoints/client.00ff6058aa.css
//   S2  guest stylesheet :root tokens (grey ramp, avatar ink schemes)
//       https://a0.muscache.com/airbnb/static/packages/web/common/frontend/core-guest-spa/entrypoints/client.37c1c188d0.css
//
// What is borrowed, and where it lives here:
//   - ONE flat ink per stamp, full opacity (S10 is a single navy, #103672).
//     `StampInk`. No alpha layering, no second inner ring.
//   - ONE ring, ~2% of the diameter (S10: ~10 px on 480). `ringRatio`.
//   - Name on top inside the ring, ISO country code small at the left, a
//     line-art landmark in the centre at the ring's stroke weight (S10).
//     Voyage puts its own airplane where S10 has Airbnb's mark.
//   - The landmarks are drawn here as simple Paths (`StampMotif`). They are
//     generic silhouettes of each city (a lighthouse, a bridge, a tower), not
//     traced from anything.
//   - Date and visits are LIVE TEXT BELOW the stamp, not in the art (S7 data
//     model `{stampResourceUrl, localizedLocation, subtitle}`); city 14/18
//     text-primary, date 12/16 text-secondary, 16 px above (S7 + S11
//     `atm_c8_18p4cis`, `atm_h3_exct8b`). See `PassportView.StampCell`.
//   - Tilt: S7 `y = t => (t % 2 == 0 ? -1 : 1) * (1 + t % 3 * .5)`, i.e.
//     -1, +1.5, -2, +1, -1.5, +2 degrees, scaled by h / (w sin θ + h cos θ) so
//     a rotated stamp keeps its box. `PassportStamp.tilt(forIndex:)`.
//   - Not collected: the SAME art recolored grey, not faded (S11 hidden stamp
//     `filter: brightness(0) … invert(72%)` ≈ #B8B8B8, with
//     `transition: filter 250ms cubic-bezier(0.2,0,0,1)`). `StampInk.uncollected`.
//   - Gold is scarce. Airbnb uses gold for exactly one accolade (Guest
//     Favorite). Here it marks only the single most-visited city, and only at
//     3+ visits. The ink is a split of the laurel's measured gold ramp
//     (#644307 → #926816 → #B58824 → #D7B23E → #F9EC67, S15 PNGs) and the
//     label is the pearly Guest-Favorite pill (S22 live style:
//     linear-gradient(to right top, #F2F2F2 0%, #FFF 11%, #FFF 70%, #EBEBEB 94%),
//     1px #FFF border, 0 4px 10px rgba(0,0,0,.16), 500 weight). The scalloped
//     die is kept for this stamp only (research §6c.2: the special shape is
//     as rare as the gold).

/// One destination's arrival stamp: ring, code, country, landmark.
struct PassportStamp: View {
    enum StampState: Equatable { case collected, uncollected, gold }

    let code: String
    let state: StampState
    var diameter: CGFloat = 100

    /// S10: ~10 px ring on a 480 px stamp.
    static let ringRatio: CGFloat = 0.022

    var body: some View {
        let d = diameter
        let line = max(1.5, d * Self.ringRatio)
        let ink = inkStyle
        ZStack {
            ring(line: line, ink: ink)

            Text(code)
                .font(.system(size: d * 0.19, weight: .semibold))
                .kerning(d * 0.004)
                .foregroundStyle(ink)
                .position(x: d / 2, y: d * 0.28)

            Text(Self.country(for: code))
                .font(.system(size: d * 0.085, weight: .semibold))
                .foregroundStyle(ink)
                .position(x: d * 0.18, y: d * 0.55)

            Image(systemName: "airplane")
                .font(.system(size: d * 0.085, weight: .semibold))
                .foregroundStyle(ink)
                .position(x: d * 0.82, y: d * 0.55)

            StampMotif(kind: StampMotif.Kind(code: code))
                .stroke(ink, style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
                .frame(width: d * 0.42, height: d * 0.36)
                .position(x: d / 2, y: d * 0.64)
        }
        .frame(width: d, height: d)
        // S11: filter 250ms cubic-bezier(0.2,0,0,1).
        .animation(.timingCurve(0.2, 0, 0, 1, duration: 0.25), value: state)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func ring(line: CGFloat, ink: AnyShapeStyle) -> some View {
        if state == .gold {
            ScallopedRing(teeth: 24)
                .stroke(ink, style: StrokeStyle(lineWidth: line, lineJoin: .round))
                .padding(line)
        } else {
            Circle().strokeBorder(ink, lineWidth: line)
        }
    }

    private var inkStyle: AnyShapeStyle {
        switch state {
        case .collected: AnyShapeStyle(StampInk.forCode(code))
        case .uncollected: AnyShapeStyle(StampInk.uncollected)
        case .gold: AnyShapeStyle(StampInk.gold)
        }
    }

    /// Every Voyage airport is in the US or Canada, and Canadian IATA codes
    /// all begin with Y.
    static func country(for code: String) -> String {
        code.hasPrefix("Y") ? "CA" : "US"
    }

    /// Airbnb's stamp tilt sequence, in degrees (S7).
    static func tilt(forIndex t: Int) -> Double {
        (t % 2 == 0 ? -1 : 1) * (1 + Double(t % 3) * 0.5)
    }

    /// S7's compensation: scale(min(h/I, I/h)) with I = w·sinθ + h·cosθ.
    static func tiltScale(degrees: Double) -> CGFloat {
        let theta = abs(degrees) * .pi / 180
        let i = sin(theta) + cos(theta)          // w = h = 1
        return CGFloat(min(1 / i, i / 1))
    }
}

// MARK: - Inks

/// Per-destination stamp inks, built like Airbnb's avatar schemes (S2
/// `--palette-text-avatar-scheme-*`): each hue's dark partner for text on a
/// light page. The hues are Voyage's own (`Airport.accentHex` in
/// Airport.swift), stepped in HSL lightness until each clears 7:1 (WCAG
/// relative luminance) on its card: light on #FFFFFF, dark on #242526
/// (MetaStyle.cardBackground). Airbnb's own stamp navy #103672 sits at 10.5:1,
/// which is why these are this dark. Measured ratios in the comments.
enum StampInk {
    private static let table: [String: (light: String, dark: String)] = [
        "BOS": ("1053B9", "85B1F4"),   // 7.09 / 7.01
        "JFK": ("785106", "F5B02C"),   // 7.05 / 8.14
        "MIA": ("B20033", "FF8CAD"),   // 7.14 / 7.02
        "RDU": ("405987", "9EB0D1"),   // 7.01 / 7.01
        "SFO": ("A32F00", "FF9469"),   // 7.09 / 7.09
        "LAX": ("7300ED", "CC9BFF"),   // 7.11 / 7.09
        "SEA": ("2E5D7A", "88B6D2"),   // 7.09 / 7.07
        "YYZ": ("0F5D8B", "62B9EE"),   // 7.10 / 7.09
        "YVR": ("186549", "2FC68F"),   // 7.01 / 7.02
        "YQR": ("72520D", "E8B23A"),   // 7.17 / 7.94
    ]

    static func forCode(_ code: String) -> Color {
        let pair = table[code] ?? ("1053B9", "85B1F4")
        return MetaStyle.pair(pair.light, pair.dark)
    }

    /// S11's hidden-stamp grey (≈#B8B8B8 on light). On the dark card the
    /// same idea is #5C5C5C, between S2's grey-800 #515151 and grey-700
    /// #6C6C6C: quiet, but still legible as the same art.
    static let uncollected = MetaStyle.pair("B8B8B8", "5C5C5C")

    /// The laurel's gold (S15), split along a diagonal like its faceted
    /// leaves: shade → mid → shade. On light the darker half of the ramp
    /// (#926816 is 4.98:1 on white); on dark the lighter half
    /// (#D7B23E is 7.55:1 on #242526).
    static let gold = LinearGradient(
        stops: [
            .init(color: MetaStyle.pair("7A5610", "F9EC67"), location: 0),
            .init(color: MetaStyle.pair("B58824", "D7B23E"), location: 0.45),
            .init(color: MetaStyle.pair("644307", "B58824"), location: 1),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

// MARK: - Gold pill

/// The one gold label in the app, built like Airbnb's Guest Favorite pill
/// (S22 live computed style): pearly white gradient, 1pt white border, soft
/// 0/4/10 16% shadow, 500-weight text in black, a small gold glyph. The glyph
/// is Voyage's own (a laurel-free star), not Airbnb's trophy or laurels.
struct MostVisitedPill: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [Color(hex: "D7B23E"), Color(hex: "926816")],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
            Text("Most visited")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.black)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(
            Capsule().fill(LinearGradient(
                stops: [.init(color: Color(hex: "F2F2F2"), location: 0),
                        .init(color: .white, location: 0.11),
                        .init(color: .white, location: 0.70),
                        .init(color: Color(hex: "EBEBEB"), location: 0.94)],
                startPoint: .bottomLeading, endPoint: .topTrailing))
        )
        .overlay(Capsule().strokeBorder(Color.white, lineWidth: 1))
        .shadow(color: .black.opacity(0.16), radius: 5, y: 4)
        .accessibilityHidden(true)
    }
}

// MARK: - Motifs

/// A one-line landmark per Voyage city, drawn on a unit box (x right, y down,
/// ground at y = 1) and stroked at the ring's weight, the way S10's tower is
/// drawn at the ring's weight. Kept to a handful of strokes each so they read
/// at 40pt and survive the grey recolor.
struct StampMotif: Shape {
    enum Kind {
        case lighthouse, skyline, palm, pine, bridge, sunset, needle, tower, mountains, elevator, plane

        init(code: String) {
            switch code {
            case "BOS": self = .lighthouse   // Boston Light
            case "JFK": self = .skyline      // Midtown setbacks
            case "MIA": self = .palm
            case "RDU": self = .pine         // the longleaf pine, NC's state tree
            case "SFO": self = .bridge       // a suspension span
            case "LAX": self = .sunset       // sun on the Pacific
            case "SEA": self = .needle       // an observation tower on legs
            case "YYZ": self = .tower        // a needle tower with a pod
            case "YVR": self = .mountains    // the North Shore peaks
            case "YQR": self = .elevator     // a prairie grain elevator
            default: self = .plane
            }
        }
    }

    let kind: Kind

    func path(in rect: CGRect) -> Path {
        var p = Path()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        func line(_ points: [(CGFloat, CGFloat)]) {
            guard let first = points.first else { return }
            p.move(to: pt(first.0, first.1))
            for point in points.dropFirst() { p.addLine(to: pt(point.0, point.1)) }
        }
        func ground(_ from: CGFloat = 0.08, _ to: CGFloat = 0.92) { line([(from, 1), (to, 1)]) }

        switch kind {
        case .lighthouse:
            ground()
            line([(0.40, 1), (0.44, 0.34), (0.56, 0.34), (0.60, 1)])       // tapered tower
            line([(0.38, 0.34), (0.62, 0.34)])                              // gallery
            line([(0.45, 0.34), (0.45, 0.20), (0.55, 0.20), (0.55, 0.34)])  // lantern
            line([(0.43, 0.20), (0.50, 0.08), (0.57, 0.20)])                // cap
            line([(0.30, 0.22), (0.18, 0.17)])                              // beams
            line([(0.70, 0.22), (0.82, 0.17)])
            line([(0.425, 0.62), (0.575, 0.62)])                            // band
        case .skyline:
            ground()
            line([(0.14, 1), (0.14, 0.58), (0.30, 0.58), (0.30, 1)])
            line([(0.38, 1), (0.38, 0.46), (0.43, 0.46), (0.43, 0.30),
                  (0.47, 0.30), (0.47, 0.20), (0.53, 0.20), (0.53, 0.30),
                  (0.57, 0.30), (0.57, 0.46), (0.62, 0.46), (0.62, 1)])
            line([(0.50, 0.20), (0.50, 0.02)])                              // spire
            line([(0.70, 1), (0.70, 0.66), (0.86, 0.66), (0.86, 1)])
        case .palm:
            ground(0.12, 0.88)
            p.move(to: pt(0.50, 1))
            p.addQuadCurve(to: pt(0.44, 0.30), control: pt(0.58, 0.62))     // trunk
            let crown = pt(0.44, 0.30)
            for (end, control) in [((0.14, 0.44), (0.24, 0.16)),
                                   ((0.20, 0.16), (0.30, 0.10)),
                                   ((0.66, 0.10), (0.58, 0.04)),
                                   ((0.80, 0.40), (0.72, 0.14))] {
                p.move(to: crown)
                p.addQuadCurve(to: pt(end.0, end.1), control: pt(control.0, control.1))
            }
        case .pine:
            ground(0.16, 0.84)
            line([(0.50, 1), (0.50, 0.84)])                                 // trunk
            // One outline, three tiers.
            line([(0.50, 0.06), (0.64, 0.30), (0.57, 0.30), (0.70, 0.56),
                  (0.61, 0.56), (0.76, 0.84), (0.24, 0.84), (0.39, 0.56),
                  (0.30, 0.56), (0.43, 0.30), (0.36, 0.30), (0.50, 0.06)])
        case .bridge:
            line([(0.0, 0.80), (1.0, 0.80)])                                // deck
            line([(0.28, 1), (0.28, 0.10)])                                 // towers
            line([(0.72, 1), (0.72, 0.10)])
            line([(0.25, 0.30), (0.31, 0.30)])
            line([(0.69, 0.30), (0.75, 0.30)])
            p.move(to: pt(0.28, 0.12))                                      // main cable
            p.addQuadCurve(to: pt(0.72, 0.12), control: pt(0.50, 0.95))
            p.move(to: pt(0.0, 0.56))
            p.addQuadCurve(to: pt(0.28, 0.12), control: pt(0.18, 0.46))
            p.move(to: pt(1.0, 0.56))
            p.addQuadCurve(to: pt(0.72, 0.12), control: pt(0.82, 0.46))
        case .sunset:
            p.addArc(center: pt(0.50, 0.68), radius: rect.width * 0.20,
                     startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            line([(0.06, 0.68), (0.94, 0.68)])                              // horizon
            line([(0.50, 0.30), (0.50, 0.16)])                              // rays
            line([(0.26, 0.44), (0.18, 0.34)])
            line([(0.74, 0.44), (0.82, 0.34)])
            line([(0.22, 0.84), (0.44, 0.84)])                              // swell
            line([(0.56, 0.84), (0.78, 0.84)])
            line([(0.36, 1.0), (0.64, 1.0)])
        case .needle:
            ground(0.16, 0.84)
            line([(0.40, 1), (0.48, 0.52), (0.52, 0.52), (0.60, 1)])        // legs
            line([(0.48, 0.52), (0.46, 0.34)])
            line([(0.52, 0.52), (0.54, 0.34)])
            line([(0.30, 0.30), (0.70, 0.30), (0.62, 0.38), (0.38, 0.38), (0.30, 0.30)]) // saucer
            line([(0.40, 0.30), (0.44, 0.22), (0.56, 0.22), (0.60, 0.30)])
            line([(0.50, 0.22), (0.50, 0.02)])                              // spire
        case .tower:
            ground(0.12, 0.88)
            line([(0.45, 1), (0.48, 0.44)])                                 // shaft
            line([(0.55, 1), (0.52, 0.44)])
            line([(0.38, 0.44), (0.62, 0.44), (0.58, 0.34), (0.42, 0.34), (0.38, 0.44)]) // pod
            line([(0.49, 0.34), (0.495, 0.22)])
            line([(0.51, 0.34), (0.505, 0.22)])
            line([(0.50, 0.22), (0.50, 0.0)])                               // antenna
            line([(0.18, 1), (0.18, 0.78), (0.32, 0.78), (0.32, 1)])        // low city
            line([(0.68, 1), (0.68, 0.72), (0.80, 0.72), (0.80, 1)])
        case .mountains:
            line([(0.02, 1), (0.34, 0.34), (0.52, 0.66), (0.70, 0.22), (0.98, 1)])
            line([(0.25, 0.52), (0.34, 0.46), (0.41, 0.52)])                // snow lines
            line([(0.61, 0.40), (0.70, 0.34), (0.78, 0.42)])
            line([(0.10, 0.86), (0.36, 0.86)])                              // water
            line([(0.62, 0.86), (0.90, 0.86)])
        case .elevator:
            ground(0.06, 0.94)
            line([(0.30, 1), (0.30, 0.36), (0.44, 0.14), (0.58, 0.36), (0.58, 1)]) // main bin
            line([(0.39, 0.22), (0.39, 0.06), (0.49, 0.06), (0.49, 0.22)])  // cupola
            line([(0.58, 0.56), (0.80, 0.56), (0.80, 1)])                   // annex
            line([(0.40, 0.50), (0.48, 0.50)])                              // window
            line([(0.10, 1), (0.10, 0.84)])                                 // wheat
            line([(0.16, 1), (0.16, 0.80)])
        case .plane:
            // A generic airliner in plan view, nose up.
            line([(0.50, 0.02), (0.50, 0.98)])
            line([(0.08, 0.56), (0.50, 0.38), (0.92, 0.56)])
            line([(0.34, 0.94), (0.50, 0.84), (0.66, 0.94)])
        }
        return p
    }
}

/// A die with a wavy edge, for the gold stamp only.
struct ScallopedRing: Shape {
    let teeth: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let base = min(rect.width, rect.height) / 2 / 1.04
        let steps = teeth * 8
        for step in 0...steps {
            let angle = Double(step) / Double(steps) * 2 * .pi
            let wave = 1 + 0.04 * cos(angle * Double(teeth))
            let point = CGPoint(x: centre.x + cos(angle) * base * wave,
                                y: centre.y + sin(angle) * base * wave)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}
