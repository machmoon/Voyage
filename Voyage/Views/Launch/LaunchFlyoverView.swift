import SwiftUI

/// The cold-launch flyover: the Voyage Classic swoops in over the launch
/// screen's navy, climbs to the centre, and flies at the camera. As it grows
/// its silhouette becomes a hole in the navy, so the traveler flies through
/// the aircraft into whatever screen is underneath.
///
/// The reveal follows RevealingSplashView, the open-source take on Twitter's
/// launch (`RevealingSplashView/Animations.swift`, `playTwitterAnimation` and
/// `playZoomOutAnimation`): a view matched to the launch screen sits over the
/// app, the mark gives a small anticipatory shrink, then scales up about 20x
/// while the cover fades and removes itself. Two changes here. The mark cuts
/// through the cover instead of sitting on it, because a white plane blown up
/// to 20x is a white flash over a dark globe. And it travels first, because
/// a plane that only scales reads as a logo, not a flight.
///
/// Staging matters more than the drawing. The first screen is a MapKit globe
/// whose first render holds up presentation for most of a second, on the
/// render server where the main thread cannot see it. Mounted under the
/// flyover from the start, that stall hid the whole flight behind the system
/// launch screen and only the zoom was ever seen. So the flight plays over
/// nothing, `onReadyForContent` asks the root to mount the first screen as the
/// plane levels off at the centre, and the zoom waits a beat. A slow first
/// render then costs a longer hover, not the flight. Home's own startup cover
/// (`StartupGlobeGate`) still hides the blank globe underneath.
///
/// It never gates the app. It plays once per process, runs 1.75 seconds (3.5
/// at the very most, see `FlyoverClock`), and passes every touch through.
/// Under Reduce Motion the plane holds still, the first screen mounts at once,
/// and the cover crossfades.
struct LaunchFlyoverView: View {
    let onReadyForContent: () -> Void
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = FlyoverClock()

    /// Once per process: returning to Home after a flight is not a launch.
    @MainActor private static var hasPlayed = false
    @MainActor static var shouldPlay: Bool { !hasPlayed }

    private static let planform = AircraftProfile.voyageClassic.planform
    /// The aircraft's length on screen at the start of the flight.
    private static let planeLength: CGFloat = 96

