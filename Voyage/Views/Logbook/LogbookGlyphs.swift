import SwiftUI

// Row glyphs for the Logbook, drawn in SwiftUI after two Airbnb DLS icons.
// Neither icon's artwork is copied; the construction rules are. Sources (the
// SVG ships inside a JS module, local copies in scratchpad/airbnb/dls/):
//   IcSystemTicket32       https://a0.muscache.com/airbnb/static/packages/web/common/frontend/dls-icons/components/IcSystemTicket32.728440d958.js
//   IcFeatureGraphUpAlt48  https://a0.muscache.com/airbnb/static/packages/web/common/frontend/dls-icons/components/IcFeatureGraphUpAlt48.e7e5841cb2.js

// MARK: - Ticket

/// A ticket outline with a semicircular notch in each side at mid-height.
///
/// Proportions are IcSystemTicket32's, read off its path on the 32 grid:
/// body 30 x 26 units, outer corner radius 2 (`c1.1046 0 2 .89543 2 2`),
/// notch radius 2 centred 1 unit inside each edge at the vertical midpoint
/// (`h-1 c-1.1046 0-2 .8954-2 2 s.8954 2 2 2 h1`). Everything scales off the
/// height so the tile can be any size.
struct TicketShape: InsettableShape {
    var inset: CGFloat = 0

    /// 2 / 26 of the body height.
    static let notchRatio: CGFloat = 2 / 26
    /// Outer radius, also 2 / 26 of the height ("radius ~2, scaled").
    static let cornerRatio: CGFloat = 2 / 26
    /// The notch centre sits 1 unit inside the edge: 1 / 30 of the width.
    static let notchInsetRatio: CGFloat = 1 / 30

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let notch = r.height * Self.notchRatio
        let corner = r.height * Self.cornerRatio
        let notchInset = r.width * Self.notchInsetRatio
        var p = Path()
        p.move(to: CGPoint(x: r.minX + corner, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - corner, y: r.minY))
        p.addArc(center: CGPoint(x: r.maxX - corner, y: r.minY + corner), radius: corner,
                 startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        // Right edge down to the notch, the flat 1-unit lip, the half circle
        // bulging inward, the lip back out.
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY - notch))
        p.addLine(to: CGPoint(x: r.maxX - notchInset, y: r.midY - notch))
        p.addArc(center: CGPoint(x: r.maxX - notchInset, y: r.midY), radius: notch,
                 startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: true)
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY + notch))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - corner))
        p.addArc(center: CGPoint(x: r.maxX - corner, y: r.maxY - corner), radius: corner,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: r.minX + corner, y: r.maxY))
        p.addArc(center: CGPoint(x: r.minX + corner, y: r.maxY - corner), radius: corner,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: r.minX, y: r.midY + notch))
        p.addLine(to: CGPoint(x: r.minX + notchInset, y: r.midY + notch))
        p.addArc(center: CGPoint(x: r.minX + notchInset, y: r.midY), radius: notch,
                 startAngle: .degrees(90), endAngle: .degrees(-90), clockwise: true)
        p.addLine(to: CGPoint(x: r.minX, y: r.midY - notch))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + corner))
        p.addArc(center: CGPoint(x: r.minX + corner, y: r.minY + corner), radius: corner,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> TicketShape {
        var copy = self
        copy.inset += amount
        return copy
    }
}

/// The leading tile of a flight row: a ticket with the destination code.
///
/// Built on IcSystemTicket32: the perforation is its column of 5 dots
/// (r = 1, 4 units apart, centred at x = 9 of 32, i.e. 8 / 30 of the body),
/// and the stub left of it carries the lime fill, the one place the accent
/// shows on a row (research §7, "use lime sparingly"). The code takes the
/// wide side where the icon draws its two bars.
///
/// A flight that stopped early keeps the same ticket in grey, the way
/// Airbnb recolors a hidden passport stamp grey instead of fading it
/// (passport-spa client.00ff6058aa.css). No stub fill: nothing was admitted.
struct TicketTile: View {
    let code: String
    let landed: Bool

    static let size = CGSize(width: 60, height: 40)
    /// 8 / 30: the perforation's x on IcSystemTicket32's body.
    private static let perforationRatio: CGFloat = 8 / 30
    /// Airbnb's 2-on-32 line weight is 6.25%; at this size that is 2.5pt,
    /// heavy next to 15pt text, so the row uses the research's 1.5pt.
    private static let lineWidth: CGFloat = 1.5

