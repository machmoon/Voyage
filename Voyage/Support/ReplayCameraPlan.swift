import Foundation

/// Camera policy for the logbook's trip replay: how high the follow camera
/// flies, how it glides between framings, and when playback may start.
///
/// Why this exists: replay used to chase the aircraft at a fixed 320 km with a
/// fresh 0.35 s spring every display frame. A 4,200 km leg replayed in five
/// seconds then pans roughly three screen widths a second into tiles MapKit
/// has never fetched, and the first frame zoomed straight from the whole-trip
/// framing into a close follow before any tile had loaded. Both show up as
/// MapKit's grey grid.
///
/// The rules here follow MapLibre Native, which bounds how fast a camera may
/// sweep the ground in *screenfuls per second* and zooms out rather than pan
/// faster (`src/mln/map/transform.cpp`, `Transform::flyTo`, an implementation
/// of van Wijk & Nuij, "Smooth and efficient zooming and panning", 2003), and
/// Mapbox Maps iOS, whose follow-puck viewport holds one zoom and sets the
/// camera directly on every puck frame rather than animating
/// (`Sources/MapboxMaps/Viewport/States/CameraViewportState.swift`).
///
/// Deliberately pure: no MapKit, no SwiftUI, no clock of its own.
enum ReplayCameraPlan {

    // MARK: Follow altitude

    /// The fastest the follow camera may sweep the ground, in screenfuls per
    /// second (a screenful is the longer side of the visible map). MapLibre's
    /// one-off `flyTo` averages 1.2 ρ-screenfuls/s with ρ = 1.42, about 0.85
    /// screenfuls/s; replay pans continuously for the whole leg, so it sits
    /// well under that and MapKit keeps ahead of the camera.
    static let maxScreenfulsPerSecond = 0.5

    /// The closest the follow camera comes, in metres. Close enough that a
    /// short hop still reads as travel, not a dot on a continent.
    static let minimumFollowDistance: Double = 320_000

    /// The follow camera's distance for an aircraft covering `groundSpeed`
    /// metres of ground per second of replay.
    ///
    /// - `screenfulPerDistance`: the visible screenful, in metres of ground,
    ///   per metre of camera distance. Measured from the live map, because it
    ///   depends on MapKit's field of view and the view's aspect.
    /// - `fitDistance`: the distance at which the whole leg fits on screen.
    ///   Following from any higher than that shows less than the overview.
    ///
    /// Zooming out instead of panning faster is MapLibre's rule, held
    /// constant for the leg rather than bowed over a single flight.
    static func followDistance(
        groundSpeed: Double,
        screenfulPerDistance: Double,
        fitDistance: Double
    ) -> Double {
        guard screenfulPerDistance > 0, groundSpeed.isFinite, groundSpeed > 0 else {
            return minimumFollowDistance
        }
        let needed = groundSpeed / (maxScreenfulsPerSecond * screenfulPerDistance)
        let ceiling = max(minimumFollowDistance, fitDistance)
        return min(ceiling, max(minimumFollowDistance, needed))
    }

    /// How quickly the follow distance eases to a new target (a new leg, or a
    /// new playback speed): a time constant, in seconds. Zoom changes are the
    /// expensive kind for tiles, so they are never stepped.
    static let distanceTimeConstant: TimeInterval = 0.6

    /// One frame of exponential easing in log-distance, so a zoom change
    /// progresses at a steady rate in zoom levels, the way MapKit's own zoom
    /// levels (and MapLibre's `easeTo`) interpolate.
    static func easedDistance(from current: Double, to target: Double, elapsed: TimeInterval) -> Double {
        guard current > 0, target > 0, elapsed > 0 else { return current > 0 ? current : target }
        let blend = 1 - exp(-elapsed / distanceTimeConstant)
        return exp(log(current) + (log(target) - log(current)) * blend)
    }

    // MARK: Glides

    /// A jump of the aircraft by more than this many screenfuls (the next
    /// flight of a week starts somewhere else) is flown, not cut.
    static let glideThresholdScreenfuls = 0.5

    /// MapLibre's default `flyTo` speed: 1.2 ρ-screenfuls per second.
    static let glideVelocity = 1.2

    /// Glides stay short: replay is a recap, and the aircraft keeps flying
    /// underneath. The floor keeps a tiny glide from reading as a twitch.
    static let glideDurationRange: ClosedRange<TimeInterval> = 0.6...1.6

    static func needsGlide(jump: Double, screenful: Double) -> Bool {
        guard screenful > 0 else { return false }
        return jump / screenful > glideThresholdScreenfuls
    }

    /// The van Wijk–Nuij optimal zoom-and-pan path, ported from MapLibre
    /// Native's `Transform::flyTo`. Spans and distances are in the same ground
    /// units (MapKit map points here, pixels at the start scale there).
    struct Glide: Equatable {
        /// ρ: how much the path zooms out. 1.42 is van Wijk's user-study
        /// average, MapLibre's default.
        static let rho = 1.42

