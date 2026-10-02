import SwiftUI
import MapKit

/// The second study view: a live flight-tracker map of the route.
/// Shows the flown portion solid and the remainder faded, with the
/// aircraft on the same runway-to-runway trajectory as the window. Two camera modes
/// (whole route / follow the plane) and two map styles (terrain / satellite).
/// Satellite is the default: Apple's hybrid imagery with realistic elevation
/// reads as the real world under the wing (Pat, 2026-09-30).
///
/// Drawn by an `MKMapView` rather than SwiftUI's `Map`, because only the UIKit
/// view says when its tiles have rendered. The card stays under a calm cover
/// until MapKit reports a full render, so the traveller never sees MapKit's
/// grey loading grid. The pattern is Wikipedia iOS's
/// (`WMFComponents/.../WMFYearInReviewSlideLocationView.swift`: a
/// `UIViewRepresentable` map acting on
/// `mapViewDidFinishRenderingMap(_:fullyRendered:)`), and the same signal the
/// window's satellite twin uses (`RealWorldTwinView.swift`).
struct FlightMapView: View {
    @Bindable var session: FlightSession

    /// False while the card is mounted only to warm MapKit behind the window
    /// view. A map nobody can see needs no camera/style controls, and leaving
    /// them in the hierarchy would expose them to VoiceOver and to taps.
    var showsControls: Bool = true

    enum CameraMode: String, CaseIterable {
        case route = "Route"
        case follow = "Follow"
    }

    enum Style: String, CaseIterable {
        case map = "Map"
        case satellite = "Satellite"
    }

    @State private var cameraMode: CameraMode = .route
    @State private var style: Style = .satellite
    /// Bumped once to pulse the aircraft for the Open skies hint.
    @State private var planePulse = 0
    @State private var tiles: WorldSceneryLoadState = .loading
    @State private var coverCeilingPassed = false
    @State private var controlsHeight: CGFloat = 0
    @ObservedObject private var availability = WorldSceneryAvailability.shared

    private var showsCover: Bool {
        StudyMapWarmup.showsTileCover(
            tiles: tiles,
            isOnline: availability.isOnline,
            ceilingPassed: coverCeilingPassed
        )
    }

    private var canLoad: Bool { availability.isOnline && tiles != .failed }

    init(session: FlightSession, showsControls: Bool = true) {
        self.session = session
        self.showsControls = showsControls
        // Open skies has no route to fit yet: it opens on the aircraft.
        _cameraMode = State(initialValue: session.isOpenSkies ? .follow : .route)
    }

