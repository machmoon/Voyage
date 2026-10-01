import SwiftUI

/// What the Live Activity draws, as plain values. The views below take this
/// rather than an `ActivityViewContext`, which nothing outside the system can
/// construct; that is what lets `VoyageWidgetsTests` render every presentation
/// to a PNG. Same split as apple/sample-food-truck
/// `Widgets/TruckActivityWidget.swift`, whose `LiveActivityView`,
/// `OrderTimerView` and `ExpandedTrailingView` take `orderNumber` and a
/// `timerRange` instead of the context.
struct FlightCard: Equatable {
    enum Status: Equatable {
        /// In the air or in the lounge, counting down to `arrival`.
        case live
        /// Backgrounded mid-flight: counting down to the diversion instead.
        case returning(deadline: Date)
        /// The app closed the flight out on landing.
        case landed
        /// Diverted, abandoned, or simply past its stale date with nobody
        /// awake to say so (`context.isStale`).
        case ended
    }

    var origin: String
    var destination: String
    var caption: String
    var departure: Date
    var arrival: Date
    var legNumber: Int
    var legCount: Int
    var status: Status

    init(origin: String, destination: String, caption: String,
         departure: Date, arrival: Date, legNumber: Int = 1, legCount: Int = 1,
         status: Status) {
        self.origin = origin
        self.destination = destination
        self.caption = caption
        self.departure = departure
        self.arrival = arrival
        self.legNumber = legNumber
        self.legCount = legCount
        self.status = status
    }

    /// The truth rules carried over from the previous card: a card past its
    /// stale date is over even if the app never said so (Voyage has no
    /// background modes, so a suspended session cannot send a final update;
    /// duckduckgo/apple-browsers `iOS/DuckDuckGo/VPNSnoozeLiveActivityWidget.swift`
    /// draws from `context.isStale` the same way), and only a flight the app
    /// actually closed out gets the "landed" look.
    init(attributes: FlightActivityAttributes,
         state: FlightActivityAttributes.ContentState,
         isStale: Bool,
         now: Date = .now) {
        let status: Status
        if state.concluded {
            status = state.phaseSymbol == "airplane.arrival" ? .landed : .ended
        } else if isStale {
            status = .ended
        } else if let grace = state.graceDeadline, grace > now {
            status = .returning(deadline: grace)
        } else {
            status = .live
        }
        let caption: String
        switch status {
        case .ended where !state.concluded: caption = "Flight ended"
        case .returning: caption = "Return to Voyage"
        default: caption = state.phaseCaption
        }
        self.init(origin: attributes.originCode,
                  destination: attributes.destinationCode,
                  caption: caption,
                  departure: state.departure,
                  arrival: state.arrival,
                  legNumber: state.legNumber,
                  legCount: state.legCount,
                  status: status)
    }

    var isOver: Bool { status == .landed || status == .ended }

    /// "Cruise · deep work", plus the leg when there is a connection.
    var captionLine: String {
        guard legCount > 1, !isOver else { return caption }
        return "\(caption) · Leg \(legNumber) of \(legCount)"
    }

    var progressRange: ClosedRange<Date> {
        departure...max(departure.addingTimeInterval(1), arrival)
    }

    /// What the countdown counts to: the diversion while backgrounded,
    /// otherwise this leg's arrival (or the lounge's boarding call).
    var countdownRange: ClosedRange<Date> {
        let end: Date
        if case .returning(let deadline) = status { end = deadline } else { end = arrival }
        let now = Date.now
        return now...max(now, end)
    }

    var tint: Color {
        if case .returning = status { return WidgetTheme.destructive }
        return WidgetTheme.accent
    }

    /// The single glyph for the compact island and the minimal view.
    var glyph: String {
        switch status {
        case .live: return "airplane"
        case .returning: return "exclamationmark.circle.fill"
        case .landed: return "checkmark.seal.fill"
        case .ended: return "xmark.circle"
        }
    }
}

// MARK: - Pieces
//
// Built on the Horizon widget style (`Styles/HorizonWidget.swift`), as the
// concepts sheet recommends for the Live Activity: the night sky, one huge
// thin countdown, one thin progress line with the plane on it. The look
// Flighty has trained people to read on a lock screen.

/// Set only by the snapshot tests. `ImageRenderer` cannot draw a timer-driven
/// `ProgressView(timerInterval:)` (it renders a placeholder), so renders draw
/// the same bar at the fraction it has right now. WidgetKit never sets this.
private struct FrozenTimelineKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var frozenTimeline: Bool {
        get { self[FrozenTimelineKey.self] }
        set { self[FrozenTimelineKey.self] = newValue }
    }
}

extension FlightCard {
    var fractionNow: Double {
        if isOver { return 1 }
        let total = progressRange.upperBound.timeIntervalSince(progressRange.lowerBound)
        return min(1, max(0, Date.now.timeIntervalSince(departure) / total))
    }

    /// White in the air (Horizon's ink), red while backgrounded.
    var ink: Color {
        status.isReturning ? WidgetTheme.destructive : .white
    }
}

/// The live countdown. `Text(timerInterval:)` ticks on its own, so the app
/// only has to send an update when the phase changes.
struct FlightCountdown: View {
    var card: FlightCard
    var size: CGFloat
    var weight: Font.Weight = .semibold

