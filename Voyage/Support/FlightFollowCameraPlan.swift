import Foundation

/// Camera policy for the in-flight map's Follow mode: where the camera sits
/// relative to the aircraft, how high it flies, and how fast either may change.
///
/// Why this exists: Follow used to re-aim `MKMapCamera` once per 0.5 s session
/// tick inside a 0.55 s linear `UIView.animate`, while the aircraft marker ran
/// its own separate 0.55 s animation off the same tick. The two never agreed
/// between ticks and every new animation cut the previous one short, so the
/// aircraft saw-toothed across the card (drifting up to a third of the card
/// off centre, then snapping back) and the view held one 220 km zoom from the
/// runway to the gate.
///
/// The design is Mapbox's, applied to MapKit:
/// - The camera follows the marker's *rendered* position, sampled once per
///   display frame, and is set directly rather than animated. Mapbox Maps iOS
///   feeds its follow camera from `onPuckRender` and applies it through
///   `CameraViewportState`
///   (`Sources/MapboxMaps/Viewport/States/FollowPuck/FollowPuckViewportState.swift`,
///   `Sources/MapboxMaps/Viewport/States/CameraViewportState.swift`, mapbox-maps-ios
///   at d872a1d). Here the shared sample is `FlightTrajectory.state(at:)` on the
///   window's clock anchor, so the marker and the camera cannot disagree.
/// - The zoom comes from a camera altitude, not a fixed zoom, and the aircraft
///   sits in the middle of the *unobscured* viewport, not the view's centre.
///   Mapbox Navigation's free-drive following camera does both
///   (`Sources/MapboxNavigationCore/Map/Camera/ViewportDataSource/MobileViewportDataSource.swift`,
///   `ZoomLevelForAltitude`, and `anchor(_:bounds:edgeInsets:)` in
///   `ViewportDataSource+Calculation.swift`, mapbox-navigation-ios at 7dc868c).
///   An aircraft changes altitude, so the camera's distance follows it: close
///   over the runway, where the roll and the departure turn read as motion,
///   wide at cruise.
/// - A chase view (Pat, 2026-10-01: "from behind the plane and the heading
///   should be the plane heading"): heading-up, pitched, the aircraft low in
///   the map so the view looks ahead along the route. This is Mapbox
///   Navigation's *active-guidance* following camera rather than its
///   free-drive one: `FollowingCameraOptions` (`followsLocationCourse = true`,
///   `defaultPitch` 45°, `bearingSmoothing.maximumBearingSmoothingAngle` 45°,
///   `Sources/MapboxNavigationCore/Map/Camera/FollowingCameraOptions.swift`),
///   whose bearing is the direction to a point ahead on the route, held
///   within 45° of the course and applied as the shortest rotation from the
///   map's current bearing (`bearing(_:mapView:coordinatesToManeuver:)`), and
///   whose puck sits below centre by the pitch coefficient
///   (`anchor(_:bounds:edgeInsets:)`), both in
///   `ViewportDataSource+Calculation.swift`, mapbox-navigation-ios at 7dc868c.
///   Mapbox recomputes per location update and lets its camera animator
///   smooth between; with a camera set every frame here, the smoothing is an
///   explicit shortest-angle exponential ease.
/// - Zoom eased in log space and never stepped, and never sweeping more than
///   `ReplayCameraPlan.maxScreenfulsPerSecond` of ground (MapLibre's rule,
///   already used by the trip replay; see `ReplayCameraPlan`).
///
/// Deliberately pure: no MapKit, no SwiftUI, no clock of its own.
enum FlightFollowCameraPlan {

    /// Camera distance with the aircraft on the runway, in metres. Close
    /// enough that the takeoff roll and the first turn visibly move the
    /// aircraft across the ground.
    static let groundDistance: Double = 30_000

    /// Camera distance at cruise, in metres: the 220 km the Follow camera has
    /// always used, wide enough to show the coast or the next city.
    static let cruiseDistance: Double = 220_000

    /// The aircraft altitude, in metres, at which the camera reaches its
    /// cruise distance. Below it the distance climbs with the aircraft.
    static let cruiseAltitude: Double = 9_000

    /// The camera's distance for an aircraft at `altitudeMeters` above the
    /// departure field, interpolated in log space so each thousand metres of
    /// climb is the same step in zoom level.
    static func altitudeDistance(altitudeMeters: Double) -> Double {
        guard altitudeMeters.isFinite else { return cruiseDistance }
        let share = min(1, max(0, altitudeMeters / cruiseAltitude))
        return exp(log(groundDistance) + (log(cruiseDistance) - log(groundDistance)) * share)
    }

