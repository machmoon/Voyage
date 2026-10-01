import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Style choice

/// The four looks a person can pick from "Edit Widget" (Pat, 2026-10-01:
/// Flapboard, Orbit, Heading and Horizon from `widget-concepts.html`; Stub was
/// dropped). Horizon is the default.
enum VoyageWidgetStyle: String, AppEnum {
    case horizon, flapboard, orbit, heading

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Style"
    static var caseDisplayRepresentations: [VoyageWidgetStyle: DisplayRepresentation] = [
        .horizon: "Horizon",
        .flapboard: "Flapboard",
        .orbit: "Orbit",
        .heading: "Heading",
    ]
}

/// The widget's configuration. Same shape as apple/sample-backyard-birds
/// `Widgets/Backyard/BackyardWidgetIntent.swift` (a `WidgetConfigurationIntent`
/// whose `@Parameter` is an `AppEnum` with a default), which that sample feeds
/// to `AppIntentConfiguration` in `BackyardWidget.swift`.
struct NextFlightConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Voyage"
    static var description = IntentDescription("Your next flight, or the one you are on.")

    @Parameter(title: "Style", default: .horizon)
    var style: VoyageWidgetStyle

    init() {}
    init(style: VoyageWidgetStyle) { self.style = style }
}

// MARK: - Entry

/// One timeline entry: the snapshot the app wrote, read at `date`.
struct NextFlightEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot
    var style: VoyageWidgetStyle = .horizon

    /// What the widget is about at `date`, in order of precedence: the flight
    /// in the air, the booked flight until its boarding window closes (when
    /// `FlightScheduler.pruneExpired` would drop it too), else the quick route.
    var glance: FlightGlance {
        if let leg = snapshot.active, date < leg.arrival {
            let total = max(1, leg.arrival.timeIntervalSince(leg.departure))
            return FlightGlance(mode: .flying, origin: leg.originCode, destination: leg.destinationCode,
                                city: leg.destinationCity, start: leg.departure, end: leg.arrival,
                                duration: total, flightNumber: nil, seat: leg.seat, bags: leg.bags,
                                course: leg.courseDegrees ?? 0, now: date)
        }
        if let leg = snapshot.scheduled, date < leg.boardingCloses {
            let duration = leg.duration ?? 0
            return FlightGlance(mode: .scheduled(boarding: date >= leg.boardingOpens),
                                origin: leg.originCode, destination: leg.destinationCode,
                                city: leg.destinationCity, start: leg.departure,
                                end: leg.departure.addingTimeInterval(duration), duration: duration,
                                flightNumber: leg.flightNumber, seat: nil, bags: nil,
                                course: leg.courseDegrees ?? 0, now: date)
        }
        let route = snapshot.quickRoute
        let duration = route?.duration ?? 25 * 60
        return FlightGlance(mode: .ready, origin: route?.originCode ?? "", destination: route?.destinationCode ?? "",
                            city: route?.destinationCity ?? "", start: date,
                            end: date.addingTimeInterval(duration), duration: duration,
                            flightNumber: nil, seat: nil, bags: nil,
                            course: route?.courseDegrees ?? 0, now: date)
    }
}

/// Everything any style draws, as plain values. A style is a drawing of this
/// and nothing else, so adding or restyling one never touches the data path.
struct FlightGlance: Equatable {
    enum Mode: Equatable {
        /// Nothing booked: a quick flight on the usual route; a tap takes off.
        case ready
        /// Booked for later; `boarding` once its window opens.
        case scheduled(boarding: Bool)
        /// In the air.
        case flying
    }

    var mode: Mode
    var origin: String
    var destination: String
    var city: String
    /// Boarding time (scheduled), takeoff (flying), now (ready).
    var start: Date
    /// Arrival.
    var end: Date
    var duration: TimeInterval
    var flightNumber: String?
    var seat: String?
    var bags: Int?
    /// Initial course, degrees true.
    var course: Double
    var now: Date

    var hasRoute: Bool { !origin.isEmpty && !destination.isEmpty }
    var isFlying: Bool { mode == .flying }
    var isBoarding: Bool { mode == .scheduled(boarding: true) }
    var tapDeparts: Bool { mode == .ready }

    var progress: Double {
        guard isFlying else { return 0 }
        return min(1, max(0, now.timeIntervalSince(start) / max(1, duration)))
    }

    var minutesLeft: Int {
        max(0, Int((end.timeIntervalSince(now) / 60).rounded(.up)))
    }

    var minutesFlown: Int {
        max(0, Int((now.timeIntervalSince(start) / 60).rounded(.down)))
    }

    /// The phase name for a moment in the flight, by fraction.
    static func phase(at fraction: Double) -> String {
        switch fraction {
        case ..<0.12: return "Climbing"
        case ..<0.85: return "Cruise"
        default: return "Descending"
        }
    }
}

// MARK: - Formatting

enum GlanceFormat {
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }
    private static let h12 = formatter("h:mm")
    private static let ampm = formatter("a")
    private static let h24 = formatter("HH:mm")

    /// ("7:30", "PM")
    static func clock(_ date: Date) -> (String, String) { (h12.string(from: date), ampm.string(from: date)) }
    static func clockText(_ date: Date) -> String { "\(h12.string(from: date)) \(ampm.string(from: date))" }
    /// "19:30", the board's 24-hour clock.
    static func clock24(_ date: Date) -> String { h24.string(from: date) }

    /// "25m", "1h 25m", "2h".
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        let h = minutes / 60, m = minutes % 60
        switch (h, m) {
        case (0, _): return "\(m)m"
        case (_, 0): return "\(h)h"
        default: return "\(h)h \(m)m"
        }
    }

    /// "1:25", the instrument's elapsed-time format.
    static func ete(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    /// "1H25", the board's.
    static func boardDuration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        return String(format: "%dH%02d", minutes / 60, minutes % 60)
    }

    static func degrees(_ value: Double) -> String {
        String(format: "%03.0f°", (value.rounded()).truncatingRemainder(dividingBy: 360))
    }
}

// MARK: - Dispatcher

/// The Home Screen and Lock Screen widget: picks the style, then the family.
/// Takes the family as a value (that environment value cannot be set from
/// outside WidgetKit) so the snapshot tests can render every family.
struct NextFlightWidgetView: View {
    var entry: NextFlightEntry
    var family: WidgetFamily

    var body: some View {
        let glance = entry.glance
        tappable(glance) {
            switch entry.style {
            case .horizon: HorizonWidget(glance: glance, family: family)
            case .flapboard: FlapboardWidget(glance: glance, family: family)
            case .orbit: OrbitWidget(glance: glance, family: family)
            case .heading: HeadingWidget(glance: glance, family: family)
            }
        }
    }

    /// Ready: the whole widget is `Button(intent: TakeOffIntent())`. Booked or
    /// in flight: no button, so the system's default tap opens the app, which
    /// shows the booked flight's banner or the flight in progress.
    @ViewBuilder
    private func tappable(_ glance: FlightGlance, @ViewBuilder content: () -> some View) -> some View {
        if glance.tapDeparts {
            Button(intent: TakeOffIntent()) {
                content().contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Take off")
        } else {
            content()
        }
    }
}

extension WidgetFamily {
    var isAccessory: Bool { self == .accessoryCircular || self == .accessoryRectangular }
}

/// The SF Symbol airplane points east; turn it to a heading in degrees
/// clockwise from east.
struct Plane: View {
    var size: CGFloat
    var angle: Double = 0
    var body: some View {
        Image(systemName: "airplane")
            .font(.system(size: size, weight: .bold))
            .rotationEffect(.degrees(angle))
    }
}
