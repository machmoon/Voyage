import SwiftUI
import MapKit

/// The second study view: a live flight-tracker map of the route.
/// Shows the flown portion solid and the remainder faded, with the
/// aircraft on the same runway-to-runway trajectory as the window. Two camera modes
/// (whole route / follow the plane) and two map styles (terrain / satellite).
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
    @State private var style: Style = .map
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

    var body: some View {
        FlightMapCanvas(
            routes: legRoutes,
            planeCoordinate: session.currentCoordinate,
            planeCourse: session.currentCourse,
            cameraMode: cameraMode,
            style: style,
            bottomInset: showsControls ? controlsHeight : 0,
            tilesChanged: { tiles = $0 }
        )
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
                destination: leg.destination,
                coordinates: coordinates,
                isFlown: index < session.legIndex,
                flownFraction: isCurrent ? flownFraction(along: coordinates, index: index) : nil
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

    /// How much of the current leg's line is flown, by length, so the solid
    /// stroke ends at the aircraft.
    private func flownFraction(along coordinates: [CLLocationCoordinate2D], index: Int) -> Double {
        let progress = session.legProgress
        let split: Int
        if session.legMapSamples.indices.contains(index),
           session.legMapSamples[index].count >= 2 {
            split = session.legMapSamples[index].lastIndex { $0.routeProgress <= progress } ?? 0
        } else {
            split = min(coordinates.count - 1, max(0, Int(progress * Double(coordinates.count - 1))))
        }
        let flown = Array(coordinates.prefix(split + 1)) + [session.currentCoordinate]
        let total = FlightMapRoute.length(of: coordinates)
        guard total > 0 else { return 0 }
        return min(1, max(0, FlightMapRoute.length(of: flown) / total))
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
    let isFlown: Bool
    /// Set on the leg being flown: the share of the line behind the aircraft.
    let flownFraction: Double?

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
    let cameraMode: FlightMapView.CameraMode
    let style: FlightMapView.Style
    let bottomInset: CGFloat
    let tilesChanged: @MainActor (WorldSceneryLoadState) -> Void

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
        private var flownLine: RouteLine?
        private weak var flownRenderer: MKPolylineRenderer?

        init(tilesChanged: @escaping @MainActor (WorldSceneryLoadState) -> Void) {
            self.tilesChanged = tilesChanged
        }

        func attach(to map: LayoutReportingMapView) {
            self.map = map
            map.addAnnotation(plane)
            // The first camera is set at the first real layout, before MapKit
            // requests tiles, so it never loads the whole world first.
            map.didLayout = { [weak self] in self?.fitRouteIfNeeded() }
        }

        func detach() {
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

            if let fraction = view.routes.compactMap(\.flownFraction).first,
               let renderer = flownRenderer,
               abs(renderer.strokeEnd - fraction) > 0.000_1 {
                renderer.strokeEnd = fraction
                renderer.setNeedsDisplay()
            }

            movePlane(to: view.planeCoordinate, course: view.planeCourse, on: map)

            let modeChanged = view.cameraMode != cameraMode
            let isFirstMode = cameraMode == nil
            cameraMode = view.cameraMode
            switch view.cameraMode {
            case .route:
                if modeChanged && !isFirstMode {
                    fitRoute(on: map, animated: true)
                } else {
                    fitRouteIfNeeded()
                }
            case .follow:
                let camera = MKMapCamera(
                    lookingAtCenter: view.planeCoordinate,
                    fromDistance: 220_000,
                    pitch: 0,
                    heading: 0
                )
                if modeChanged {
                    map.setCamera(camera, animated: !isFirstMode)
                } else if !coordinatesNearlyEqual(map.camera.centerCoordinate, view.planeCoordinate) {
                    // Constant-velocity glide matched to the session tick; an
                    // eased animation restarts every 0.5 s and makes the
                    // tracking pulse.
                    UIView.animate(withDuration: 0.55, delay: 0,
                                   options: [.curveLinear, .allowUserInteraction]) {
                        map.camera = camera
                    }
                }
            }
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
            if !coordinatesNearlyEqual(plane.coordinate, coordinate) {
                if CLLocationCoordinate2DIsValid(plane.coordinate), plane.hasPosition {
                    UIView.animate(withDuration: 0.55, delay: 0,
                                   options: [.curveLinear, .allowUserInteraction]) {
                        self.plane.coordinate = coordinate
                    }
                } else {
                    plane.coordinate = coordinate
                    plane.hasPosition = true
                }
            }
            if plane.course != course {
                plane.course = course
                (map.view(for: plane) as? PlaneMarkerView)?.course = course
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
            map.setVisibleMapRect(
                rect,
                edgePadding: UIEdgeInsets(top: pad, left: pad,
                                          bottom: pad + max(0, bottomInset), right: pad),
                animated: animated
            )
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

/// Reports each layout pass, so the first camera can wait for a real size.
final class LayoutReportingMapView: MKMapView {
    var didLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        didLayout?()
    }
}

private final class RouteLine: MKPolyline {
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
    var hasPosition = false
}

private final class AirportAnnotation: NSObject, MKAnnotation {
    let airport: Airport
    var filled: Bool
    var coordinate: CLLocationCoordinate2D { airport.coordinate }

    init(airport: Airport, filled: Bool) {
        self.airport = airport
        self.filled = filled
    }
}

/// White aircraft over a soft shadow, pointing along the course.
private final class PlaneMarkerView: MKAnnotationView {
    static let reuseID = "plane"
    private let shadow = CAGradientLayer()
    private let icon = UIImageView()

    var course: Double = 0 {
        didSet {
            // SF airplane points along +x (east / 90°).
            icon.transform = CGAffineTransform(rotationAngle: (course - 90) * .pi / 180)
        }
    }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 34, height: 34)
        zPriority = .max
        collisionMode = .circle

        shadow.type = .radial
        shadow.colors = [UIColor.black.withAlphaComponent(0.35).cgColor, UIColor.clear.cgColor]
        shadow.startPoint = CGPoint(x: 0.5, y: 0.5)
        shadow.endPoint = CGPoint(x: 1, y: 1)
        shadow.frame = bounds
        layer.addSublayer(shadow)

        // Deliberately not scaled with Dynamic Type: a map annotation is drawn
        // in map space, and a larger aircraft covers the route it is flying.
        icon.image = UIImage(systemName: "airplane",
                             withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .bold))
        icon.tintColor = .white
        icon.contentMode = .center
        icon.frame = bounds
        addSubview(icon)

        isAccessibilityElement = true
        accessibilityLabel = "Your aircraft"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// Airport dot with its code underneath.
private final class AirportDotView: MKAnnotationView {
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
