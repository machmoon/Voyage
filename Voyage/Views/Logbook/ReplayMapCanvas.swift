import MapKit
import SwiftUI
import UIKit

/// A request to frame part of the map, applied once per `id`.
struct ReplayFraming: Equatable {
    let id: Int
    let rect: MKMapRect

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

/// One airport stop on the replay, drawn once however many flights touch it.
struct ReplayStop: Equatable {
    let airport: Airport
    let reached: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.airport.code == rhs.airport.code && lhs.reached == rhs.reached
    }
}

/// The replay's map: an `MKMapView`, like the in-flight map
/// (`FlightMapView`), because only the UIKit view reports when its tiles have
/// rendered and lets the camera be set directly on every display frame.
///
/// Three things keep MapKit's grey grid off screen:
///
/// 1. **Start gate.** The whole trip is framed first and playback waits for
///    `mapViewDidFinishRenderingMap(_:fullyRendered:)`, so every part of the
///    route has a cached parent tile before the camera dives in (Wikipedia
///    iOS, `WMFYearInReviewSlideLocationView.swift`).
/// 2. **Bounded sweep.** The follow camera flies high enough that it never
///    crosses more than `ReplayCameraPlan.maxScreenfulsPerSecond` of ground,
///    holds that altitude for the leg, and is set directly each frame, not
///    re-animated (MapLibre `Transform::flyTo`; Mapbox `CameraViewportState`).
/// 3. **Route prefetch.** A second, near-invisible `MKMapView` sits under the
///    visible one and sweeps the whole trip at the follow camera's zoom, one
///    overlapping screenful per stop, moving on at each full render (or after
///    a short timeout). Playback starts once the first flight is fetched, and
///    the sweep stays ahead of the aircraft from there (the `MapWarmer`
///    pattern, moved along the route).
struct ReplayMapCanvas: UIViewRepresentable {
    let routes: [[CLLocationCoordinate2D]]
    let stops: [ReplayStop]
    /// Per route, the share of its samples flown (0…1).
    let reveal: [Double]
    let aircraft: FlightReplaySnapshot?
    /// True while playback drives the camera.
    let following: Bool
    /// Global replay progress (0…1), so the prefetch never falls behind.
    let progress: Double
    /// Per route, the ground its aircraft covers per second of wall-clock
    /// replay at the current speed, in metres.
    let legGroundSpeeds: [Double]
    /// The active route's index.
    let activeLeg: Int
    /// The active leg's bounds, which cap how high the follow camera flies.
    let legRect: MKMapRect
    let framing: ReplayFraming?
    /// The map area not covered by the header and the activity card.
    let focusInsets: UIEdgeInsets
    let reduceMotion: Bool
    let tilesChanged: @MainActor (WorldSceneryLoadState) -> Void

    func makeUIView(context: Context) -> ReplayMapContainer {
        let container = ReplayMapContainer()
        for map in [container.warmMap, container.map] {
            map.preferredConfiguration = MKStandardMapConfiguration(
                elevationStyle: .flat, emphasisStyle: .muted)
            map.pointOfInterestFilter = .excludingAll
            map.overrideUserInterfaceStyle = .dark
            map.isRotateEnabled = false
            map.isPitchEnabled = false
            map.showsCompass = false
            map.showsScale = false
            map.insetsLayoutMarginsFromSafeArea = false
        }
        container.map.register(AirportDotView.self,
                               forAnnotationViewWithReuseIdentifier: AirportDotView.reuseID)
        container.map.register(ReplayAircraftView.self,
                               forAnnotationViewWithReuseIdentifier: ReplayAircraftView.reuseID)
        context.coordinator.attach(to: container)
        context.coordinator.apply(self)
        return container
    }

    func updateUIView(_ container: ReplayMapContainer, context: Context) {
        context.coordinator.tilesChanged = tilesChanged
        context.coordinator.apply(self)
    }

