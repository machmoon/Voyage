import SwiftUI
import WidgetKit

/// Direction D, Heading (`widget-concepts.html`, `#hsi`): a horizontal
/// situation indicator. The compass card turned to the course for the
/// destination, the magenta course needle, the amber lubber line, and in the
/// air a ring that fills over the leg. The dial is the mockup's own SVG
/// generator (its `data-dial` script) redrawn with `Canvas`.
struct HeadingWidget: View {
    var glance: FlightGlance
    var family: WidgetFamily
    @Environment(\.colorScheme) private var scheme

    struct Palette {
        var bg, face, ring, tick, fg, dim, magenta, amber, progress, rule: Color
        static let light = Palette(bg: hex(0xE6EAF0), face: hex(0xF8FAFD), ring: hex(0xC9D0DB), tick: hex(0x0B0E14),
                                   fg: hex(0x0B0E14), dim: hex(0x5D6577), magenta: hex(0xB437C9),
                                   amber: hex(0xC77800), progress: hex(0x3D6FE8), rule: hex(0xCFD5DF))
        static let dark = Palette(bg: hex(0x05070B), face: hex(0x0B0E14), ring: hex(0x232A38), tick: hex(0xE9EDF5),
                                  fg: .white, dim: hex(0x8A93A6), magenta: hex(0xF07CFF),
                                  amber: hex(0xFFB938), progress: hex(0x5E8FFF), rule: hex(0x1D2330))
    }

    private var palette: Palette { scheme == .dark ? .dark : .light }

    private var background: some View {
        RadialGradient(colors: [palette.face, palette.bg], center: UnitPoint(x: 0.3, y: 0.2),
                       startRadius: 0, endRadius: 200)
    }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangular.containerBackground(for: .widget) { Color.clear }
        case .accessoryCircular:
            circular.containerBackground(for: .widget) { Color.clear }
        case .systemMedium:
            medium.containerBackground(for: .widget) { background }
        default:
            HSIDial(glance: glance, palette: palette)
                .padding(-5)
                .containerBackground(for: .widget) { background }
        }
    }

    // MARK: Medium

    private var medium: some View {
        HStack(spacing: 16) {
            HSIDial(glance: glance, palette: palette)
                .aspectRatio(1, contentMode: .fit)
            VStack(alignment: .leading, spacing: 0) {
                if glance.isFlying {
                    row("ETE", GlanceFormat.ete(glance.end.timeIntervalSince(glance.now)), hero: true)
                    Spacer(minLength: 0)
                    row("ETA", GlanceFormat.clock24(glance.end))
                    Spacer(minLength: 0)
                    row("CRS", GlanceFormat.degrees(glance.course), color: palette.magenta)
                    Spacer(minLength: 0)
                    row(glance.seat == nil ? "FLOWN" : "SEAT",
                        glance.seat ?? "\(glance.minutesFlown)m", color: palette.progress, last: true)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(glance.hasRoute ? glance.destination : "VOYAGE")
                            .font(.system(size: 22, weight: .bold)).kerning(-0.2)
                        Text(glance.mode == .ready ? "Quick flight · from \(glance.origin)"
                                                   : "\(glance.city) · from \(glance.origin)")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(palette.dim)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    row(glance.mode == .ready ? "DEP" : "BOARD",
                        glance.mode == .ready ? "NOW" : (glance.isBoarding ? "OPEN" : GlanceFormat.clock24(glance.start)))
                    Spacer(minLength: 0)
                    row("ETE", GlanceFormat.ete(glance.duration))
                    Spacer(minLength: 0)
                    row("CRS", GlanceFormat.degrees(glance.course), color: palette.magenta, last: true)
                }
            }
        }
        .foregroundStyle(palette.fg)
    }

    private func row(_ key: String, _ value: String, color: Color? = nil, hero: Bool = false,
                     last: Bool = false) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(key).font(.system(size: 9, weight: .semibold, design: .monospaced)).kerning(1.2)
                    .foregroundStyle(palette.dim)
                Spacer()
                Text(value)
                    .font(hero ? .system(size: 30, weight: .semibold, design: .rounded)
                               : .system(size: 15, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(color ?? palette.fg)
            }
            if !last { palette.rule.frame(height: 1) }
        }
    }

    // MARK: Lock Screen

    private var rectangular: some View {
        VStack(spacing: 5) {
            HeadingTape(heading: glance.course).frame(height: 30)
            HStack {
                Text(glance.isFlying ? "ETE \(GlanceFormat.ete(glance.end.timeIntervalSince(glance.now)))"
                                     : (glance.hasRoute ? glance.destination : "VOY"))
                Spacer()
                Text(glance.isFlying ? "\(glance.origin) › \(glance.destination)"
                                     : "ETE \(GlanceFormat.ete(glance.duration))")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12.5, weight: .bold, design: .monospaced))
            .monospacedDigit()
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            CompassRing(progress: glance.isFlying ? glance.progress : 0)
            VStack(spacing: 2) {
                if glance.isFlying {
                    Text("\(glance.minutesLeft)").font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("MIN").font(.system(size: 8.5, weight: .semibold, design: .monospaced)).kerning(0.9)
                        .foregroundStyle(.secondary)
                } else {
                    Text(GlanceFormat.degrees(glance.course)).font(.system(size: 14, weight: .bold, design: .monospaced))
                    Text(glance.hasRoute ? glance.destination : "VOY")
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced)).kerning(0.9)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .widgetAccentable()
    }
}

