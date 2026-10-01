import SwiftUI
import WidgetKit

/// Direction E, Horizon (`widget-concepts.html`, section `#horizon`): Apple
/// Weather's structure for a flight. The sky as the background (dusk before
/// takeoff, night in the air, the same in light and dark mode as Weather's
/// is), one huge thin number, and the flight laid out like an hourly
/// forecast. The strip shows the flight's phases at their times, since a
/// booked flight has no bags yet.
struct HorizonWidget: View {
    var glance: FlightGlance
    var family: WidgetFamily

    static let fg = Color.white
    static let dim = Color.white.opacity(0.78)
    static let faint = Color.white.opacity(0.4)

    static let dusk = LinearGradient(stops: [
        .init(color: hex(0x3B4FA0), location: 0),
        .init(color: hex(0x8D68B4), location: 0.58),
        .init(color: hex(0xF29A72), location: 1),
    ], startPoint: .top, endPoint: .bottom)

    static let night = LinearGradient(stops: [
        .init(color: hex(0x0A1230), location: 0),
        .init(color: hex(0x1A2766), location: 0.55),
        .init(color: hex(0x4B3F8E), location: 0.88),
        .init(color: hex(0xE0866A), location: 1),
    ], startPoint: .top, endPoint: .bottom)

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangular.containerBackground(for: .widget) { Color.clear }
        case .accessoryCircular:
            circular.containerBackground(for: .widget) { Color.clear }
        case .systemMedium:
            medium.containerBackground(for: .widget) { glance.isFlying ? Self.night : Self.dusk }
        default:
            small.containerBackground(for: .widget) { glance.isFlying ? Self.night : Self.dusk }
        }
    }

    // MARK: Pieces

    private var place: some View {
        Group {
            if glance.isFlying {
                Text(glance.city)
            } else if glance.hasRoute {
                HStack(spacing: 5) {
                    Text(glance.origin)
                    Plane(size: 10)
                    Text(glance.destination)
                }
            } else {
                Text("Voyage")
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .lineLimit(1)
    }

    /// "7:30 PM", "42 m", "25 m": the number huge and thin, the unit small.
    private func huge(_ size: CGFloat, unitSuffix: String = "") -> some View {
        let (number, unit): (String, String)
        switch glance.mode {
        case .scheduled:
            (number, unit) = GlanceFormat.clock(glance.start)
        case .flying:
            (number, unit) = minutes(glance.minutesLeft, suffix: unitSuffix)
        case .ready:
            (number, unit) = minutes(Int((glance.duration / 60).rounded()), suffix: "")
        }
        return HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(number).font(.system(size: size, weight: .light)).kerning(-size * 0.035)
            Text(unit).font(.system(size: 17, weight: .medium))
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func minutes(_ m: Int, suffix: String) -> (String, String) {
        m >= 60 ? ("\(m / 60):\(String(format: "%02d", m % 60))", "h" + suffix)
                : ("\(m)", "m" + suffix)
    }

    private var line1: String {
        switch glance.mode {
        case .scheduled(let boarding):
            return boarding ? "Now boarding" : "Boards · \(GlanceFormat.duration(glance.duration))"
        case .flying: return FlightGlance.phase(at: glance.progress)
        case .ready: return "Quick flight"
        }
    }

    private var line2: String {
        switch glance.mode {
        case .scheduled: return glance.flightNumber ?? glance.city
        case .flying: return "Lands \(GlanceFormat.clockText(glance.end))"
        case .ready: return "Tap to take off"
        }
    }

    // MARK: Small

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            place
            huge(46)
            Spacer(minLength: 0)
            if glance.isFlying {
                HorizonBar(progress: glance.progress, color: Self.fg, track: Self.faint)
                Text(line2).font(.system(size: 12, weight: .medium)).foregroundStyle(Self.dim)
                    .padding(.top, 4)
            } else {
                Text(line1).font(.system(size: 12, weight: .semibold))
                Text(line2).font(.system(size: 12, weight: .medium)).foregroundStyle(Self.dim)
            }
        }
        .foregroundStyle(Self.fg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Medium

    private var medium: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    place
                    huge(40, unitSuffix: " left")
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Image(systemName: glance.isFlying ? "airplane" : "airplane.departure")
                        .font(.system(size: 15, weight: .semibold))
                    Text(glance.isFlying ? line1 : (glance.mode == .ready ? "Quick flight" : "Boards"))
                        .font(.system(size: 12, weight: .semibold)).padding(.top, 4)
                    Text(mediumLine2).font(.system(size: 12, weight: .medium)).foregroundStyle(Self.dim)
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
            hours
        }
        .foregroundStyle(Self.fg)
    }

    private var mediumLine2: String {
        switch glance.mode {
        case .scheduled:
            return [GlanceFormat.duration(glance.duration), glance.flightNumber].compactMap { $0 }
                .joined(separator: " · ")
        case .flying: return "Lands \(GlanceFormat.clockText(glance.end))"
        case .ready: return "Tap to take off"
        }
    }

    /// Five columns like Weather's hourly row: takeoff, the three phases,
    /// landing, each at its time. In the air the passed ones dim and the
    /// current one reads "Now" on a light pill.
    private var hours: some View {
        let slots: [(String, String)] = [
            ("airplane.departure", "Takeoff"), ("arrow.up.right", "Climb"),
            ("airplane", "Cruise"), ("arrow.down.right", "Descent"), ("airplane.arrival", "Land"),
        ]
        let nowIndex = glance.isFlying ? min(3, max(1, Int((glance.progress * 4).rounded()))) : -1
        return HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                let time = glance.start.addingTimeInterval(glance.duration * Double(i) / 4)
                VStack(spacing: 5) {
                    Text(i == nowIndex ? "Now" : GlanceFormat.clock(time).0)
                        .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    Image(systemName: slots[i].0).font(.system(size: 13, weight: .semibold))
                    Text(slots[i].1).font(.system(size: 11, weight: .medium))
                        .foregroundStyle(i == nowIndex ? Self.fg : Self.dim)
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(i == nowIndex ? Color.white.opacity(0.16) : .clear,
                            in: RoundedRectangle(cornerRadius: 9))
                .opacity(nowIndex >= 0 && i < nowIndex ? 0.45 : 1)
            }
        }
    }

    // MARK: Lock Screen

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: glance.isFlying ? 5 : 2) {
            switch glance.mode {
            case .flying:
                (Text("\(glance.minutesLeft)m ").font(.system(size: 15, weight: .bold))
                 + Text("to \(glance.destination)").font(.system(size: 15, weight: .medium))
                    .foregroundColor(.secondary))
                HorizonBar(progress: glance.progress, color: .primary, track: .primary.opacity(0.3),
                           endpoints: false, height: 10)
                Text("Lands \(GlanceFormat.clockText(glance.end))")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            case .scheduled(let boarding):
                Text(boarding ? "Now boarding" : "Boards \(GlanceFormat.clockText(glance.start))")
                    .font(.system(size: 15, weight: .bold))
                Text("\(glance.origin) → \(glance.destination) · \(GlanceFormat.duration(glance.duration))")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                if let number = glance.flightNumber {
                    Text(number).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                }
            case .ready:
                Text("Quick flight · \(GlanceFormat.duration(glance.duration))")
                    .font(.system(size: 15, weight: .bold))
                if glance.hasRoute {
                    Text("\(glance.origin) → \(glance.destination)")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                }
                Text("Tap to take off")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The system's open gauge, as the mockup's ring is.
    private var circular: some View {
        Gauge(value: glance.progress) {
            EmptyView()
        } currentValueLabel: {
            if glance.isFlying {
                Text("\(glance.minutesLeft)").font(.system(size: 21, weight: .bold, design: .rounded))
            } else {
                VStack(spacing: 2) {
                    Image(systemName: "airplane.departure").font(.system(size: 11, weight: .bold))
                    Text(glance.mode == .ready ? GlanceFormat.duration(glance.duration)
                                               : GlanceFormat.clock(glance.start).0)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
    }
}

/// The thin progress line: origin dot, filled run, the plane at the current
/// fraction, hollow destination ring.
struct HorizonBar: View {
    var progress: Double
    var color: Color
    var track: Color
    var endpoints = true
    var height: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let x = w * progress
            let mid = geo.size.height / 2
            ZStack(alignment: .leading) {
                Capsule().fill(track).frame(height: 1.5).position(x: w / 2, y: mid)
                Capsule().fill(color).frame(width: max(0, x), height: 1.5).position(x: x / 2, y: mid)
                if endpoints {
                    Circle().fill(color).frame(width: 5, height: 5).position(x: 2.5, y: mid)
                    Circle().stroke(color, lineWidth: 1.3).frame(width: 5, height: 5).position(x: w - 2.5, y: mid)
                }
                Plane(size: 10).foregroundStyle(color).position(x: min(max(6, x), w - 6), y: mid)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

func hex(_ value: UInt32, _ alpha: Double = 1) -> Color {
    Color(.sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
          blue: Double(value & 0xFF) / 255, opacity: alpha)
}