    static func dismantleUIView(_ container: ReplayMapContainer, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator { Coordinator(tilesChanged: tilesChanged) }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        var tilesChanged: @MainActor (WorldSceneryLoadState) -> Void
        private weak var container: ReplayMapContainer?
        private var map: MKMapView? { container?.map }
        private var warmMap: MKMapView? { container?.warmMap }

        // Content
        private var routeCount = -1
        private var revealLines: [RouteLine] = []
        private var revealRenderers: [Int: MKPolylineRenderer] = [:]
        private var revealLengths: [[Double]] = []
        private var revealShown: [Double] = []
        private var airports: [String: AirportAnnotation] = [:]
        private let aircraft = ReplayAircraftAnnotation()

        // Inputs of the latest update
        private var view: ReplayMapCanvas?
        private var appliedFramingID: Int?
        private var focusInsets: UIEdgeInsets = .zero

        // Tile readiness: the visible map's full render of the whole trip,
        // plus the prefetch having swept the first flight.
        private var loadState: WorldSceneryLoadState = .loading
        private var mainRendered = false
        private var firstLegWarmed = false

        // Route prefetch
        private struct WarmStop {
            let coordinate: CLLocationCoordinate2D
            let distance: Double
            let progress: Double
            let leg: Int
        }
        private var warmStops: [WarmStop] = []
        private var warmCursor = 0
        private var warmStartLeg = 0
        private var warmSpeeds: [Double] = []
        private var warmToken = 0

        // Camera
        private var wasFollowing = false
        private var span: Double = 0            // visible map points, longer side
        private var lastFrame: CFTimeInterval?
        private var glide: (path: ReplayCameraPlan.Glide, start: CFTimeInterval, offset: (dx: Double, dy: Double))?
        private var screenfulPerDistance: Double?
        private var measuredSize: CGSize = .zero

        init(tilesChanged: @escaping @MainActor (WorldSceneryLoadState) -> Void) {
            self.tilesChanged = tilesChanged
        }

        func attach(to container: ReplayMapContainer) {
            self.container = container
            container.map.delegate = self
            container.warmMap.delegate = self
            // The first framing waits for a real size, so MapKit never
            // requests tiles for a default whole-world camera first.
            container.didLayout = { [weak self] in self?.layoutChanged() }
        }

        func detach() {
            container?.didLayout = nil
            map?.delegate = nil
            warmMap?.delegate = nil
            container = nil
        }

        func apply(_ view: ReplayMapCanvas) {
            self.view = view
            guard let map else { return }

            if view.routes.count != routeCount { rebuildRoutes(view.routes, on: map) }
            updateReveal(view.reveal)
            updateStops(view.stops, on: map)
            updateAircraft(view.aircraft, on: map)

            if view.focusInsets != focusInsets {
                focusInsets = view.focusInsets
                // MapKit keeps its "Legal" link inside the layout margins, so
                // the attribution stays clear of the activity card.
                map.layoutMargins = UIEdgeInsets(top: view.focusInsets.top, left: 8,
                                                 bottom: view.focusInsets.bottom, right: 8)
            }

            guard map.bounds.width > 0, map.bounds.height > 0 else { return }
            applyFramingIfNeeded(view, on: map)
            driveCamera(view, on: map)
            planWarmSweepIfNeeded(view, on: map)
            keepWarmSweepAhead(of: view.progress)
        }

        private func layoutChanged() {
            guard let map, map.bounds.width > 0, map.bounds.height > 0 else { return }
            if map.bounds.size != measuredSize {
                measuredSize = map.bounds.size
                screenfulPerDistance = nil
            }
            if let view {
                applyFramingIfNeeded(view, on: map)
                planWarmSweepIfNeeded(view, on: map)
            }
        }

        // MARK: Content

        private func rebuildRoutes(_ routes: [[CLLocationCoordinate2D]], on map: MKMapView) {
            map.removeOverlays(map.overlays)
            routeCount = routes.count
            revealRenderers = [:]
            revealShown = Array(repeating: 0, count: routes.count)
            revealLengths = routes.map(Self.cumulativeLengths)

            let accent = UIColor(Theme.accent)
            var base: [RouteLine] = []
            revealLines = []
            for coordinates in routes {
                base.append(RouteLine(coordinates, color: .white.withAlphaComponent(0.18), width: 4))
                revealLines.append(RouteLine(coordinates, color: accent, width: 4))
            }
            map.addOverlays(base, level: .aboveRoads)
            map.addOverlays(revealLines, level: .aboveRoads)
        }

        /// `strokeEnd` is a share of the line's length; replay progress is a
        /// share of its samples. Convert, so the ink ends under the aircraft.
        private func updateReveal(_ reveal: [Double]) {
            for index in revealLines.indices {
                let sampleShare = reveal.indices.contains(index) ? reveal[index] : 0
                let share = Self.lengthShare(ofSampleShare: sampleShare, cumulative: revealLengths[index])
                guard abs(share - revealShown[index]) > 0.000_5 || (share == 0) != (revealShown[index] == 0) else {
                    continue
                }
                revealShown[index] = share
                if let renderer = revealRenderers[index] {
                    renderer.strokeEnd = share
                    renderer.setNeedsDisplay()
                }
            }
        }

        private func updateStops(_ stops: [ReplayStop], on map: MKMapView) {
            for stop in stops {
                if let existing = airports[stop.airport.code] {
                    guard existing.filled != stop.reached else { continue }
                    existing.filled = stop.reached
                    (map.view(for: existing) as? AirportDotView)?.configure(existing)
                } else {
                    let annotation = AirportAnnotation(airport: stop.airport, filled: stop.reached)
                    airports[stop.airport.code] = annotation
                    map.addAnnotation(annotation)
                }
            }
        }

        private func updateAircraft(_ snapshot: FlightReplaySnapshot?, on map: MKMapView) {
            guard let snapshot else {
                if aircraft.isOnMap { map.removeAnnotation(aircraft); aircraft.isOnMap = false }
                return
            }
            // Set, not animated: the display link is the animation.
            aircraft.coordinate = snapshot.coordinate
            if !aircraft.isOnMap { map.addAnnotation(aircraft); aircraft.isOnMap = true }
            if aircraft.course != snapshot.course {
                aircraft.course = snapshot.course
                (map.view(for: aircraft) as? ReplayAircraftView)?.course = snapshot.course
            }
        }

        // MARK: Camera

        private func applyFramingIfNeeded(_ view: ReplayMapCanvas, on map: MKMapView) {
            guard let framing = view.framing, framing.id != appliedFramingID,
                  map.bounds.width > 0, map.bounds.height > 0, !framing.rect.isNull else { return }
            // While playback flies the camera a framing is dropped, never
            // queued: a queued one would snap the view the moment play pauses.
            if view.following, appliedFramingID != nil {
                appliedFramingID = framing.id
                return
            }
            let isFirst = appliedFramingID == nil
            appliedFramingID = framing.id
            glide = nil
            let pad: CGFloat = 28
            map.setVisibleMapRect(
                framing.rect,
                edgePadding: UIEdgeInsets(top: focusInsets.top + pad, left: pad,
                                          bottom: focusInsets.bottom + pad, right: pad),
                animated: !isFirst && !view.reduceMotion
            )
        }

        /// The visible screenful in metres per metre of camera distance, read
        /// off the live map once per view size.
        private func screenful(on map: MKMapView) -> Double {
            if let measured = screenfulPerDistance { return measured }
            let rect = map.visibleMapRect
            let distance = map.camera.centerCoordinateDistance
            let latitude = map.camera.centerCoordinate.latitude
            guard distance > 0, rect.size.width > 0 else { return 1 }
            let metres = max(rect.size.width, rect.size.height) * MKMetersPerMapPointAtLatitude(latitude)
            let value = metres / distance
            // A world-clamped overview under-reports the span; only trust a
            // plausible reading.
            guard value.isFinite, value > 0.2, value < 5 else { return 1 }
            screenfulPerDistance = value
            return value
        }

        /// Where the follow camera wants to be, as (centre, span in map points).
        private func followTarget(for view: ReplayMapCanvas, on map: MKMapView)
            -> (center: MKMapPoint, span: Double)? {
            guard let aircraft = view.aircraft else { return nil }
            let k = screenful(on: map)
            let plane = MKMapPoint(aircraft.coordinate)
            let metresPerPoint = MKMetersPerMapPointAtLatitude(aircraft.coordinate.latitude)
            let legSide = max(view.legRect.size.width, view.legRect.size.height)
            let fit = view.legRect.isNull ? 0 : legSide * metresPerPoint * 1.25 / k
            let speed = view.legGroundSpeeds.indices.contains(view.activeLeg)
                ? view.legGroundSpeeds[view.activeLeg] : 0
            let distance = ReplayCameraPlan.followDistance(
                groundSpeed: speed, screenfulPerDistance: k, fitDistance: fit)
            let targetSpan = distance * k / metresPerPoint

            // Sit the aircraft in the middle of the band between the header
            // and the card, not behind the card at the screen's centre.
            let bounds = map.bounds
            let bandMid = (focusInsets.top + (bounds.height - focusInsets.bottom)) / 2
            let offsetPoints = bandMid - bounds.midY
            let pointsPerScreenful = max(bounds.width, bounds.height)
            let currentSpan = span > 0 ? span : targetSpan
            let center = MKMapPoint(x: plane.x,
                                    y: plane.y - Double(offsetPoints) * currentSpan / Double(pointsPerScreenful))
            return (center, targetSpan)
        }

        private func driveCamera(_ view: ReplayMapCanvas, on map: MKMapView) {
            defer { wasFollowing = view.following }
            guard view.following, let target = followTarget(for: view, on: map) else {
                lastFrame = nil
                glide = nil
                return
            }
            let now = CACurrentMediaTime()
            let elapsed = lastFrame.map { min(0.1, max(0, now - $0)) } ?? 0
            lastFrame = now

            let rect = map.visibleMapRect
            let liveCenter = MKMapPoint(map.camera.centerCoordinate)
            if !wasFollowing || span <= 0 {
                span = max(rect.size.width, rect.size.height)
            }

            // Start a glide when following begins, or when the aircraft jumps
            // (the next flight of the week starts somewhere else).
            var offset = Self.wrappedOffset(from: target.center, to: liveCenter)
            let jump = hypot(offset.dx, offset.dy)
            if glide == nil, !wasFollowing || ReplayCameraPlan.needsGlide(jump: jump, screenful: span) {
                if view.reduceMotion || jump == 0 && abs(log(target.span / span)) < 0.01 {
                    offset = (0, 0)
                    span = target.span
                } else {
                    glide = (ReplayCameraPlan.Glide(startSpan: span, endSpan: target.span, distance: jump),
                             now, offset)
                }
            }

            var center = target.center
            if let active = glide {
                let fraction = (now - active.start) / active.path.duration
                let sample = active.path.sample(fraction)
                span = sample.span
                center = MKMapPoint(x: target.center.x + active.offset.dx * (1 - sample.travelled),
                                    y: target.center.y + active.offset.dy * (1 - sample.travelled))
                if fraction >= 1 { glide = nil }
            } else {
                span = ReplayCameraPlan.easedDistance(from: span, to: target.span, elapsed: elapsed)
            }

            let coordinate = center.coordinate
            let k = screenful(on: map)
            let distance = span * MKMetersPerMapPointAtLatitude(coordinate.latitude) / k
            map.camera = MKMapCamera(lookingAtCenter: coordinate, fromDistance: distance, pitch: 0, heading: 0)
        }

        /// The follow camera's distance for route `leg`, as `driveCamera`
        /// will fly it.
        private func followDistance(leg: Int, speed: Double, on map: MKMapView) -> Double {
            let k = screenful(on: map)
            let rect = Self.rect(of: view?.routes[leg] ?? [])
            let middle = MKMapPoint(x: rect.midX, y: rect.midY).coordinate
            let metresPerPoint = MKMetersPerMapPointAtLatitude(middle.latitude)
            let fit = rect.isNull ? 0
                : max(rect.size.width, rect.size.height) * metresPerPoint * 1.25 / k
            return ReplayCameraPlan.followDistance(groundSpeed: speed, screenfulPerDistance: k, fitDistance: fit)
        }

        /// Lays out the prefetch: stops along every route from the aircraft
        /// onward, one overlapping follow-camera screenful apart. Re-planned
        /// when the playback speed changes the follow altitude.
        private func planWarmSweepIfNeeded(_ view: ReplayMapCanvas, on map: MKMapView) {
            guard !view.routes.isEmpty, view.legGroundSpeeds.count == view.routes.count,
                  warmStops.isEmpty || view.legGroundSpeeds != warmSpeeds else { return }
            _ = screenful(on: map)
            // Wait for a real reading off the framed map before planning.
            guard let k = screenfulPerDistance else { return }
            warmSpeeds = view.legGroundSpeeds
            var stops: [WarmStop] = []
            let count = Double(view.routes.count)
            for (leg, route) in view.routes.enumerated() where route.count >= 2 {
                let distance = followDistance(leg: leg, speed: view.legGroundSpeeds[leg], on: map)
                let cumulative = revealLengths.indices.contains(leg)
                    ? revealLengths[leg] : Self.cumulativeLengths(route)
                let middle = route[route.count / 2]
                let legMetres = (cumulative.last ?? 0) * MKMetersPerMapPointAtLatitude(middle.latitude)
                for share in ReplayCameraPlan.warmStops(legScreenfuls: legMetres / (distance * k)) {
                    stops.append(WarmStop(
                        coordinate: Self.coordinate(atLengthShare: share, of: route, cumulative: cumulative),
                        distance: distance,
                        progress: (Double(leg) + share) / count,
                        leg: leg))
                }
            }
            warmStops = stops
            warmStartLeg = view.activeLeg
            warmCursor = stops.firstIndex { $0.progress >= view.progress } ?? stops.count
            if warmCursor >= stops.count { firstLegWarmed = true; checkReady() }
            showWarmStop()
        }

        /// Never fetch behind the aircraft: skip stops it has already passed.
        private func keepWarmSweepAhead(of progress: Double) {
            guard warmCursor < warmStops.count, warmStops[warmCursor].progress < progress else { return }
            while warmCursor < warmStops.count, warmStops[warmCursor].progress < progress {
                warmCursor += 1
            }
            showWarmStop()
        }

        private func showWarmStop() {
            warmToken += 1
            guard let warmMap, warmCursor < warmStops.count else { return }
            let stop = warmStops[warmCursor]
            warmMap.camera = MKMapCamera(lookingAtCenter: stop.coordinate, fromDistance: stop.distance,
                                         pitch: 0, heading: 0)
            let token = warmToken
            DispatchQueue.main.asyncAfter(deadline: .now() + ReplayCameraPlan.warmStopTimeout) { [weak self] in
                guard let self, self.warmToken == token else { return }
                self.advanceWarmSweep()
            }
        }

        private func advanceWarmSweep() {
            guard warmCursor < warmStops.count else { return }
            let leg = warmStops[warmCursor].leg
            warmCursor += 1
            if leg == warmStartLeg,
               warmCursor >= warmStops.count || warmStops[warmCursor].leg != leg {
                firstLegWarmed = true
                checkReady()
            }
            showWarmStop()
        }

        private func checkReady() {
            if mainRendered && firstLegWarmed { publish(.ready) }
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? RouteLine else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = line.color
            renderer.lineWidth = line.width
            renderer.lineCap = .round
            renderer.lineJoin = .round
            if let index = revealLines.firstIndex(where: { $0 === line }) {
                renderer.strokeEnd = revealShown.indices.contains(index) ? revealShown[index] : 0
                revealRenderers[index] = renderer
            }
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            switch annotation {
            case let aircraft as ReplayAircraftAnnotation:
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: ReplayAircraftView.reuseID, for: aircraft) as? ReplayAircraftView
                view?.course = aircraft.course
                return view
            case let airport as AirportAnnotation:
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: AirportDotView.reuseID, for: airport) as? AirportDotView
                view?.configure(airport)
                return view
            default:
                return nil
            }
        }

        func mapViewWillStartLoadingMap(_ mapView: MKMapView) {
            if mapView === map, loadState == .failed { publish(.loading) }
        }

        func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
            // Only a full render counts; a partial one is the grey grid.
            guard fullyRendered else { return }
            if mapView === map {
                mainRendered = true
                checkReady()
            } else if mapView === warmMap, warmCursor < warmStops.count {
                advanceWarmSweep()
            }
        }

        func mapViewDidFailLoadingMap(_ mapView: MKMapView, withError error: Error) {
            guard mapView === map, loadState != .ready else { return }
            publish(.failed)
        }

        private func publish(_ state: WorldSceneryLoadState) {
            guard state != loadState else { return }
            loadState = state
            // Deferred so SwiftUI state never changes inside a representable update.
            Task { @MainActor [tilesChanged] in tilesChanged(state) }
        }

        // MARK: Geometry

        private static func cumulativeLengths(_ coordinates: [CLLocationCoordinate2D]) -> [Double] {
            var lengths: [Double] = [0]
            lengths.reserveCapacity(coordinates.count)
            for index in coordinates.indices.dropFirst() {
                let a = MKMapPoint(coordinates[index - 1])
                let b = MKMapPoint(coordinates[index])
                lengths.append(lengths[index - 1] + hypot(b.x - a.x, b.y - a.y))
            }
            return lengths
        }

        private static func lengthShare(ofSampleShare share: Double, cumulative: [Double]) -> Double {
            guard let total = cumulative.last, total > 0, cumulative.count > 1 else { return share > 0 ? 1 : 0 }
            let position = min(1, max(0, share)) * Double(cumulative.count - 1)
            let lower = Int(position.rounded(.down))
            let upper = min(cumulative.count - 1, lower + 1)
            let t = position - Double(lower)
            return (cumulative[lower] + (cumulative[upper] - cumulative[lower]) * t) / total
        }

        private static func rect(of coordinates: [CLLocationCoordinate2D]) -> MKMapRect {
            coordinates.reduce(MKMapRect.null) { rect, coordinate in
                let point = MKMapPoint(coordinate)
                return rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
            }
        }

        private static func coordinate(atLengthShare share: Double,
                                       of route: [CLLocationCoordinate2D],
                                       cumulative: [Double]) -> CLLocationCoordinate2D {
            guard let total = cumulative.last, total > 0, route.count == cumulative.count else {
                return route.first ?? CLLocationCoordinate2D()
            }
            let target = min(1, max(0, share)) * total
            let upper = cumulative.firstIndex { $0 >= target } ?? cumulative.count - 1
            guard upper > 0 else { return route[0] }
            let lower = upper - 1
            let span = cumulative[upper] - cumulative[lower]
            let t = span > 0 ? (target - cumulative[lower]) / span : 0
            let a = MKMapPoint(route[lower]), b = MKMapPoint(route[upper])
            return MKMapPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t).coordinate
        }

        /// The offset from `a` to `b`, the short way round the antimeridian.
        private static func wrappedOffset(from a: MKMapPoint, to b: MKMapPoint) -> (dx: Double, dy: Double) {
            let world = MKMapSize.world.width
            var dx = b.x - a.x
            if dx > world / 2 { dx -= world } else if dx < -world / 2 { dx += world }
            return (dx, b.y - a.y)
        }
    }
}

