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
/// - North up and no pitch, as that free-drive camera defaults
///   (`followsLocationCourse == false` gives bearing 0; pitch 0).
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