    var body: some View {
        FlightMapCanvas(
            routes: legRoutes,
            planeCoordinate: session.currentCoordinate,
            planeCourse: session.currentCourse,
            trajectory: session.stage == .inFlight ? session.currentTrajectory : nil,
            seat: session.seat,
            // Anchored on the session's own clock reading, not on when this
            // body happens to run: a body re-evaluated between ticks would
            // otherwise pin an old elapsed to a later date and step the
            // aircraft backwards.
            clockAnchor: FlightVisualClockAnchor(legElapsed: session.legElapsed,
                                                 displayDate: session.now),
            isVisible: showsControls,
            cameraMode: cameraMode,
            style: style,
            bottomInset: showsControls ? controlsHeight : 0,
            tilesChanged: { tiles = $0 },
            onPlaneTap: session.isOpenSkies && showsControls
                ? { session.toggleOpenSkiesControl() } : nil,
            planePulse: planePulse
        )
        .overlay {
            if session.isOpenSkies && showsControls {
                OpenSkiesMapOverlay(session: session, bottomInset: controlsHeight,
                                    planePulse: $planePulse)
            }
        }
        // Flying by hand wants the aircraft in the middle of the map.
        .onChange(of: session.openSkies?.control) { _, control in
            if control == .pilot, cameraMode != .follow {
                withAnimation(.snappy(duration: 0.2)) { cameraMode = .follow }
            }
        }
        .overlay {
            if showsCover { cover.transition(.opacity) }
        }
        .animation(.easeInOut(duration: 0.32), value: showsCover)
        .overlay(alignment: .bottom) {
            if showsControls {
                controls
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        controlsHeight = $0
                    }
            }
        }
        .onChange(of: style) { _, _ in tiles = .loading }
        // The cover waits for a full render, but never forever: a map whose
        // camera keeps moving may never report one. Restarted per style,
        // because a style change reloads every tile.
        .task(id: style) {
            coverCeilingPassed = false
            try? await Task.sleep(for: .seconds(StudyMapWarmup.tileCoverCeiling))
            if !Task.isCancelled { coverCeilingPassed = true }
        }
    }

    /// The departure curtain's palette, so the hand-off from the curtain to the
    /// map reads as one continuous load.
    private var cover: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "0D1531"), Color(hex: "050713")],
                startPoint: .top, endPoint: .bottom
            )
            if !canLoad {
                Text("Map needs a connection")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .accessibilityHidden(canLoad)
    }

    // MARK: Route geometry

    private var legRoutes: [FlightMapRoute] {
        session.itinerary.legs.enumerated().map { index, leg in
            let coordinates = routeCoordinates(for: leg, index: index)
            let isCurrent = index == session.legIndex
            return FlightMapRoute(
                id: leg.id,
                origin: leg.origin,
                // Open skies has no destination dot until it is cleared to land.
                destination: leg.destination.isOpenSkiesPlaceholder ? leg.origin : leg.destination,
                coordinates: coordinates,
                progress: sampleProgress(index: index, count: coordinates.count),
                isFlown: index < session.legIndex,
                flownFraction: isCurrent
                    ? FlightMapRoute.flownFraction(
                        coordinates: coordinates,
                        progress: sampleProgress(index: index, count: coordinates.count),
                        routeProgress: session.legProgress,
                        aircraft: session.currentCoordinate)
                    : nil
            )
        }
    }

    /// The shared trajectory, which keeps the runway roll, authored departure
    /// turn, approach and rollout that a plain great circle would lose.
    private func routeCoordinates(for leg: FlightLeg, index: Int) -> [CLLocationCoordinate2D] {
        if session.legMapSamples.indices.contains(index),
           session.legMapSamples[index].count >= 2 {
            return session.legMapSamples[index].map(\.coordinate)
        }
        return GreatCircle.points(
            from: leg.origin.coordinate,
            to: leg.destination.coordinate,
            count: 96
        )
    }

    /// Route progress at each drawn point, when the line is the shared
    /// trajectory's samples; nil for the great-circle fallback.
    private func sampleProgress(index: Int, count: Int) -> [Double]? {
        guard session.legMapSamples.indices.contains(index),
              session.legMapSamples[index].count == count, count >= 2 else { return nil }
        return session.legMapSamples[index].map(\.routeProgress)
    }

    // MARK: Controls

    /// Side by side normally; stacked at large text sizes, where the two
    /// capsules used to share one row and wrap their labels mid-word
    /// ("Rout e", "Satellit e"; QA/e2e-ax-08-inflight-map.png).
    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                picker(selection: $cameraMode, options: CameraMode.allCases, id: \.rawValue)
                Spacer()
                picker(selection: $style, options: Style.allCases, id: \.rawValue)
            }
            VStack(alignment: .leading, spacing: 8) {
                picker(selection: $cameraMode, options: CameraMode.allCases, id: \.rawValue)
                picker(selection: $style, options: Style.allCases, id: \.rawValue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private func picker<T: Hashable & CaseIterable>(
        selection: Binding<T>,
        options: T.AllCases,
        id: KeyPath<T, String>
    ) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(options), id: \.self) { option in
                let isOn = selection.wrappedValue == option
                Button {
                    Haptics.tap()
                    withAnimation(.snappy(duration: 0.2)) { selection.wrappedValue = option }
                } label: {
                    Text(option[keyPath: id])
                        .voyageFont(11, weight: .bold)
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(isOn ? .black : .white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.clear),
                                    in: Capsule())
                }
                .accessibilityLabel(option[keyPath: id])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(3)
        .background(.black.opacity(0.55), in: Capsule())
    }
}

/// One leg as the map draws it.
struct FlightMapRoute: Equatable {
    let id: FlightLeg.ID
    let origin: Airport
    let destination: Airport
    let coordinates: [CLLocationCoordinate2D]
    /// Route progress (0…1) at each coordinate, for the trajectory's samples.
    var progress: [Double]? = nil
    let isFlown: Bool
    /// Set on the leg being flown: the share of the line behind the aircraft.
    let flownFraction: Double?

    /// How much of a leg's line is flown, by length, so the solid stroke ends
    /// at the aircraft: the samples up to `routeProgress`, plus the stretch
    /// from the last of them to the aircraft itself.
    static func flownFraction(
        coordinates: [CLLocationCoordinate2D],
        progress: [Double]?,
        routeProgress: Double,
        aircraft: CLLocationCoordinate2D
    ) -> Double {
        guard coordinates.count >= 2 else { return 0 }
        let split: Int
        if let progress, progress.count == coordinates.count {
            split = progress.lastIndex { $0 <= routeProgress } ?? 0
        } else {
            split = min(coordinates.count - 1, max(0, Int(routeProgress * Double(coordinates.count - 1))))
        }
        let flown = Array(coordinates.prefix(split + 1)) + [aircraft]
        let total = length(of: coordinates)
        guard total > 0 else { return 0 }
        return min(1, max(0, length(of: flown) / total))
    }

    static func length(of coordinates: [CLLocationCoordinate2D]) -> Double {
        zip(coordinates, coordinates.dropFirst()).reduce(0) {
            $0 + MKMapPoint($1.0).distance(to: MKMapPoint($1.1))
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.isFlown == rhs.isFlown
            && lhs.flownFraction == rhs.flownFraction
            && lhs.coordinates.count == rhs.coordinates.count
    }
}

// MARK: - MapKit view

private struct FlightMapCanvas: UIViewRepresentable {
    let routes: [FlightMapRoute]
    let planeCoordinate: CLLocationCoordinate2D
    let planeCourse: Double
    /// The leg being flown, sampled every display frame for the aircraft and
    /// the Follow camera. Nil outside the air (the tick position is used).
    let trajectory: FlightTrajectory?
    let seat: String
    let clockAnchor: FlightVisualClockAnchor
    /// False while the card only warms MapKit behind the window: nothing
    /// visible, so no display link.
    let isVisible: Bool
    let cameraMode: FlightMapView.CameraMode
    let style: FlightMapView.Style
    let bottomInset: CGFloat
    let tilesChanged: @MainActor (WorldSceneryLoadState) -> Void
    /// Open skies only: a tap on the aircraft takes or returns the controls.
    var onPlaneTap: (() -> Void)?
    /// Each change pulses the aircraft once.
    var planePulse = 0