/// Hosts the visible map over the warm map, and reports layout passes.
final class ReplayMapContainer: UIView {
    let map = MKMapView()
    /// Near-invisible, under the visible map: MapKit only fetches tiles for a
    /// map that is on screen, the reason `MapWarmer` parks its map at 2 %.
    let warmMap = MKMapView()
    var didLayout: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        warmMap.alpha = 0.02
        warmMap.isUserInteractionEnabled = false
        warmMap.accessibilityElementsHidden = true
        for view in [warmMap, map] {
            view.frame = bounds
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        didLayout?()
    }
}

private final class ReplayAircraftAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    var course: Double = 0
    var isOnMap = false
}

/// The replay's aircraft: an accent badge with a soft halo, as before.
private final class ReplayAircraftView: MKAnnotationView {
    static let reuseID = "replay-aircraft"
    private let halo = UIView()
    private let badge = UIView()
    private let icon = UIImageView()

    var course: Double = 0 {
        didSet {
            // The SF Symbol points east at 0°; the map stays north-up.
            icon.transform = CGAffineTransform(rotationAngle: (course - 90) * .pi / 180)
        }
    }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 48, height: 48)
        zPriority = .max
        displayPriority = .required
        collisionMode = .circle

        let accent = UIColor(Theme.accent)
        halo.frame = bounds
        halo.layer.cornerRadius = 24
        halo.backgroundColor = accent.withAlphaComponent(0.20)
        addSubview(halo)

        badge.frame = CGRect(x: 9, y: 9, width: 30, height: 30)
        badge.layer.cornerRadius = 15
        badge.backgroundColor = accent
        addSubview(badge)

        icon.image = UIImage(systemName: "airplane",
                             withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .black))
        icon.tintColor = .white
        icon.contentMode = .center
        icon.frame = bounds
        addSubview(icon)

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.22
        layer.shadowRadius = 5
        layer.shadowOffset = CGSize(width: 0, height: 2)

        isAccessibilityElement = true
        accessibilityLabel = "Replay aircraft"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