    /// The follow camera's target distance: the altitude distance, raised if
    /// the aircraft would otherwise sweep the ground faster than
    /// `ReplayCameraPlan.maxScreenfulsPerSecond` (a compressed demo flight
    /// can; a real one never does).
    ///
    /// - `screenfulPerDistance`: metres of visible ground per metre of
    ///   camera distance, measured off the live map.
    static func targetDistance(
        altitudeMeters: Double,
        groundSpeed: Double,
        screenfulPerDistance: Double
    ) -> Double {
        max(altitudeDistance(altitudeMeters: altitudeMeters),
            sweepFloor(groundSpeed: groundSpeed, screenfulPerDistance: screenfulPerDistance))
    }

    /// How quickly the follow distance eases to its target: a time constant,
    /// in seconds. Longer than replay's 0.6 s, because a live flight is
    /// watched for an hour and the zoom should drift, not move.
    static let distanceTimeConstant: TimeInterval = 2.0

    /// One frame of exponential easing in log distance. When the camera is
    /// lower than the sweep bound allows (`sweepFloor`), it climbs on the
    /// replay's quicker 0.6 s constant instead: that is the case where the
    /// ground is about to outrun MapKit's tiles, and waiting two seconds to
    /// climb is what shows as blur.
    static func easedDistance(from current: Double, to target: Double,
                              sweepFloor: Double = 0, elapsed: TimeInterval) -> Double {
        guard current > 0, target > 0, elapsed > 0 else { return current > 0 ? current : target }
        let constant = current < sweepFloor ? ReplayCameraPlan.distanceTimeConstant : distanceTimeConstant
        let blend = 1 - exp(-elapsed / constant)
        return exp(log(current) + (log(target) - log(current)) * blend)
    }

    /// The lowest distance at which an aircraft covering `groundSpeed`
    /// metres a second stays under the sweep bound; 0 when it is unknown.
    static func sweepFloor(groundSpeed: Double, screenfulPerDistance: Double) -> Double {
        guard screenfulPerDistance > 0, groundSpeed.isFinite, groundSpeed > 0 else { return 0 }
        return groundSpeed / (ReplayCameraPlan.maxScreenfulsPerSecond * screenfulPerDistance)
    }

    // MARK: Chase view

    /// Camera pitch (degrees from straight down) on the runway: Mapbox's
    /// `defaultPitch`. Lower than at cruise, so the runway and the roll read
    /// from above while the camera is close.
    static let groundPitch: Double = 45

    /// Camera pitch at cruise.
    static let cruisePitch: Double = 60

    /// Pitch for an aircraft at `altitudeMeters` above the field, on the same
    /// altitude share as the distance. MapKit may lower it further when the
    /// camera is high; the caller reads back what MapKit actually used.
    static func pitch(altitudeMeters: Double) -> Double {
        guard altitudeMeters.isFinite else { return cruisePitch }
        let share = min(1, max(0, altitudeMeters / cruiseAltitude))
        return groundPitch + (cruisePitch - groundPitch) * share
    }

    /// The pitch to fly at `distance` metres: `pitch(altitudeMeters:)`,
    /// flattened in proportion once the sweep bound has lifted the camera
    /// above its cruise distance. Only a compressed demo leg gets there, and
    /// a tilted view from that high reaches far more ground than MapKit has
    /// fetched, which showed as its grey grid in the recordings.
    static func pitch(altitudeMeters: Double, distance: Double) -> Double {
        let base = pitch(altitudeMeters: altitudeMeters)
        guard distance > cruiseDistance else { return base }
        return base * cruiseDistance / distance
    }

    /// The signed turn, in degrees in (-180, 180], from `from` to `to`.
    /// Mapbox's `shortestRotation(angle:)`: a heading of 359° to 1° is +2°,
    /// never -358°.
    static func shortestRotation(from: Double, to: Double) -> Double {
        var delta = (to - from).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta <= -180 { delta += 360 }
        return delta
    }

    /// The most the camera's bearing may differ from the aircraft's course:
    /// Mapbox's `maximumBearingSmoothingAngle`.
    static let maximumBearingSmoothingAngle: Double = 45

    /// The chase camera's target bearing: the direction from the aircraft to
    /// a point ahead on its path, held within
    /// `maximumBearingSmoothingAngle` of the current course. Mapbox's
    /// `bearing(_:mapView:coordinatesToManeuver:)`, which steps the course by
    /// at most the smoothing angle toward the look-ahead direction.
    static func chaseBearing(course: Double, lookAhead: Double?) -> Double {
        guard let lookAhead, lookAhead.isFinite else { return normalized(course) }
        let diff = shortestRotation(from: course, to: lookAhead)
        let limit = maximumBearingSmoothingAngle
        return normalized(course + min(limit, max(-limit, diff)))
    }