        let startSpan: Double
        let endSpan: Double
        let distance: Double
        /// S: path length in ρ-screenfuls.
        let length: Double
        private let r0: Double
        private let isClose: Bool

        init(startSpan w0: Double, endSpan w1: Double, distance u1: Double) {
            let rho = Self.rho
            let rho2 = rho * rho
            startSpan = w0
            endSpan = w1
            distance = u1

            func r(_ descent: Bool) -> Double {
                let b = (w1 * w1 - w0 * w0 + (descent ? -1 : 1) * rho2 * rho2 * u1 * u1)
                    / (2 * (descent ? w1 : w0) * rho2 * u1)
                return log(sqrt(b * b + 1) - b)
            }
            let r0 = u1 != 0 ? r(false) : .infinity
            let r1 = u1 != 0 ? r(true) : .infinity
            // When the ends are the same place, only the zoom changes.
            isClose = abs(u1) < 0.000_001 || !r0.isFinite || !r1.isFinite
            self.r0 = r0
            length = isClose ? abs(log(max(w1, .leastNonzeroMagnitude) / max(w0, .leastNonzeroMagnitude))) / rho
                             : (r1 - r0) / rho
        }

        /// Seconds the glide takes at MapLibre's default speed, kept inside
        /// `glideDurationRange`.
        var duration: TimeInterval {
            let natural = length / ReplayCameraPlan.glideVelocity
            let range = ReplayCameraPlan.glideDurationRange
            return min(range.upperBound, max(range.lowerBound, natural.isFinite ? natural : range.lowerBound))
        }

        /// Position along the path at time fraction `k` (0…1):
        /// - `travelled`: share of the ground distance covered, u(s)/u₁;
        /// - `span`: the visible span, w₀·w(s).
        func sample(_ k: Double) -> (travelled: Double, span: Double) {
            let k = min(1, max(0, k))
            if k >= 1 { return (1, endSpan) }
            let rho = Self.rho
            let s = k * length
            if isClose {
                let direction: Double = endSpan < startSpan ? -1 : 1
                return (k, startSpan * exp(direction * rho * s))
            }
            let w = cosh(r0) / cosh(r0 + rho * s)
            let u = startSpan * (cosh(r0) * tanh(r0 + rho * s) - sinh(r0)) / (rho * rho) / distance
            return (min(1, max(0, u)), startSpan * w)
        }
    }

    // MARK: Route prefetch

    /// Spacing of the hidden warm map's stops along a leg, in follow-camera
    /// screenfuls. Under one, so consecutive stops overlap and no strip of the
    /// route is left unfetched.
    static let warmStepScreenfuls = 0.8

    /// Where along a leg (fractions of its length, 0…1, both ends included)
    /// the warm map stops to fetch the follow camera's tiles. The same idea as
    /// fetching ahead along a known route before the camera gets there, one
    /// screenful at a time.
    static func warmStops(legScreenfuls: Double) -> [Double] {
        guard legScreenfuls.isFinite, legScreenfuls > 0 else { return [0] }
        let steps = max(1, Int((legScreenfuls / warmStepScreenfuls).rounded(.up)))
        return (0...steps).map { Double($0) / Double(steps) }
    }

    /// The longest the warm map waits at one stop for MapKit's full render
    /// before moving on, so one slow tile never stalls the sweep.
    static let warmStopTimeout: TimeInterval = 1.2

    // MARK: Start gate

    /// Whether replay may start playing. It first holds on the whole trip
    /// until MapKit reports a full render, which also caches a parent tile
    /// under every mile of the route, so any tile the follow camera is still
    /// waiting on is drawn from its parent instead of grey. The pattern is
    /// Wikipedia iOS's `WMFYearInReviewSlideLocationView` (render the whole
    /// map, wait for `fullyRendered`, only then move the camera), with the
    /// in-flight map's 5 s ceiling (`StudyMapWarmup.tileCoverCeiling`).
    ///
    /// Unlike the in-flight cover, replay never holds the aircraft on the
    /// ground for want of a connection: once MapKit has failed it plays over
    /// whatever the map has, because the route and aircraft are the point.
    /// It deliberately does not consult reachability, which reads "offline"
    /// for the first moments of every launch (`WorldSceneryAvailability`
    /// starts pessimistic) and would open the gate before any tile loaded;
    /// a real outage surfaces as a MapKit failure, or the ceiling.
    static func playbackMayStart(
        tiles: WorldSceneryLoadState,
        ceilingPassed: Bool
    ) -> Bool {
        switch tiles {
        case .ready, .failed: return true
        case .loading: return ceilingPassed
        }
    }

    /// A short establishing beat on the whole trip once it has rendered,
    /// before the camera dives into the first flight.
    static let establishingHold: TimeInterval = 0.6
}
