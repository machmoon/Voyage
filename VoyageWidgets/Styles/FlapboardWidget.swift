import SwiftUI
import WidgetKit

/// Direction A, Flapboard (`widget-concepts.html`, `#flapboard`): the gate's
/// departure board. Destination or minutes on split flaps, status in amber or
/// green, a slat bar for progress. A real board is black in any light, so
/// this one is too.
struct FlapboardWidget: View {
    var glance: FlightGlance
    var family: WidgetFamily

    static let bg = hex(0x0A0B0E)
    static let flapTop = hex(0x26292F)
    static let flapBottom = hex(0x1B1D22)
    static let char = hex(0xF3F0E6)
    static let dim = hex(0x7E838D)
    static let amber = hex(0xFFB938)
    static let green = hex(0x62E08A)
    static let hinge = hex(0x050506)

    static var background: some View {
        RadialGradient(colors: [hex(0x15171C), bg], center: UnitPoint(x: 0.5, y: 0),
                       startRadius: 0, endRadius: 190)
    }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangular.containerBackground(for: .widget) { Color.clear }
        case .accessoryCircular:
            circular.containerBackground(for: .widget) { Color.clear }
        case .systemMedium:
            medium.containerBackground(for: .widget) { Self.background }
                .environment(\.colorScheme, .dark)
        default:
            small.containerBackground(for: .widget) { Self.background }
                .environment(\.colorScheme, .dark)
        }
    }

    // MARK: Pieces

    private func label(_ text: String, _ color: Color = dim) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .kerning(1.2)
            .foregroundStyle(color)
            .lineLimit(1)
    }

    private var status: some View {
        HStack(spacing: 5) {
            switch glance.mode {
            case .flying:
                Circle().fill(Self.amber).frame(width: 6, height: 6)
                label("En route", Self.amber)
            case .scheduled(let boarding):
                label(boarding ? "Boarding" : "On time", boarding ? Self.amber : Self.green)
            case .ready:
                label("Ready", Self.green)
            }
        }
    }

    private func field(_ key: String, _ value: String, _ color: Color = char) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(key.uppercased())
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .kerning(1).foregroundStyle(Self.dim)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .monospaced)).monospacedDigit()
                .foregroundStyle(color)
        }
        .lineLimit(1)
    }

    private var destinationFlaps: String { glance.hasRoute ? glance.destination : "VOY" }

    private var departs: (String, String, Color) {
        switch glance.mode {
        case .scheduled(let boarding):
            return ("Boards", boarding ? "NOW" : GlanceFormat.clock24(glance.start), Self.amber)
        default:
            return ("Departs", "NOW", Self.amber)
        }
    }

    // MARK: Small

    @ViewBuilder
    private var small: some View {
        if glance.isFlying {
            VStack(alignment: .leading, spacing: 0) {
                HStack { label("› \(glance.destination)"); Spacer(minLength: 4); status.layoutPriority(1) }
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 7) {
                    Flaps(text: String(min(99, glance.minutesLeft)), size: .regular)
                    VStack(alignment: .leading, spacing: 1) {
                        label(glance.minutesLeft > 99 ? "min+" : "min", Self.char)
                        label("left")
                    }
                    .padding(.bottom, 4)
                }
                Spacer(minLength: 0)
                Slats(count: 12, on: Int((glance.progress * 12).rounded()))
                HStack {
                    label(glance.seat.map { "Seat \($0)" } ?? glance.origin)
                    Spacer()
                    label("Arr \(GlanceFormat.clock24(glance.end))")
                }
                .padding(.top, 6)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack { label("\(glance.origin) ›"); Spacer(); status }
                Spacer(minLength: 0)
                Flaps(text: destinationFlaps, size: .regular)
                Spacer(minLength: 0)
                HStack(spacing: 18) {
                    field(departs.0, departs.1, glance.isBoarding ? Self.amber : Self.char)
                    field("Flight", GlanceFormat.boardDuration(glance.duration))
                }
            }
        }
    }

    // MARK: Medium

    @ViewBuilder
    private var medium: some View {
        if glance.isFlying {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    label(["\(glance.origin) › \(glance.destination)", glance.seat].compactMap { $0 }
                        .joined(separator: " · "))
                    Spacer(); status
                }
                Spacer(minLength: 0)
                HStack(spacing: 14) {
                    Flaps(text: GlanceFormat.ete(glance.end.timeIntervalSince(glance.now)), size: .medium)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(glance.city).font(.system(size: 17, weight: .bold))
                        Text("\(FlightGlance.phase(at: glance.progress)) · lands \(GlanceFormat.clock24(glance.end))")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Self.dim)
                    }
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
                Slats(count: 24, on: Int((glance.progress * 24).rounded()))
                HStack {
                    label(glance.origin); Spacer()
                    label("\(glance.minutesFlown)m flown"); Spacer()
                    label(glance.destination)
                }
                .padding(.top, 6)
            }
            .foregroundStyle(Self.char)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack { label("Departures · \(glance.hasRoute ? glance.origin : "Voyage")"); Spacer(); status }
                Spacer(minLength: 0)
                HStack(spacing: 14) {
                    Flaps(text: destinationFlaps, size: .regular)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(glance.mode == .ready ? "Quick flight" : glance.city)
                            .font(.system(size: 17, weight: .bold))
                        Text(glance.mode == .ready ? "\(glance.city) · tap to board" : (glance.flightNumber ?? ""))
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Self.dim)
                    }
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
                HStack {
                    field(departs.0, departs.1, Self.amber)
                    Spacer()
                    field("Flight", GlanceFormat.boardDuration(glance.duration))
                    Spacer()
                    field("No.", glance.flightNumber.map { $0.replacingOccurrences(of: "VOY ", with: "") } ?? "—")
                    Spacer()
                    field("Arrives", GlanceFormat.clock24(glance.end))
                }
            }
            .foregroundStyle(Self.char)
        }
    }

    // MARK: Lock Screen

    @ViewBuilder
    private var rectangular: some View {
        if glance.isFlying {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    LockFlaps(text: String(min(99, glance.minutesLeft)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("MIN").foregroundStyle(.primary)
                        Text("TO \(glance.destination)").foregroundStyle(.secondary)
                    }
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
                LockSlats(count: 12, on: Int((glance.progress * 12).rounded()))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 10) {
                LockFlaps(text: destinationFlaps)
                VStack(alignment: .leading, spacing: 3) {
                    Text(departs.1).font(.system(size: 18, weight: .bold, design: .monospaced)).monospacedDigit()
                    Text(departs.0.uppercased())
                        .font(.system(size: 11, weight: .medium, design: .monospaced)).kerning(0.9)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if glance.isFlying {
                SlatRing(on: Int((glance.progress * 12).rounded()))
                Text("\(min(99, glance.minutesLeft))")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
            } else {
                VStack(spacing: 4) {
                    Text(destinationFlaps).font(.system(size: 15, weight: .bold, design: .monospaced))
                    Text(departs.1).font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .widgetAccentable()
    }
}

// MARK: - Flaps

/// Split-flap characters: two-tone halves, a hinge line, side notches. A
/// colon is drawn bare, as on a real board.
struct Flaps: View {
    enum Size {
        case regular, medium
        var metrics: (w: CGFloat, h: CGFloat, font: CGFloat) {
            switch self {
            case .regular: return (34, 44, 30)
            case .medium: return (30, 40, 27)
            }
        }
    }

    var text: String
    var size: Size

    var body: some View {
        let m = size.metrics
        HStack(spacing: 3) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                if ch == ":" {
                    Text(":").font(.system(size: m.font, weight: .bold))
                        .foregroundStyle(FlapboardWidget.char).frame(width: 12, height: m.h)
                } else {
                    Flap(character: String(ch), width: m.w, height: m.h, font: m.font)
                }
            }
        }
    }
}

private struct Flap: View {
    var character: String
    var width: CGFloat
    var height: CGFloat
    var font: CGFloat

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                FlapboardWidget.flapTop
                FlapboardWidget.flapBottom
            }
            Text(character)
                .font(.system(size: font, weight: .bold))
                .foregroundStyle(FlapboardWidget.char)
            FlapboardWidget.hinge.opacity(0.9).frame(height: 1)
            HStack {
                FlapboardWidget.hinge.frame(width: 2, height: 6)
                Spacer()
                FlapboardWidget.hinge.frame(width: 2, height: 6)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 3.5))
        .overlay(alignment: .top) { Color.white.opacity(0.07).frame(height: 1) }
        .shadow(color: .black.opacity(0.7), radius: 0.5, y: 1)
    }
}

