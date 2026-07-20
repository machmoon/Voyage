import SwiftUI
import MapKit

/// The second study view: a live flight-tracker map of the route.
/// Shows the flown portion solid and the remainder faded, with the
/// aircraft at its real great-circle position. Two camera modes
/// (whole route / follow the plane) and two map styles (terrain / satellite).
struct FlightMapView: View {
    @Bindable var session: FlightSession

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
        .overlay(alignment: .bottom) { controls }
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

        // Endpoints.
        Annotation(leg.origin.code, coordinate: leg.origin.coordinate) {
            airportDot(leg.origin, filled: true)
        }
        Annotation(leg.destination.code, coordinate: leg.destination.coordinate) {
            airportDot(leg.destination, filled: isFlown)
        }

        if isCurrentLeg {
            // Flown portion: solid; remaining: faded.
            let split = session.legProgress
            let flown = GreatCircle.points(from: leg.origin.coordinate,
                                           to: leg.destination.coordinate,
                                           count: 48).prefix(upTo(split, of: 48))
            let remaining = GreatCircle.points(from: leg.origin.coordinate,
                                               to: leg.destination.coordinate,
                                               count: 48).suffix(from: max(0, upTo(split, of: 48) - 1))
            if flown.count > 1 {
                MapPolyline(coordinates: Array(flown))
                    .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
            if remaining.count > 1 {
                MapPolyline(coordinates: Array(remaining))
                    .stroke(accent.opacity(0.4),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        } else {
            MapPolyline(coordinates: [leg.origin.coordinate, leg.destination.coordinate],
                        contourStyle: .geodesic)
                .stroke(isFlown ? accent : accent.opacity(0.4),
                        style: StrokeStyle(lineWidth: isFlown ? 4 : 3, lineCap: .round))
        }
    }

    private func upTo(_ fraction: Double, of count: Int) -> Int {
        min(count, max(1, Int((fraction * Double(count - 1)).rounded()) + 1))
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
                .fill(.black.opacity(0.35))
                .frame(width: 34, height: 34)
                .blur(radius: 3)
            Image(systemName: "airplane")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 2)
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

    private var controls: some View {
        HStack(spacing: 8) {
            picker(selection: $cameraMode, options: CameraMode.allCases, id: \.rawValue)
            Spacer()
            picker(selection: $style, options: Style.allCases, id: \.rawValue)
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
                        .font(.system(size: 11, weight: .bold))
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
