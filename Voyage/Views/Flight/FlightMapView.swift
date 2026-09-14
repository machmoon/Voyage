import SwiftUI
import MapKit

/// The second study view: a live flight-tracker map of the route.
/// Shows the flown portion solid and the remainder faded, with the
/// aircraft on the same runway-to-runway trajectory as the window. Two camera modes
/// (whole route / follow the plane) and two map styles (terrain / satellite).
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
    @State private var cameraPosition: MapCameraPosition = .automatic

    private var accent: Color { Theme.accent }

    var body: some View {
        Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {
            ForEach(Array(session.itinerary.legs.enumerated()), id: \.element.id) { index, leg in
                legContent(leg: leg, index: index)
            }

            Annotation("", coordinate: session.currentCoordinate) {
                planeMarker
            }
            .annotationTitles(.hidden)
        }
        .mapStyle(mapStyle)
        .onAppear { updateCamera(animated: false) }
        .onChange(of: cameraMode) { _, _ in updateCamera(animated: true) }
        .onChange(of: session.legProgress) { _, _ in
            // Constant-velocity glide between ticks; an eased animation here
            // restarts every 0.5 s and makes the tracking pulse.
            if cameraMode == .follow { updateCamera(animated: true, tracking: true) }
        }
        // A bottom safe-area inset, not an overlay: MapKit keeps its "Legal"
        // link above the inset, so the pickers never sit on the attribution.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsControls { controls }
        }
    }

    /// Two honest choices — "Standard vs Terrain" looked identical at route
    /// zoom, so they collapsed into one. Hybrid imagery keeps city labels
    /// on the satellite view.
    private var mapStyle: MapStyle {
        switch style {
        case .map: return .standard(elevation: .realistic)
        case .satellite: return .hybrid(elevation: .realistic)
        }
    }

    // MARK: Route content

    @MapContentBuilder
    private func legContent(leg: FlightLeg, index: Int) -> some MapContent {
        let isCurrentLeg = index == session.legIndex
        let isFlown = index < session.legIndex
        let geometry = routeGeometry(for: leg, index: index)

        // Endpoints.
        Annotation(leg.origin.code, coordinate: leg.origin.coordinate) {
            airportDot(leg.origin, filled: true)
        }
        Annotation(leg.destination.code, coordinate: leg.destination.coordinate) {
            airportDot(leg.destination, filled: isFlown)
        }

        if isCurrentLeg {
            // Split the shared trajectory at the aircraft. This retains the
            // runway roll, authored departure turn, approach and rollout that
            // would disappear in an origin→current→destination great circle.
            MapPolyline(coordinates: geometry.flown)
                .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            MapPolyline(coordinates: geometry.remaining)
                .stroke(accent.opacity(0.4),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
        } else {
            MapPolyline(coordinates: geometry.all)
                .stroke(isFlown ? accent : accent.opacity(0.4),
                        style: StrokeStyle(lineWidth: isFlown ? 4 : 3, lineCap: .round))
        }
    }

    private struct RouteGeometry {
        let all: [CLLocationCoordinate2D]
        let flown: [CLLocationCoordinate2D]
        let remaining: [CLLocationCoordinate2D]
    }

    private func routeGeometry(for leg: FlightLeg, index: Int) -> RouteGeometry {
        guard session.legMapSamples.indices.contains(index),
              session.legMapSamples[index].count >= 2 else {
            let fallback = GreatCircle.points(
                from: leg.origin.coordinate,
                to: leg.destination.coordinate,
                count: 96
            )
            if index != session.legIndex {
                return RouteGeometry(all: fallback, flown: fallback, remaining: fallback)
            }
            let split = min(fallback.count - 1, max(0, Int(session.legProgress * Double(fallback.count - 1))))
            let current = session.currentCoordinate
            return RouteGeometry(
                all: fallback,
                flown: Array(fallback.prefix(split + 1)) + [current],
                remaining: [current] + Array(fallback.suffix(from: split))
            )
        }

        let samples = session.legMapSamples[index]
        let all = samples.map(\.coordinate)
        guard index == session.legIndex else {
            return RouteGeometry(all: all, flown: all, remaining: all)
        }

        let progress = session.legProgress
        let split = samples.lastIndex { $0.routeProgress <= progress } ?? 0
        let current = session.currentCoordinate
        var flown = samples.prefix(split + 1).map(\.coordinate)
        if flown.last.map({ coordinatesNearlyEqual($0, current) }) != true {
            flown.append(current)
        }
        if flown.count == 1 { flown.insert(leg.origin.coordinate, at: 0) }

        var remaining = [current]
        let nextIndex = min(samples.count, split + 1)
        remaining.append(contentsOf: samples.suffix(from: nextIndex).map(\.coordinate))
        if remaining.count == 1 { remaining.append(leg.destination.coordinate) }
        return RouteGeometry(all: all, flown: flown, remaining: remaining)
    }

    private func coordinatesNearlyEqual(
        _ lhs: CLLocationCoordinate2D,
        _ rhs: CLLocationCoordinate2D
    ) -> Bool {
        abs(lhs.latitude - rhs.latitude) < 0.000_001 &&
            abs(lhs.longitude - rhs.longitude) < 0.000_001
    }

    private func airportDot(_ airport: Airport, filled: Bool) -> some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(filled ? accent : Color.black.opacity(0.6))
                    .frame(width: 14, height: 14)
                Circle()
                    .strokeBorder(.white.opacity(0.9), lineWidth: 1.5)
                    .frame(width: 14, height: 14)
            }
        }
        .accessibilityLabel(airport.code)
    }

    private var planeMarker: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.black.opacity(0.35), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 17
                    )
                )
                .frame(width: 34, height: 34)
            // Deliberately NOT scaled: a map annotation is drawn in map
            // space, not text space. Growing the aircraft with the reader's
            // text size makes it cover the route it is flying.
            Image(systemName: "airplane")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                // SF airplane points along +x (east / 90°).
                .rotationEffect(.degrees(session.currentCourse - 90))
        }
        .accessibilityLabel("Your aircraft")
    }

    // MARK: Camera

    private func updateCamera(animated: Bool, tracking: Bool = false) {
        let target: MapCameraPosition
        switch cameraMode {
        case .route:
            target = .automatic
        case .follow:
            target = .camera(MapCamera(
                centerCoordinate: session.currentCoordinate,
                distance: 220_000,
                heading: 0,
                pitch: 0
            ))
        }
        if !animated {
            cameraPosition = target
        } else if tracking {
            // Match the session tick so successive segments join smoothly.
            withAnimation(.linear(duration: 0.55)) { cameraPosition = target }
        } else {
            withAnimation(.smooth(duration: 1.0)) { cameraPosition = target }
        }
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