    func makeUIView(context: Context) -> LayoutReportingMapView {
        let map = LayoutReportingMapView(frame: .zero)
        map.delegate = context.coordinator
        // Pan and zoom only, as the SwiftUI map had.
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsCompass = false
        map.showsScale = false
        // MapKit keeps its "Legal" link inside the layout margins, so the
        // pickers never sit on the attribution.
        map.insetsLayoutMarginsFromSafeArea = false
        map.register(AirportDotView.self,
                     forAnnotationViewWithReuseIdentifier: AirportDotView.reuseID)
        map.register(PlaneMarkerView.self,
                     forAnnotationViewWithReuseIdentifier: PlaneMarkerView.reuseID)
        context.coordinator.attach(to: map)
        context.coordinator.apply(self)
        return map
    }

    func updateUIView(_ map: LayoutReportingMapView, context: Context) {
        context.coordinator.tilesChanged = tilesChanged
        context.coordinator.apply(self)
    }

    static func dismantleUIView(_ map: LayoutReportingMapView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator { Coordinator(tilesChanged: tilesChanged) }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        var tilesChanged: @MainActor (WorldSceneryLoadState) -> Void
        private weak var map: LayoutReportingMapView?
        private var loadState: WorldSceneryLoadState = .loading

        private var routes: [FlightMapRoute] = []
        private var style: FlightMapView.Style?
        private var cameraMode: FlightMapView.CameraMode?
        private var bottomInset: CGFloat = -1
        private var needsRouteFit = true

        private let plane = PlaneAnnotation()
        private var onPlaneTap: (() -> Void)?
        private var planePulse = 0
        private var flownLine: RouteLine?
        private weak var flownRenderer: MKPolylineRenderer?

        // Per-frame motion (see `FlightFollowCameraPlan`).
        private var trajectory: FlightTrajectory?
        private var seat = ""
        private var clockAnchor: FlightVisualClockAnchor?
        private var displayLink: CADisplayLink?
        /// The aircraft's last frame, for its ground speed.
        private var lastAircraft: (point: MKMapPoint, time: CFTimeInterval)?
        private var groundSpeed: Double = 0
        /// The Follow camera's current (eased) distance, in metres; 0 until
        /// Follow first drives the camera.
        private var followDistance: Double = 0
        /// The chase camera's current (eased) bearing and pitch, degrees.
        private var followHeading: Double?
        private var followPitch: Double = 0
        /// The bearing the frame's look-ahead asked for.
        private var chaseTarget: Double = 0
        private var entryStart: (heading: Double, pitch: Double)?
        private var lastCameraFrame: CFTimeInterval?
        /// The glide onto the aircraft when Follow starts or resumes.
        private var entryGlide: (path: ReplayCameraPlan.Glide, start: CFTimeInterval,
                                 duration: TimeInterval, offset: (dx: Double, dy: Double))?
        private var needsEntryGlide = true
        /// Visible ground per metre of camera distance, per view size.
        private var screenfulPerDistance: Double?
        private var measuredSize: CGSize = .zero
        /// Follow lets go while a finger is on the map, so a pan or pinch is
        /// never fought, and glides back shortly after it lifts.
        private var touchHoldUntil: CFTimeInterval = 0
        private var isTouching = false

        init(tilesChanged: @escaping @MainActor (WorldSceneryLoadState) -> Void) {
            self.tilesChanged = tilesChanged
        }

        func attach(to map: LayoutReportingMapView) {
            self.map = map
            map.addAnnotation(plane)
            let touches = TouchTracker { [weak self] touching in self?.touchesChanged(touching) }
            map.addGestureRecognizer(touches)
            // The first camera is set at the first real layout, before MapKit
            // requests tiles, so it never loads the whole world first.
            map.didLayout = { [weak self] in self?.fitRouteIfNeeded() }
        }

        func detach() {
            displayLink?.invalidate()
            displayLink = nil
            map?.didLayout = nil
            map?.delegate = nil
            map = nil
        }

        func apply(_ view: FlightMapCanvas) {
            guard let map else { return }

            if view.style != style {
                let isChange = style != nil
                style = view.style
                map.preferredConfiguration = switch view.style {
                case .map: MKStandardMapConfiguration(elevationStyle: .realistic)
                case .satellite: MKHybridMapConfiguration(elevationStyle: .realistic)
                }
                // Every tile reloads, so the next full render reveals again.
                if isChange { loadState = .loading }
            }

            if view.bottomInset != bottomInset {
                bottomInset = view.bottomInset
                map.layoutMargins = UIEdgeInsets(top: 0, left: 8, bottom: view.bottomInset, right: 8)
                if cameraMode == .route { needsRouteFit = true }
            }

            if view.routes.map(\.id) != routes.map(\.id)
                || view.routes.map(\.isFlown) != routes.map(\.isFlown)
                || view.routes.map(\.coordinates.count) != routes.map(\.coordinates.count)
                || view.routes.map({ $0.flownFraction == nil }) != routes.map({ $0.flownFraction == nil }) {
                rebuildRoutes(view.routes, on: map)
                needsRouteFit = needsRouteFit || cameraMode != .follow
            }
            routes = view.routes

            onPlaneTap = view.onPlaneTap
            let planeView = map.view(for: plane) as? PlaneMarkerView
            planeView?.onTap = view.onPlaneTap
            if view.planePulse != planePulse {
                planePulse = view.planePulse
                planeView?.pulse()
            }

            trajectory = view.trajectory
            seat = view.seat
            clockAnchor = view.clockAnchor
            let animates = view.isVisible && view.trajectory != nil
            setDisplayLinkRunning(animates)

            let modeChanged = view.cameraMode != cameraMode
            let isFirstMode = cameraMode == nil
            cameraMode = view.cameraMode
            if modeChanged {
                needsEntryGlide = !isFirstMode
                lastCameraFrame = nil
                entryGlide = nil
                if view.cameraMode == .follow, isFirstMode { followDistance = 0 }
            }

            // Without a display link (on the ground, between legs, or warming
            // behind the window) the session tick places the aircraft: set,
            // never animated, so there is no second clock to disagree with.
            if !animates {
                if let fraction = view.routes.compactMap(\.flownFraction).first {
                    setStrokeEnd(fraction)
                }
                movePlane(to: view.planeCoordinate, course: view.planeCourse, on: map)
            }

            switch view.cameraMode {
            case .route:
                if modeChanged && !isFirstMode {
                    fitRoute(on: map, animated: true)
                } else {
                    fitRouteIfNeeded()
                }
            case .follow:
                if !animates {
                    followStatic(view.planeCoordinate, on: map, animated: modeChanged && !isFirstMode)
                }
            }
        }

        // MARK: Display link

        private func setDisplayLinkRunning(_ running: Bool) {
            if running {
                if displayLink == nil {
                    let link = CADisplayLink(target: self, selector: #selector(frame(_:)))
                    // The replay clock's range (`FlightReplayView.swift`,
                    // `ReplayDisplayLinkClock`).
                    link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
                    link.add(to: .main, forMode: .common)
                    displayLink = link
                } else if displayLink?.isPaused == true {
                    // Coming back from the window: the aircraft has moved on
                    // while the map was hidden, so Follow glides to it.
                    needsEntryGlide = true
                    entryGlide = nil
                }
                displayLink?.isPaused = false
            } else {
                displayLink?.isPaused = true
                lastAircraft = nil
                lastCameraFrame = nil
            }
        }

        /// One display frame: sample the trajectory once and give the same
        /// pose to the aircraft, the flown line and the camera.
        @objc private func frame(_ link: CADisplayLink) {
            guard let map, let trajectory, let clockAnchor else { return }
            let now = link.targetTimestamp
            // The anchor is in wall-clock time; the link's target is in media
            // time. Same offset, read once per frame.
            let date = Date().addingTimeInterval(now - CACurrentMediaTime())
            let elapsed = clockAnchor.elapsed(at: date, legDuration: trajectory.schedule.legEnd)
            let state = trajectory.state(at: elapsed, seat: seat)
            let aircraft = state.aircraft

            // Last, once this frame's camera heading is set: the marker is
            // rotated relative to it.
            defer { movePlane(to: aircraft.coordinate, course: aircraft.courseDegrees, on: map) }
            if let current = routes.first(where: { $0.flownFraction != nil }) {
                setStrokeEnd(FlightMapRoute.flownFraction(
                    coordinates: current.coordinates,
                    progress: current.progress,
                    routeProgress: state.routeProgress,
                    aircraft: aircraft.coordinate))
            }
            measureSpeed(MKMapPoint(aircraft.coordinate), at: now)

            guard cameraMode == .follow else { return }
            if isTouching || now < touchHoldUntil {
                lastCameraFrame = nil
                return
            }
            let field = state.routeProgress < 0.5
                ? trajectory.departureRunway.threshold.altitudeMeters
                : trajectory.arrivalRunway.threshold.altitudeMeters
            // The bearing looks a share of the view ahead along the path, not
            // at this frame's course alone, so per-frame sampling cannot
            // jitter it and a turn is anticipated (Mapbox's look-ahead to the
            // maneuver; see `FlightFollowCameraPlan.chaseBearing`).
            let distance = followDistance > 0 ? followDistance : FlightFollowCameraPlan.groundDistance
            let ahead = FlightFollowCameraPlan.lookAheadDistance(cameraDistance: distance)
            // On the runway the course *is* the runway, and a look-ahead
            // would reach past the rollout to wherever the leg's path ends;
            // likewise once the look-ahead would run off the end of the leg.
            let seconds = min(180, max(0.5, ahead / max(groundSpeed, 30)))
            let airborne = aircraft.altitudeMeters - field > 30
            var lookAhead: Double?
            if airborne, elapsed + seconds < trajectory.schedule.legEnd {
                let next = trajectory.state(at: elapsed + seconds, seat: seat).aircraft.coordinate
                if MKMapPoint(aircraft.coordinate).distance(to: MKMapPoint(next)) > 50 {
                    lookAhead = GreatCircle.bearing(from: aircraft.coordinate, to: next)
                }
            }
            chaseTarget = FlightFollowCameraPlan.chaseBearing(course: aircraft.courseDegrees,
                                                             lookAhead: lookAhead)
            driveFollow(aircraft.coordinate, altitude: aircraft.altitudeMeters - field, at: now, on: map)
        }

        /// Ground speed off consecutive frames, smoothed over a few frames so
        /// one that lands late does not jolt the zoom.
        private func measureSpeed(_ point: MKMapPoint, at now: CFTimeInterval) {
            defer { lastAircraft = (point, now) }
            guard let last = lastAircraft else { return }
            let dt = now - last.time
            guard dt > 0.001, dt < 0.25 else { return }
            let speed = last.point.distance(to: point) / dt
            let blend = 1 - exp(-dt / 0.3)
            groundSpeed += (speed - groundSpeed) * blend
        }

        private func setStrokeEnd(_ fraction: Double) {
            guard let renderer = flownRenderer, abs(renderer.strokeEnd - fraction) > 0.000_1 else { return }
            renderer.strokeEnd = fraction
            renderer.setNeedsDisplay()
        }

        private func touchesChanged(_ touching: Bool) {
            isTouching = touching
            guard !touching, cameraMode == .follow else { return }
            // Let the gesture's own deceleration finish, then glide back.
            touchHoldUntil = CACurrentMediaTime() + 1.5
            needsEntryGlide = true
            entryGlide = nil
            followDistance = map?.camera.centerCoordinateDistance ?? followDistance
        }

        // MARK: Content

        private func rebuildRoutes(_ newRoutes: [FlightMapRoute], on map: MKMapView) {
            map.removeOverlays(map.overlays)
            map.removeAnnotations(map.annotations.filter { $0 is AirportAnnotation })
            flownLine = nil
            flownRenderer = nil

            let accent = UIColor(Theme.accent)
            var lines: [RouteLine] = []
            for route in newRoutes {
                if route.flownFraction != nil {
                    // Faded full line, with the solid flown share drawn over it.
                    lines.append(RouteLine(route.coordinates, color: accent.withAlphaComponent(0.4), width: 4))
                    let flown = RouteLine(route.coordinates, color: accent, width: 4)
                    flownLine = flown
                    lines.append(flown)
                } else {
                    lines.append(RouteLine(
                        route.coordinates,
                        color: route.isFlown ? accent : accent.withAlphaComponent(0.4),
                        width: route.isFlown ? 4 : 3
                    ))
                }
            }
            map.addOverlays(lines, level: .aboveRoads)

            // A connection airport ends one leg and starts the next; draw it once.
            var airports: [String: AirportAnnotation] = [:]
            var order: [String] = []
            for route in newRoutes {
                for (airport, filled) in [(route.origin, true), (route.destination, route.isFlown)] {
                    if let existing = airports[airport.code] {
                        existing.filled = existing.filled || filled
                    } else {
                        airports[airport.code] = AirportAnnotation(airport: airport, filled: filled)
                        order.append(airport.code)
                    }
                }
            }
            map.addAnnotations(order.compactMap { airports[$0] })
        }

        private func movePlane(to coordinate: CLLocationCoordinate2D, course: Double, on map: MKMapView) {
            // Set, not animated: the display link is the animation, and an
            // animation of its own would trail the camera.
            if !coordinatesNearlyEqual(plane.coordinate, coordinate) {
                plane.coordinate = coordinate
            }
            // The marker is drawn in screen space, so it points along the
            // course relative to the map's own heading: straight up the
            // screen in the chase view.
            let onScreen = FlightFollowCameraPlan.normalized(course - map.camera.heading)
            if abs(FlightFollowCameraPlan.shortestRotation(from: plane.course, to: onScreen)) > 0.05 {
                plane.course = onScreen
                (map.view(for: plane) as? PlaneMarkerView)?.course = onScreen
            }
        }

        // MARK: Camera

        private func fitRouteIfNeeded() {
            guard needsRouteFit, cameraMode != .follow, let map,
                  map.bounds.width > 0, map.bounds.height > 0 else { return }
            needsRouteFit = false
            fitRoute(on: map, animated: false)
        }

        private func fitRoute(on map: MKMapView, animated: Bool) {
            let rect = map.overlays.reduce(MKMapRect.null) { $0.union($1.boundingMapRect) }
            guard !rect.isNull else { return }
            let pad: CGFloat = 36
            followHeading = nil
            if map.camera.pitch > 0.5 || abs(FlightFollowCameraPlan.shortestRotation(
                from: map.camera.heading, to: 0)) > 0.5,
               let screenful = screenfulPerDistance {
                // Leaving the chase view: setVisibleMapRect would keep its
                // heading and pitch, so fly to a north-up, flat camera that
                // frames the same rect.
                let insetWidth = max(1, Double(map.bounds.width) - 2 * Double(pad))
                let insetHeight = max(1, Double(map.bounds.height) - 2 * Double(pad) - Double(max(0, bottomInset)))
                let longer = Double(max(map.bounds.width, map.bounds.height))
                let span = max(rect.size.width * longer / insetWidth, rect.size.height * longer / insetHeight)
                let pointsPerPoint = span / longer
                let mid = MKMapPoint(x: rect.midX,
                                     y: rect.midY + Double(max(0, bottomInset)) / 2 * pointsPerPoint)
                let distance = span * MKMetersPerMapPointAtLatitude(mid.coordinate.latitude) / screenful
                map.setCamera(MKMapCamera(lookingAtCenter: mid.coordinate, fromDistance: distance,
                                          pitch: 0, heading: 0), animated: animated)
                return
            }
            map.setVisibleMapRect(
                rect,
                edgePadding: UIEdgeInsets(top: pad, left: pad,
                                          bottom: pad + max(0, bottomInset), right: pad),
                animated: animated
            )
        }

        /// The visible screenful in metres per metre of camera distance, read
        /// off the live map once per view size (the replay's measurement,
        /// `ReplayMapCanvas.screenful(on:)`).
        private func screenful(on map: MKMapView) -> Double {
            // Only a flat camera can be measured; a resize mid-chase keeps
            // the last reading until the map is flat again.
            if map.bounds.size != measuredSize, map.camera.pitch < 1 {
                measuredSize = map.bounds.size
                screenfulPerDistance = nil
            }
            if let measured = screenfulPerDistance { return measured }
            let rect = map.visibleMapRect
            let distance = map.camera.centerCoordinateDistance
            let latitude = map.camera.centerCoordinate.latitude
            guard distance > 0, rect.size.width > 0, map.camera.pitch < 1 else { return 1 }
            let metres = max(rect.size.width, rect.size.height) * MKMetersPerMapPointAtLatitude(latitude)
            let value = metres / distance
            guard value.isFinite, value > 0.2, value < 5 else { return 1 }
            screenfulPerDistance = value
            return value
        }

        /// One frame of Follow, as a chase view: heading-up along the eased
        /// look-ahead bearing, pitched, the aircraft in the lower third of
        /// the map above the controls, the distance eased toward the altitude
        /// target, and the camera set directly. Turning Follow on (or
        /// letting go of the map) flies there first.
        private func driveFollow(_ coordinate: CLLocationCoordinate2D, altitude: Double,
                                 at now: CFTimeInterval, on map: MKMapView) {
            guard map.bounds.width > 0, map.bounds.height > 0 else { return }
            let plan = FlightFollowCameraPlan.self
            let k = screenful(on: map)
            let dt = lastCameraFrame.map { min(0.1, max(0, now - $0)) } ?? 0
            lastCameraFrame = now
            let target = plan.targetDistance(
                altitudeMeters: altitude, groundSpeed: groundSpeed, screenfulPerDistance: k)
            let targetPitch = plan.pitch(altitudeMeters: altitude,
                                         distance: max(target, followDistance))
            let height = Double(map.bounds.height)
            let longer = Double(max(map.bounds.width, map.bounds.height))
            // `k` is measured along the longer side; the field of view that
            // matters here is the vertical one.
            let halfFieldTangent = k / 2 * height / longer
            let fraction = plan.anchorScreenFraction(viewHeight: height,
                                                    bottomInset: Double(max(0, bottomInset)))
            let mpp = MKMetersPerMapPointAtLatitude(coordinate.latitude)

            func centre(distance: Double, pitch: Double, heading: Double) -> MKMapPoint {
                let ahead = plan.groundAhead(distance: distance, pitchDegrees: pitch,
                                             screenFraction: fraction,
                                             halfFieldTangent: halfFieldTangent) / mpp
                let plane = MKMapPoint(coordinate)
                let radians = heading * .pi / 180
                // Map points grow east (x) and south (y).
                return MKMapPoint(x: plane.x + sin(radians) * ahead, y: plane.y - cos(radians) * ahead)
            }

            if followDistance <= 0 { followDistance = target }
            if needsEntryGlide {
                needsEntryGlide = false
                let rect = map.visibleMapRect
                let startSpan = max(rect.size.width, rect.size.height)
                let endSpan = target * k / mpp
                let live = MKMapPoint(map.camera.centerCoordinate)
                let goal = centre(distance: target, pitch: targetPitch, heading: chaseTarget)
                let offset = (dx: live.x - goal.x, dy: live.y - goal.y)
                followHeading = map.camera.heading
                followPitch = map.camera.pitch
                if UIAccessibility.isReduceMotionEnabled {
                    followDistance = target
                    followHeading = chaseTarget
                    followPitch = targetPitch
                } else {
                    let path = ReplayCameraPlan.Glide(startSpan: startSpan, endSpan: endSpan,
                                                      distance: hypot(offset.dx, offset.dy))
                    let range = plan.entryDurationRange
                    let natural = path.length / ReplayCameraPlan.glideVelocity
                    let duration = min(range.upperBound,
                                       max(range.lowerBound, natural.isFinite ? natural : range.lowerBound))
                    entryGlide = (path, now, duration, offset)
                    entryStart = (followHeading ?? 0, followPitch)
                }
            }

            var distance: Double
            var center: MKMapPoint
            var heading = followHeading ?? chaseTarget
            var pitch = followPitch
            if let glide = entryGlide {
                let t = min(1, max(0, (now - glide.start) / glide.duration))
                let sample = glide.path.sample(t)
                distance = sample.span * mpp / k
                // Turn and tilt over the same glide, eased in and out, so
                // the view swings round behind the aircraft as it arrives.
                let ease = t * t * (3 - 2 * t)
                let start = entryStart ?? (heading, pitch)
                heading = plan.normalized(start.heading
                    + plan.shortestRotation(from: start.heading, to: chaseTarget) * ease)
                pitch = start.pitch + (targetPitch - start.pitch) * ease
                let goal = centre(distance: distance, pitch: pitch, heading: heading)
                center = MKMapPoint(x: goal.x + glide.offset.dx * (1 - sample.travelled),
                                    y: goal.y + glide.offset.dy * (1 - sample.travelled))
                if t >= 1 {
                    entryGlide = nil
                    followDistance = distance
                }
            } else {
                followDistance = plan.easedDistance(
                    from: followDistance, to: target,
                    sweepFloor: plan.sweepFloor(groundSpeed: groundSpeed, screenfulPerDistance: k),
                    elapsed: dt)
                distance = followDistance
                heading = plan.easedBearing(from: heading, to: chaseTarget, elapsed: dt)
                pitch = plan.easedPitch(from: pitch, to: targetPitch, elapsed: dt)
                center = centre(distance: distance, pitch: pitch, heading: heading)
            }
            followHeading = heading
            followPitch = pitch
            map.camera = MKMapCamera(lookingAtCenter: center.coordinate, fromDistance: distance,
                                     pitch: pitch, heading: heading)
            // MapKit caps the pitch. Measured on the iOS 26.5 simulator in this
            // card: 45 to 47° asked, 34° drawn at every distance from 31 to
            // 425 km. Where it used less than asked, place the aircraft for
            // the pitch it actually drew, so it still sits in the lower third.
            let drawn = Double(map.camera.pitch)
            if drawn < pitch - 0.5 {
                let corrected = centre(distance: distance, pitch: drawn, heading: heading)
                map.camera = MKMapCamera(lookingAtCenter: corrected.coordinate, fromDistance: distance,
                                         pitch: drawn, heading: heading)
            }
        }

        /// Follow without a display link: one camera per session tick, set
        /// directly (no per-tick animation to restart).
        private func followStatic(_ coordinate: CLLocationCoordinate2D, on map: MKMapView, animated: Bool) {
            guard !coordinatesNearlyEqual(map.camera.centerCoordinate, coordinate) || animated else { return }
            let distance = followDistance > 0 ? followDistance : FlightFollowCameraPlan.cruiseDistance
            map.setCamera(MKMapCamera(lookingAtCenter: coordinate, fromDistance: distance,
                                      pitch: followPitch, heading: followHeading ?? 0), animated: animated)
        }

        private func coordinatesNearlyEqual(_ lhs: CLLocationCoordinate2D,
                                            _ rhs: CLLocationCoordinate2D) -> Bool {
            abs(lhs.latitude - rhs.latitude) < 0.000_001 &&
                abs(lhs.longitude - rhs.longitude) < 0.000_001
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? RouteLine else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = line.color
            renderer.lineWidth = line.width
            renderer.lineCap = .round
            renderer.lineJoin = .round
            if line === flownLine {
                renderer.strokeEnd = routes.compactMap(\.flownFraction).first ?? 0
                flownRenderer = renderer
            }
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            switch annotation {
            case let plane as PlaneAnnotation:
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: PlaneMarkerView.reuseID, for: plane) as? PlaneMarkerView
                view?.course = plane.course
                view?.onTap = onPlaneTap
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
            // A failed map gets another chance when MapKit tries again, for
            // example once the connection is back.
            if loadState == .failed { publish(.loading) }
        }

        func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
            // Only a full render lifts the cover; a partial one is the grey
            // grid this view exists to hide. The cover's ceiling handles a
            // camera that never lets MapKit finish.
            guard fullyRendered else { return }
            publish(.ready)
        }

        func mapViewDidFailLoadingMap(_ mapView: MKMapView, withError error: Error) {
            publish(.failed)
        }

        private func publish(_ state: WorldSceneryLoadState) {
            guard state != loadState else { return }
            loadState = state
            // Deferred so SwiftUI state never changes inside a representable update.
            Task { @MainActor [tilesChanged] in tilesChanged(state) }
        }
    }
}

/// Reports whether any finger is on the map, without taking part in MapKit's
/// own gestures: it never recognises, never cancels or delays touches, and
/// runs alongside every other recogniser.
private final class TouchTracker: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private let changed: (Bool) -> Void
    private var active = 0