    var body: some View {
        let size = Self.size
        let stubWidth = size.width * Self.perforationRatio
        let line = landed ? Ramp.ink : Ramp.muted
        let notchReach = size.width * TicketShape.notchInsetRatio
            + size.height * TicketShape.notchRatio + 1
        ZStack(alignment: .leading) {
            TicketShape().fill(Ramp.surface)
            if landed {
                Rectangle()
                    .fill(Ramp.solar)
                    .frame(width: stubWidth)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipShape(TicketShape())
            }
            perforation(color: line)
                .frame(width: 2.4)
                .offset(x: stubWidth - 1.2)
            Text(code)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(landed ? Ramp.ink : Ramp.hushed)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                // Centred between the perforation and the inner edge of
                // the right notch, so the code never crowds the cut.
                .frame(width: size.width - stubWidth - notchReach)
                .offset(x: stubWidth)
            TicketShape().strokeBorder(line, lineWidth: Self.lineWidth)
        }
        .frame(width: size.width, height: size.height)
        .animation(.timingCurve(0.2, 0, 0, 1, duration: 0.25), value: landed)
    }

    /// 5 dots, 4 / 26 of the height apart, like the icon's column.
    private func perforation(color: Color) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { index in
                Circle().fill(color).frame(width: 2.4, height: 2.4)
                if index < 4 { Spacer(minLength: 0) }
            }
        }
        .frame(height: Self.size.height * (16 / 26) + 2.4)
    }
}

// MARK: - Insights

/// The Insights row glyph, drawn the way Airbnb draws its 48-grid "Feature"
/// icons: one outline at full strength plus ONE secondary shape set inside
/// it at 20% (`fill-opacity=".2"` in IcFeatureGraphUpAlt48). Here that is an
/// L of axes, a rising line that ends in an arrow, and the area under the
/// line. Coordinates are on the icon's own 48 grid:
///   axes         IcFeatureGraphUpAlt48 `M4 5 v38 h39` (x = 5, y = 43)
///   rising line  its `L18.1 19 H28.2 L40.7 6` (flat run then climb)
///   arrowhead    its `H35 V4 H43 V13 H41` corner at the top right
///   area         its second path, at 20%
/// Voyage's line bends twice more (four study weeks read as a trend), and
/// uses round strokes to match SF Symbols at 22pt.
struct InsightsGlyph: View {
    var line: Color
    /// The 20% layer. Airbnb uses currentColor at .2; `area` lets the row
    /// put the lime fill there instead (see LogbookView.recorderRow).
    var area: Color
    var areaOpacity: Double = 0.2
    var lineWidth: CGFloat = 1.75

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 48
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

            // The trend: flat, up, a small dip, up to the arrow.
            let trend: [CGPoint] = [pt(10, 34), pt(18, 27), pt(25, 30), pt(39, 11)]

            var areaPath = Path()
            areaPath.move(to: pt(10, 39))
            for p in trend { areaPath.addLine(to: p) }
            areaPath.addLine(to: pt(39, 39))
            areaPath.closeSubpath()
            context.fill(areaPath, with: .color(area.opacity(areaOpacity)))

            let stroke = StrokeStyle(lineWidth: lineWidth * s * 48 / 24, lineCap: .round, lineJoin: .round)

            var axes = Path()
            axes.move(to: pt(5, 5))
            axes.addLine(to: pt(5, 43))
            axes.addLine(to: pt(43, 43))
            context.stroke(axes, with: .color(line), style: stroke)

            var trendPath = Path()
            trendPath.move(to: trend[0])
            for p in trend.dropFirst() { trendPath.addLine(to: p) }
            context.stroke(trendPath, with: .color(line), style: stroke)

            // Arrowhead: the two arms of the icon's corner, pointing along
            // the last segment.
            var arrow = Path()
            arrow.move(to: pt(30, 11))
            arrow.addLine(to: pt(39, 11))
            arrow.addLine(to: pt(39, 20))
            context.stroke(arrow, with: .color(line), style: stroke)
        }
        .accessibilityHidden(true)
    }
}