    /// How far ahead along the path the bearing looks, in metres: a share of
    /// the camera distance, so the look-ahead is always a fixed part of the
    /// view whatever the zoom. Long enough that one frame's sample of the
    /// path cannot jitter the bearing; short enough to turn with the turn.
    static func lookAheadDistance(cameraDistance: Double) -> Double {
        max(1_500, 0.15 * max(0, cameraDistance))
    }

    /// How quickly the camera's bearing and pitch ease to their targets: a
    /// time constant, in seconds.
    static let bearingTimeConstant: TimeInterval = 2.0

    /// One frame of shortest-angle exponential easing. The result is
    /// `current` plus a share of the shortest turn, so it never spins the
    /// long way round, and is normalised to 0..<360.
    static func easedBearing(from current: Double, to target: Double, elapsed: TimeInterval) -> Double {
        guard elapsed > 0, current.isFinite else { return normalized(target) }
        let blend = 1 - exp(-elapsed / bearingTimeConstant)
        return normalized(current + shortestRotation(from: current, to: target) * blend)
    }

    /// Linear easing for the pitch, on the bearing's time constant.
    static func easedPitch(from current: Double, to target: Double, elapsed: TimeInterval) -> Double {
        guard elapsed > 0, current.isFinite else { return target }
        let blend = 1 - exp(-elapsed / bearingTimeConstant)
        return current + (target - current) * blend
    }

    static func normalized(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    /// Mapbox's pitch coefficient for the anchor: the aircraft sits this
    /// share of the padded viewport's half-height below its centre. Mapbox
    /// uses 1 (the puck at the bottom edge) for driving; 0.4 puts the
    /// aircraft at 70 % of the way down the visible map, in its lower third,
    /// with room behind it for the route already flown.
    static let anchorCoefficient: Double = 0.4

    /// Where the aircraft sits, as a fraction of the *whole* view's
    /// half-height below its centre, given the controls covering
    /// `bottomInset` points of a view `viewHeight` tall. Mapbox's
    /// `anchor(_:bounds:edgeInsets:)`, in fractions.
    static func anchorScreenFraction(viewHeight: Double, bottomInset: Double,
                                     coefficient: Double = anchorCoefficient) -> Double {
        guard viewHeight > 0 else { return 0 }
        let padded = max(0, viewHeight - max(0, bottomInset))
        let y = padded / 2 * (1 + coefficient)
        return (y - viewHeight / 2) / (viewHeight / 2)
    }

    /// How far ahead of the aircraft, in metres of ground along the bearing,
    /// the camera's centre must be so that the aircraft lands
    /// `screenFraction` of the half-height below the screen centre.
    ///
    /// A pinhole camera `distance` metres from the centre point, pitched
    /// `pitchDegrees` from straight down, with a vertical half field of view
    /// whose tangent is `halfFieldTangent`: the ray through the aircraft
    /// leans `α = atan(screenFraction · halfFieldTangent)` further down than
    /// the centre ray, so it meets the ground `h·(tan p − tan(p − α))` short
    /// of the centre, where `h = distance · cos p` is the camera's height.
    /// At zero pitch this is the flat-map offset, `distance · tan α`.
    static func groundAhead(distance: Double, pitchDegrees: Double,
                            screenFraction: Double, halfFieldTangent: Double) -> Double {
        guard distance > 0, halfFieldTangent > 0 else { return 0 }
        let p = min(85, max(0, pitchDegrees)) * .pi / 180
        let alpha = atan(screenFraction * halfFieldTangent)
        let height = distance * cos(p)
        return height * (tan(p) - tan(p - alpha))
    }

    /// How far, in screen points, the camera's centre sits below the
    /// aircraft so the aircraft is centred in the part of the map not covered
    /// by the bottom controls. Mapbox's `anchor(_:bounds:edgeInsets:)` with a
    /// zero pitch coefficient: the middle of the padded viewport.
    static func centreOffsetPoints(topInset: Double, bottomInset: Double) -> Double {
        (max(0, bottomInset) - max(0, topInset)) / 2
    }

    /// Turning Follow on flies from wherever the camera was (usually the
    /// whole-route view) onto the aircraft along the van Wijk–Nuij path
    /// (`ReplayCameraPlan.Glide`), the way Mapbox Navigation enters its
    /// following state with `camera.fly(to:duration:)` rather than a cut
    /// (`NavigationCameraStateTransition.transitionTo`, mapbox-navigation-ios
    /// at 7dc868c). Mapbox flies for 0.25 to 0.5 s; this is longer because
    /// the whole-route view to Follow is a far bigger zoom change than a
    /// street-level recentre, and MapLibre's 1.2 ρ-screenfuls/s sets it.
    static let entryDurationRange: ClosedRange<TimeInterval> = 0.8...1.6
}