    init(changed: @escaping (Bool) -> Void) {
        self.changed = changed
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if active == 0 { changed(true) }
        active += touches.count
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { lift(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { lift(touches) }

    private func lift(_ touches: Set<UITouch>) {
        active = max(0, active - touches.count)
        if active == 0 {
            changed(false)
            state = .failed
        }
    }

    override func reset() {
        super.reset()
        if active > 0 { active = 0; changed(false) }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

/// Reports each layout pass, so the first camera can wait for a real size.
final class LayoutReportingMapView: MKMapView {
    var didLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        didLayout?()
    }
}

final class RouteLine: MKPolyline {
    private(set) var color: UIColor = .white
    private(set) var width: CGFloat = 3

    convenience init(_ coordinates: [CLLocationCoordinate2D], color: UIColor, width: CGFloat) {
        self.init(coordinates: coordinates, count: coordinates.count)
        self.color = color
        self.width = width
    }
}

private final class PlaneAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    var course: Double = 0
}

final class AirportAnnotation: NSObject, MKAnnotation {
    let airport: Airport
    var filled: Bool
    var coordinate: CLLocationCoordinate2D { airport.coordinate }

    init(airport: Airport, filled: Bool) {
        self.airport = airport
        self.filled = filled
    }
}

/// White aircraft over a soft shadow, pointing along the course.
///
/// On an Open skies flight it is also the control: one tap takes the airplane,
/// another gives it back. The view is 44 pt square for the hit target (Apple's
/// minimum) while the drawing stays its 34 pt size, and the tap is the view's
/// own recogniser, so the map's pan, pinch and double-tap are untouched.
private final class PlaneMarkerView: MKAnnotationView {
    static let reuseID = "plane"
    private static let hitSize: CGFloat = 44
    private static let drawnSize: CGFloat = 34
    private let shadow = CAGradientLayer()
    private let icon = UIImageView()
    /// Holds the drawing, so a pulse can scale it while `course` rotates the icon.
    private let glyph = UIView()

    var course: Double = 0 {
        didSet {
            // SF airplane points along +x (east / 90°).
            icon.transform = CGAffineTransform(rotationAngle: (course - 90) * .pi / 180)
        }
    }

    /// Set only when the aircraft can be flown.
    var onTap: (() -> Void)? {
        didSet {
            accessibilityTraits = onTap == nil ? .none : .button
            accessibilityHint = onTap == nil ? nil : "Takes or hands back the controls"
        }
    }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: Self.hitSize, height: Self.hitSize)
        zPriority = .max
        collisionMode = .circle

        let inset = (Self.hitSize - Self.drawnSize) / 2
        glyph.frame = bounds.insetBy(dx: inset, dy: inset)
        glyph.isUserInteractionEnabled = false
        addSubview(glyph)
        let drawn = glyph.bounds
        shadow.type = .radial
        shadow.colors = [UIColor.black.withAlphaComponent(0.35).cgColor, UIColor.clear.cgColor]
        shadow.startPoint = CGPoint(x: 0.5, y: 0.5)
        shadow.endPoint = CGPoint(x: 1, y: 1)
        shadow.frame = drawn
        glyph.layer.addSublayer(shadow)

        // Deliberately not scaled with Dynamic Type: a map annotation is drawn
        // in map space, and a larger aircraft covers the route it is flying.
        icon.image = UIImage(systemName: "airplane",
                             withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .bold))
        icon.tintColor = .white
        icon.contentMode = .center
        icon.frame = drawn
        glyph.addSubview(icon)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))

        isAccessibilityElement = true
        accessibilityLabel = "Your aircraft"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func tapped() { onTap?() }

    override func accessibilityActivate() -> Bool {
        guard let onTap else { return false }
        onTap()
        return true
    }

    /// One gentle swell and back: "this can be touched".
    func pulse() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.glyph.transform = CGAffineTransform(scaleX: 1.35, y: 1.35)
        } completion: { _ in
            UIView.animate(withDuration: 0.45, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
                self.glyph.transform = .identity
            }
        }
    }
}