// MARK: - The dial

private struct HSIDial: View {
    var glance: FlightGlance
    var palette: HeadingWidget.Palette

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = s / 2 - 1
            let flying = glance.isFlying
            let crs = glance.course

            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                     with: .color(palette.face))
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                       with: .color(palette.ring), lineWidth: 1)
            let tickR = flying ? r - 6 : r - 2
            if flying {
                let rr = r - 2.5
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: 2 * rr, height: 2 * rr)),
                           with: .color(palette.ring), lineWidth: 3)
                var arc = Path()
                arc.addArc(center: c, radius: rr, startAngle: .degrees(-90),
                           endAngle: .degrees(-90 + 360 * glance.progress), clockwise: false)
                ctx.stroke(arc, with: .color(palette.progress), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }

            // Card, turned so the course is up.
            for d in stride(from: 0, to: 360, by: 5) {
                let len: CGFloat = d % 30 == 0 ? 7 : (d % 10 == 0 ? 4.5 : 2.5)
                var line = Path()
                line.move(to: pt(c, tickR, Double(d) - crs))
                line.addLine(to: pt(c, tickR - len, Double(d) - crs))
                ctx.stroke(line, with: .color(palette.tick.opacity(d % 10 == 0 ? 1 : 0.55)),
                           lineWidth: d % 30 == 0 ? 1.3 : 0.8)
            }
            let labels = [0: "N", 30: "3", 60: "6", 90: "E", 120: "12", 150: "15",
                          180: "S", 210: "21", 240: "24", 270: "W", 300: "30", 330: "33"]
            for (d, label) in labels {
                let cardinal = "NESW".contains(label)
                let a = Double(d) - crs
                let p = pt(c, tickR - 15, a)
                var inner = ctx
                inner.translateBy(x: p.x, y: p.y)
                inner.rotate(by: .degrees(a))
                inner.opacity = cardinal ? 1 : 0.7
                inner.draw(Text(label).font(.system(size: cardinal ? 9 : 8, weight: cardinal ? .bold : .semibold,
                                                    design: .monospaced))
                    .foregroundColor(palette.tick), at: .zero)
            }

            // Heading bug at the course (top, since the card is turned).
            var bug = Path()
            bug.move(to: pt(c, tickR + 0.5, -5)); bug.addLine(to: pt(c, tickR + 0.5, 5))
            bug.addLine(to: pt(c, tickR - 5, 3)); bug.addLine(to: pt(c, tickR - 5, -3)); bug.closeSubpath()
            ctx.fill(bug, with: .color(palette.magenta))

            // Course needle, broken around the centre text.
            let inner = s * 0.2, outer = tickR - 21
            for a in [0.0, 180.0] {
                var needle = Path()
                needle.move(to: pt(c, inner, a)); needle.addLine(to: pt(c, outer, a))
                ctx.stroke(needle, with: .color(palette.magenta), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            }
            var head = Path()
            head.move(to: pt(c, outer + 5, 0)); head.addLine(to: pt(c, outer - 1, -6))
            head.addLine(to: pt(c, outer - 1, 6)); head.closeSubpath()
            ctx.fill(head, with: .color(palette.magenta))

            // Lubber line, fixed at the top.
            let top = c.y - r + (flying ? 7 : 3)
            var lub = Path()
            lub.move(to: CGPoint(x: c.x - 4, y: top)); lub.addLine(to: CGPoint(x: c.x + 4, y: top))
            lub.addLine(to: CGPoint(x: c.x, y: top + 6)); lub.closeSubpath()
            ctx.fill(lub, with: .color(palette.amber))

            if flying {
                var plane = ctx
                plane.translateBy(x: c.x, y: c.y - s * 0.2 + 6)
                plane.rotate(by: .degrees(-90))
                plane.draw(Text(Image(systemName: "airplane")).font(.system(size: 11, weight: .bold))
                    .foregroundColor(palette.amber), at: .zero)
                ctx.draw(Text("\(glance.minutesLeft)").font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundColor(palette.fg), at: CGPoint(x: c.x, y: c.y + 2))
                ctx.draw(Text("MIN").font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(palette.dim), at: CGPoint(x: c.x, y: c.y + 20))
            } else {
                ctx.draw(Text(glance.hasRoute ? glance.destination : "VOY")
                    .font(.system(size: 18, weight: .bold)).foregroundColor(palette.fg),
                         at: CGPoint(x: c.x, y: c.y - 3))
                ctx.draw(Text(GlanceFormat.boardDuration(glance.duration).replacingOccurrences(of: "H", with: "H "))
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(palette.dim), at: CGPoint(x: c.x, y: c.y + 12))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Point at `radius` from `c`, `degrees` clockwise from straight up.
private func pt(_ c: CGPoint, _ radius: CGFloat, _ degrees: Double) -> CGPoint {
    let a = (degrees - 90) * .pi / 180
    return CGPoint(x: c.x + radius * cos(a), y: c.y + radius * sin(a))
}

/// The Lock Screen's heading tape: ticks every 5° either side of the course,
/// tens labelled, the course boxed above a pointer.
private struct HeadingTape: View {
    var heading: Double

    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 160, mid = size.width / 2
            let h = Int(heading.rounded())
            for d in (h - 22)...(h + 22) where d % 5 == 0 {
                let x = mid + CGFloat(d - h) * 3.6 * sx
                let tall = d % 10 == 0
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: 30)); tick.addLine(to: CGPoint(x: x, y: tall ? 20 : 24))
                ctx.stroke(tick, with: .color(.primary.opacity(tall ? 0.95 : 0.55)), lineWidth: tall ? 1.3 : 0.8)
                if tall {
                    ctx.draw(Text("\(((d % 360) + 360) % 360 / 10)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.6)), at: CGPoint(x: x, y: 11))
                }
            }
            let box = CGRect(x: mid - 16, y: 0, width: 32, height: 17)
            ctx.fill(Path(roundedRect: box, cornerRadius: 4), with: .color(.primary))
            var pointer = Path()
            pointer.move(to: CGPoint(x: mid - 4, y: 17)); pointer.addLine(to: CGPoint(x: mid + 4, y: 17))
            pointer.addLine(to: CGPoint(x: mid, y: 21)); pointer.closeSubpath()
            ctx.fill(pointer, with: .color(.primary))
            var knock = ctx
            knock.blendMode = .destinationOut
            knock.draw(Text(String(format: "%03d", ((h % 360) + 360) % 360))
                .font(.system(size: 10.5, weight: .bold, design: .monospaced)), at: CGPoint(x: mid, y: 8.5))
        }
        .compositingGroup()
    }
}

/// Thirty-six ticks round the circular accessory; lit up to the progress.
private struct CompassRing: View {
    var progress: Double

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 72
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            for d in stride(from: 0, to: 360, by: 10) {
                let on = progress > 0 && Double(d) < 360 * progress
                let big = d % 90 == 0
                var line = Path()
                line.move(to: pt(c, 33 * s, Double(d)))
                line.addLine(to: pt(c, (big ? 27 : 29.5) * s, Double(d)))
                ctx.stroke(line, with: .color(.primary.opacity(on ? 1 : (big ? 0.8 : 0.4))),
                           style: StrokeStyle(lineWidth: on || big ? 1.6 : 1, lineCap: .round))
            }
            if progress == 0 {
                var tri = Path()
                tri.move(to: CGPoint(x: c.x - 4 * s, y: c.y - 34 * s)); tri.addLine(to: CGPoint(x: c.x + 4 * s, y: c.y - 34 * s))
                tri.addLine(to: CGPoint(x: c.x, y: c.y - 28 * s)); tri.closeSubpath()
                ctx.fill(tri, with: .color(.primary))
            }
        }
    }
}