    var body: some View {
        Group {
            switch card.status {
            case .landed:
                Text("Landed")
            case .ended:
                Text("Ended").foregroundStyle(HorizonWidget.dim)
            case .live, .returning:
                Text(timerInterval: card.countdownRange, countsDown: true)
                    .monospacedDigit()
                    .foregroundStyle(card.ink)
            }
        }
        .font(.system(size: size, weight: weight))
        .kerning(weight == .light ? -size * 0.03 : 0)
        .lineLimit(1)
    }
}

/// Horizon's line: origin dot, a live fill (`ProgressView(timerInterval:)`,
/// which advances between updates), hollow destination ring. The plane sits
/// at the fraction the last update carried. WidgetKit cannot move a view on
/// a timer, but the in-flight card is only on screen once the app has gone
/// to the background, and that transition is itself an update
/// (`FlightSession.handleScenePhase`), so the plane is where the flight is.
struct RouteLine: View {
    var card: FlightCard
    @Environment(\.frozenTimeline) private var frozen

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, mid = geo.size.height / 2
            let x = w * card.fractionNow
            ZStack {
                if card.isOver || frozen {
                    // Drawn, not a ProgressView: nothing moves, and a linear
                    // ProgressView is UIKit-backed, which ImageRenderer cannot draw.
                    Capsule().fill(.white.opacity(0.4)).frame(width: w - 10, height: 2)
                        .position(x: w / 2, y: mid)
                    Capsule().fill(card.ink).frame(width: max(0, (w - 10) * card.fractionNow), height: 2)
                        .position(x: 5 + (w - 10) * card.fractionNow / 2, y: mid)
                } else {
                    ProgressView(timerInterval: card.progressRange, countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .progressViewStyle(.linear)
                    .tint(card.ink)
                    .scaleEffect(x: 1, y: 0.5)
                    .frame(width: w - 10)
                    .position(x: w / 2, y: mid)
                }
                Circle().fill(.white).frame(width: 5, height: 5).position(x: 2.5, y: mid)
                Circle().stroke(.white, lineWidth: 1.3).frame(width: 5, height: 5).position(x: w - 2.5, y: mid)
                Plane(size: 12).foregroundStyle(card.ink).position(x: min(max(8, x), w - 8), y: mid)
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}

private struct Place: View {
    var card: FlightCard
    var body: some View {
        HStack(spacing: 5) {
            Text(card.origin)
            Plane(size: 10)
            Text(card.destination)
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.white)
    }
}

private struct Caption: View {
    var card: FlightCard
    var size: CGFloat
    var body: some View {
        Text(card.captionLine)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(card.status.isReturning ? WidgetTheme.destructive : HorizonWidget.dim)
            .lineLimit(1)
    }
}

/// "Lands 8:55 PM", or how it ended.
private struct Arrival: View {
    var card: FlightCard
    var body: some View {
        Group {
            switch card.status {
            case .live: Text("Lands \(GlanceFormat.clockText(card.arrival))")
            case .returning: Text("Diverts when this reaches zero")
            case .landed, .ended: Text(card.caption)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(HorizonWidget.dim)
        .lineLimit(1)
    }
}

// MARK: - Lock screen

/// Horizon on the lock screen: SFO ✈ JFK and the phase, the countdown huge
/// and thin, the line, the arrival.
struct FlightLockScreenView: View {
    var card: FlightCard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Place(card: card)
                Spacer(minLength: 8)
                if card.status != .landed && card.status != .ended { Caption(card: card, size: 13) }
            }
            FlightCountdown(card: card, size: 44, weight: .light)
                .foregroundStyle(.white)
            RouteLine(card: card)
            Arrival(card: card)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(HorizonWidget.night)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Dynamic Island

struct FlightIslandPlace: View {
    var card: FlightCard
    var body: some View { Place(card: card).padding(.leading, 6) }
}

struct FlightIslandCaption: View {
    var card: FlightCard
    var body: some View { Caption(card: card, size: 13).padding(.trailing, 6) }
}

/// The expanded island's bottom region: the countdown and the arrival on one
/// line, then the route line.
struct FlightIslandBottom: View {
    var card: FlightCard
    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .lastTextBaseline) {
                FlightCountdown(card: card, size: 34, weight: .light).foregroundStyle(.white)
                Spacer(minLength: 8)
                Arrival(card: card)
            }
            RouteLine(card: card)
        }
        .padding(.horizontal, 6)
    }
}

/// Compact leading: the plane, or the warning while backgrounded.
struct FlightIslandGlyph: View {
    var card: FlightCard
    var body: some View {
        Image(systemName: card.glyph)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(card.status == .ended ? HorizonWidget.dim : card.ink)
    }
}

/// Minimal: a ring that fills over the leg, plane inside.
struct FlightIslandMinimal: View {
    var card: FlightCard
    @Environment(\.frozenTimeline) private var frozen
    var body: some View {
        if card.isOver {
            FlightIslandGlyph(card: card)
        } else if frozen {
            ZStack {
                Circle().stroke(card.ink.opacity(0.3), lineWidth: 3)
                Circle().trim(from: 0, to: card.fractionNow)
                    .stroke(card.ink, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Plane(size: 9).foregroundStyle(card.ink)
            }
        } else {
            ProgressView(timerInterval: card.progressRange, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                Plane(size: 9).foregroundStyle(card.ink)
            }
            .progressViewStyle(.circular)
            .tint(card.ink)
        }
    }
}

extension FlightCard.Status {
    var isReturning: Bool {
        if case .returning = self { return true }
        return false
    }
}