    // Timeline, in seconds.
    private static let flightEnd: Double = 0.9
    /// Level at the centre while the first screen mounts underneath.
    private static let zoomStart: Double = 1.3
    private static let total: Double = 1.75
    private static let reducedTotal: Double = 0.75

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = clock.advance(to: timeline.date)
            let duration = reduceMotion ? Self.reducedTotal : Self.total
            Canvas { context, size in
                if reduceMotion {
                    drawReduced(context: context, size: size, elapsed: elapsed)
                } else {
                    draw(context: context, size: size, elapsed: elapsed)
                }
            }
            .onChange(of: elapsed >= Self.flightEnd) { _, levelled in
                if levelled { readyForContent() }
            }
            .onChange(of: elapsed >= duration) { _, done in
                if done { finish() }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            Self.hasPlayed = true
            if reduceMotion { readyForContent() }
            // Backstop: if frames stop arriving altogether, get out of the way.
            try? await Task.sleep(for: .seconds(FlyoverClock.ceiling))
            readyForContent()
            finish()
        }
    }

    private func readyForContent() {
        guard !clock.contentRequested else { return }
        clock.contentRequested = true
        onReadyForContent()
    }

    private func finish() {
        guard !clock.finished else { return }
        clock.finished = true
        onFinish()
    }

    // MARK: Motion

    /// A swoop: in from the left heading down and across, bottoming out
    /// under the centre, and climbing straight up to the middle of the screen.
    private func flightPath(in size: CGSize) -> [CGPoint] {
        [CGPoint(x: -0.2 * size.width, y: 0.64 * size.height),
         CGPoint(x: 0.42 * size.width, y: 0.98 * size.height),
         CGPoint(x: 0.5 * size.width, y: 0.7 * size.height),
         CGPoint(x: 0.5 * size.width, y: 0.47 * size.height)]
    }

    private func bezier(_ p: [CGPoint], _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return CGPoint(x: a * p[0].x + b * p[1].x + c * p[2].x + d * p[3].x,
                       y: a * p[0].y + b * p[1].y + c * p[2].y + d * p[3].y)
    }

    /// Heading in radians, with the plane's nose drawn pointing up.
    private func heading(_ p: [CGPoint], _ t: CGFloat) -> CGFloat {
        let ahead = bezier(p, min(1, t + 0.01))
        let behind = bezier(p, max(0, t - 0.01))
        return atan2(ahead.y - behind.y, ahead.x - behind.x) + .pi / 2
    }

    private func easeInOut(_ x: Double) -> CGFloat {
        let x = min(max(x, 0), 1)
        return CGFloat(x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2)
    }

    private func progress(_ elapsed: Double, from: Double, to: Double) -> Double {
        min(max((elapsed - from) / (to - from), 0), 1)
    }

    // MARK: Drawing

    private func draw(context: GraphicsContext, size: CGSize, elapsed: Double) {
        let path = flightPath(in: size)
        let t = easeInOut(elapsed / Self.flightEnd)
        let position = bezier(path, t)
        let angle = heading(path, t)

        // Bank into the turn: roll follows how fast the heading is changing,
        // and a rolled wing is a foreshortened wing.
        let turnRate = heading(path, min(1, t + 0.04)) - angle
        let roll = min(abs(turnRate) * 6, 0.6)
        let wingScale = cos(roll)

        // RevealingSplashView's anticipation: a small settle before the zoom.
        let settle = progress(elapsed, from: Self.flightEnd, to: Self.zoomStart)
        let zoom = progress(elapsed, from: Self.zoomStart, to: Self.total)
        let scale = (1 - 0.1 * sin(settle * .pi)) * (1 + 19 * CGFloat(pow(zoom, 2.6)))

        // The cover fades through the second half of the zoom; the white plane
        // fades early, so what grows is a window onto the app, not a flash.
        let coverOpacity = 1 - progress(elapsed, from: Self.zoomStart + 0.15, to: Self.total)
        let planeOpacity = 1 - progress(elapsed, from: Self.zoomStart, to: Self.zoomStart + 0.18)

        var cover = context
        cover.opacity = coverOpacity
        cover.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color("LaunchBackground")))

        drawContrail(context: context, path: path, t: t, opacity: planeOpacity * coverOpacity)

        var plane = context
        plane.translateBy(x: position.x, y: position.y)
        plane.rotate(by: .radians(angle))
        plane.scaleBy(x: wingScale * scale, y: scale)

        var hole = plane
        hole.blendMode = .destinationOut
        fillSilhouette(hole, color: .white)

        var aircraft = plane
        aircraft.opacity = planeOpacity
        fillSilhouette(aircraft, color: .white)
        fillGlazing(aircraft)
    }

    /// A short, thin trail behind the plane that thins out toward its end.
    private func drawContrail(context: GraphicsContext, path: [CGPoint], t: CGFloat, opacity: Double) {
        guard opacity > 0, t > 0.02 else { return }
        let steps = 14
        let length: CGFloat = 0.3
        for i in 0..<steps {
            let a = max(0, t - length * CGFloat(steps - i) / CGFloat(steps))
            let b = max(0, t - length * CGFloat(steps - i - 1) / CGFloat(steps) - 0.02)
            guard b > a else { continue }
            var segment = Path()
            segment.move(to: bezier(path, a))
            segment.addLine(to: bezier(path, b))
            let fade = Double(i + 1) / Double(steps)
            context.stroke(segment, with: .color(.white.opacity(0.22 * fade * opacity)),
                           style: StrokeStyle(lineWidth: 1 + 1.5 * fade, lineCap: .round))
        }
    }

    private func drawReduced(context: GraphicsContext, size: CGSize, elapsed: Double) {
        let fade = 1 - progress(elapsed, from: 0.4, to: Self.reducedTotal)
        var cover = context
        cover.opacity = fade
        cover.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color("LaunchBackground")))

        var plane = context
        plane.opacity = fade
        plane.translateBy(x: size.width / 2, y: size.height * 0.47)
        fillSilhouette(plane, color: .white)
        fillGlazing(plane)
    }

    // MARK: Aircraft

    /// The aircraft centred on its wing, nose up, at unit zoom.
    private static let outline: AirframeOutline = {
        let scale = planeLength / CGFloat(planform.length)
        return AirframeOutline(planform: planform, scale: scale, midX: 0,
                               noseTipY: -CGFloat(planform.exitStation) * scale)
    }()

    private func fillSilhouette(_ context: GraphicsContext, color: Color) {
        for part in Self.outline.silhouetteParts {
            context.fill(part, with: .color(color))
        }
        context.fill(Self.outline.fin, with: .color(color))
    }

    private func fillGlazing(_ context: GraphicsContext) {
        var glazing = context
        glazing.clip(to: Self.outline.fuselage)
        for pane in Self.outline.windshield {
            glazing.fill(pane, with: .color(Color("LaunchBackground")))
        }
    }
}

/// Animation time for the flyover, advanced per frame with each step capped.
///
/// Launch work on the main thread (opening the logbook store, building the
/// first screen) can skip frames. A wall-clock timeline comes out of a hitch
/// further along than the traveler saw; capping each step at two frames means
/// a hitch pauses the plane where it is instead. `ceiling` bounds the real
/// time the whole thing can take.
@MainActor
final class FlyoverClock {
    static let maxStep: TimeInterval = 1.0 / 30
    static let ceiling: TimeInterval = 3.5

    private var last: Date?
    private(set) var elapsed: TimeInterval = 0
    var contentRequested = false
    var finished = false

    /// Advances to `date` and returns the animation time. Safe to call more
    /// than once for the same frame.
    func advance(to date: Date) -> TimeInterval {
        if let last, date > last {
            elapsed += min(date.timeIntervalSince(last), Self.maxStep)
        }
        if last.map({ date > $0 }) ?? true { last = date }
        return elapsed
    }
}