/// The progress slats: amber when passed.
struct Slats: View {
    var count: Int
    var on: Int
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i < on ? FlapboardWidget.amber : FlapboardWidget.flapTop)
                    .frame(height: 7)
                    .shadow(color: i < on ? FlapboardWidget.amber.opacity(0.35) : .clear, radius: 3)
            }
        }
    }
}

/// Lock Screen flaps: vibrant, so only shape and opacity carry them.
private struct LockFlaps: View {
    var text: String
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                ZStack {
                    RoundedRectangle(cornerRadius: 3).fill(.primary.opacity(0.14))
                    Text(String(ch)).font(.system(size: 18, weight: .bold))
                    Rectangle().fill(.black.opacity(0.35)).frame(height: 1)
                }
                .frame(width: 21, height: 27)
            }
        }
    }
}

private struct LockSlats: View {
    var count: Int
    var on: Int
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(.primary.opacity(i < on ? 1 : 0.26))
                    .frame(height: 5)
            }
        }
    }
}

/// Twelve slats round the circular accessory, lit as the flight progresses.
private struct SlatRing: View {
    var on: Int
    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                ForEach(0..<12, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.primary.opacity(i < on ? 1 : 0.28))
                        .frame(width: side * 4 / 72, height: side * 8 / 72)
                        .offset(y: -side * 28 / 72)
                        .rotationEffect(.degrees(Double(i) * 30))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