/// Airport dot with its code underneath.
final class AirportDotView: MKAnnotationView {
    static let reuseID = "airport"
    private static let dotSize: CGFloat = 14
    private let dot = UIView()
    private let code = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        let size = Self.dotSize
        dot.frame = CGRect(x: 0, y: 0, width: size, height: size)
        dot.layer.cornerRadius = size / 2
        dot.layer.borderWidth = 1.5
        dot.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
        addSubview(dot)

        code.font = .systemFont(ofSize: 11, weight: .semibold)
        code.textColor = .white
        code.layer.shadowColor = UIColor.black.cgColor
        code.layer.shadowOpacity = 0.8
        code.layer.shadowRadius = 2
        code.layer.shadowOffset = .zero
        addSubview(code)

        displayPriority = .required
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(_ annotation: AirportAnnotation) {
        dot.backgroundColor = annotation.filled
            ? UIColor(Theme.accent)
            : UIColor.black.withAlphaComponent(0.6)
        code.text = annotation.airport.code
        code.sizeToFit()

        let size = Self.dotSize
        let width = max(size, code.bounds.width)
        let height = size + 2 + code.bounds.height
        frame.size = CGSize(width: width, height: height)
        dot.frame.origin = CGPoint(x: (width - size) / 2, y: 0)
        code.frame.origin = CGPoint(x: (width - code.bounds.width) / 2, y: size + 2)
        // Keep the dot, not the whole view, on the airport.
        centerOffset = CGPoint(x: 0, y: height / 2 - size / 2)
        accessibilityLabel = annotation.airport.code
    }
}
