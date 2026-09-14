import MapKit
import simd
import SwiftUI

/// Continuous in-window world renderer. Apple's satellite flyover is the one
/// streamed provider; the deterministic procedural world is the complete
/// offline and transition frame beneath it.
struct RealWorldTwinView<ProceduralFallback: View, ForegroundOverlay: View>: View {
    let pose: WorldCameraPose
    let realWorldTwinEnabled: Bool
    let reduceMotion: Bool

    private let proceduralFallback: () -> ProceduralFallback
    private let foregroundOverlay: () -> ForegroundOverlay

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @ObservedObject private var availability = WorldSceneryAvailability.shared
    @State private var mapKitLoadState: WorldSceneryLoadState = .loading
    /// Once MapKit has rendered a frame, keep it visible through tile refreshes
    /// and shade interaction so the procedural fallback never flashes through.
    @State private var mapKitHasRenderedFrame = false

    init(
        pose: WorldCameraPose,
        realWorldTwinEnabled: Bool,
        reduceMotion: Bool,
        @ViewBuilder proceduralFallback: @escaping () -> ProceduralFallback,
        @ViewBuilder foregroundOverlay: @escaping () -> ForegroundOverlay
    ) {
        self.pose = pose
        self.realWorldTwinEnabled = realWorldTwinEnabled
        self.reduceMotion = reduceMotion
        self.proceduralFallback = proceduralFallback
        self.foregroundOverlay = foregroundOverlay
    }

    var body: some View {
        ZStack {
            // Kept alive beneath streamed providers so offline/failure changes
            // always crossfade onto a complete frame instead of a blank pane.
            proceduralFallback()

            if WorldSceneryLayerPolicy.needsMapKit(under: provider) {
                // While the satellite tiles are still loading, a neutral cover
                // hides the procedural ("fake") scene — the traveler sees a calm
                // dark pane (matching the departure curtain) that fades to the
                // live map, never the illustrated fallback. The cover sits
                // UNDER the map and stays until the map fails: crossfading the
                // two at once let the drawn world show through mid-fade for a
                // few frames (QA/video/tear-raw.mp4, 36.5 s: a green flash
                // between the dark pane and the satellite). Offline/failed
                // states drop the cover and reveal the procedural world instead.
                if mapKitLoadState != .failed {
                    neutralLoadingCover
                        .transition(.opacity)
                }

                MapKitSceneryView(
                    pose: pose,
                    loadStateChanged: mapKitLoadStateDidChange
                )
                .opacity(mapKitIsVisible ? 1 : 0)
                .transition(.opacity)
            }

            AttributionProtectedOverlay {
                // Wing, glass, precipitation, and forecast-driven Metal
                // atmosphere. The old always-on altitude film was removed — the
                // map stays clear unless the forecast actually calls for haze or
                // cloud (which the shader draws across the whole pane).
                foregroundOverlay()
            }
        }
        .clipped()
        .animation(.easeInOut(duration: effectiveReduceMotion ? 0.01 : 0.38), value: provider)
        .animation(.easeInOut(duration: effectiveReduceMotion ? 0.01 : 0.3), value: mapKitLoadState)
        .onChange(of: provider) { oldProvider, newProvider in
            if !WorldSceneryLayerPolicy.needsMapKit(under: oldProvider),
               WorldSceneryLayerPolicy.needsMapKit(under: newProvider) {
                mapKitLoadState = .loading
            }
            if !WorldSceneryLayerPolicy.needsMapKit(under: newProvider) {
                mapKitHasRenderedFrame = false
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Real-world passenger window scenery")
        .accessibilityIdentifier("real-world-twin-scenery")
    }

    private var provider: WorldSceneryProviderKind {
        WorldSceneryProviderPolicy.provider(
            realWorldTwinEnabled: realWorldTwinEnabled,
            appIsActive: scenePhase == .active,
            isOnline: availability.isOnline &&
                WorldSceneryConfiguration.streamedSceneryAllowedByProcess,
            thermalState: availability.thermalState
        )
    }

    private var effectiveReduceMotion: Bool {
        reduceMotion || systemReduceMotion
    }

    private var mapKitIsVisible: Bool {
        guard WorldSceneryLayerPolicy.needsMapKit(under: provider) else { return false }
        return mapKitHasRenderedFrame || mapKitLoadState.hasRenderableFrame
    }

    /// Calm dark pane shown over the window until the satellite is ready, in the
    /// departure-curtain tone so the hand-off reads as one continuous load.
    private var neutralLoadingCover: some View {
        LinearGradient(
            colors: [Color(hex: "0D1531"), Color(hex: "050713")],
            startPoint: .top, endPoint: .bottom
        )
        .accessibilityHidden(true)
    }

    private func mapKitLoadStateDidChange(_ state: WorldSceneryLoadState) {
        guard mapKitLoadState != state else { return }
        mapKitLoadState = state
        if state == .ready {
            mapKitHasRenderedFrame = true
            // The window owns a real frame now, so the departure gate is
            // satisfied and the invisible warm map has done its job — release
            // it rather than carry an extra MKMapView through the flight.
            DepartureReadiness.shared.markMapRendered()
            MapWarmer.shared.cancel()
        } else if state == .failed {
            mapKitHasRenderedFrame = false
        }
    }
}

extension RealWorldTwinView where ForegroundOverlay == EmptyView {
    init(
        pose: WorldCameraPose,
        realWorldTwinEnabled: Bool,
        reduceMotion: Bool,
        @ViewBuilder proceduralFallback: @escaping () -> ProceduralFallback
    ) {
        self.init(
            pose: pose,
            realWorldTwinEnabled: realWorldTwinEnabled,
            reduceMotion: reduceMotion,
            proceduralFallback: proceduralFallback,
            foregroundOverlay: { EmptyView() }
        )
    }
}

extension RealWorldTwinView where
    ProceduralFallback == DefaultWorldSceneryFallback,
    ForegroundOverlay == EmptyView
{
    init(
        pose: WorldCameraPose,
        realWorldTwinEnabled: Bool,
        reduceMotion: Bool
    ) {
        self.init(
            pose: pose,
            realWorldTwinEnabled: realWorldTwinEnabled,
            reduceMotion: reduceMotion,
            proceduralFallback: {
                DefaultWorldSceneryFallback(altitudeMeters: pose.altitudeMeters)
            },
            foregroundOverlay: { EmptyView() }
        )
    }
}

/// A deterministic last-resort frame for offline launches. The primary and
/// secondary renderers remain real 3D geospatial sources whenever online.
struct DefaultWorldSceneryFallback: View {
    let altitudeMeters: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.25, green: 0.53, blue: 0.77),
                             Color(red: 0.70, green: 0.82, blue: 0.88)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Canvas { context, size in
                    let altitudeFade = min(0.72, max(0.24, altitudeMeters / 15_000))
                    for layer in 0..<4 {
                        let depth = Double(layer) / 3
                        var ridge = Path()
                        ridge.move(to: CGPoint(x: 0, y: size.height * (0.58 + depth * 0.09)))
                        for index in 0...12 {
                            let x = size.width * Double(index) / 12
                            let wave = sin(Double(index) * 1.73 + Double(layer) * 0.91)
                            let y = size.height * (0.59 + depth * 0.09 - wave * (0.025 + depth * 0.012))
                            ridge.addLine(to: CGPoint(x: x, y: y))
                        }
                        ridge.addLine(to: CGPoint(x: size.width, y: size.height))
                        ridge.addLine(to: CGPoint(x: 0, y: size.height))
                        ridge.closeSubpath()
                        context.fill(
                            ridge,
                            with: .color(Color(red: 0.23 + depth * 0.12,
                                               green: 0.31 + depth * 0.11,
                                               blue: 0.29 + depth * 0.09)
                                .opacity(1 - altitudeFade * depth))
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Gives overlay content full window geometry, then masks only the provider's
/// attribution band. This avoids moving the wing/horizon while guaranteeing
/// that tint, haze, glass, and precipitation cannot cover legal marks.
private struct AttributionProtectedOverlay<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            content()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .mask(alignment: .top) {
                    Rectangle()
                        .frame(
                            width: geometry.size.width,
                            height: max(
                                0,
                                geometry.size.height - WorldSceneryAttributionLayout.protectedHeight
                            )
                        )
                        .frame(maxHeight: .infinity, alignment: .top)
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - MapKit online provider

private struct MapKitSceneryView: UIViewRepresentable {
    let pose: WorldCameraPose
    let loadStateChanged: @MainActor (WorldSceneryLoadState) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.mapType = .satelliteFlyover
        map.isOpaque = false
        map.backgroundColor = .clear
        map.isUserInteractionEnabled = false
        map.isPitchEnabled = true
        map.isRotateEnabled = true
        map.showsBuildings = true
        map.showsTraffic = false
        map.showsCompass = false
        map.showsScale = false
        map.pointOfInterestFilter = .excludingAll
        map.layoutMargins = UIEdgeInsets(
            top: 0,
            left: WorldSceneryAttributionLayout.horizontalInset,
            bottom: WorldSceneryAttributionLayout.bottomInset,
            right: WorldSceneryAttributionLayout.horizontalInset
        )
        context.coordinator.attach(to: map)
        context.coordinator.update(pose: pose)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.update(pose: pose)
    }

    static func dismantleUIView(_ map: MKMapView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(loadStateChanged: loadStateChanged)
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        private weak var map: MKMapView?
        private let loadStateChanged: @MainActor (WorldSceneryLoadState) -> Void
        private var loadState: WorldSceneryLoadState = .loading
        private var didFallbackFromFlyover = false
        private var departureAltitudeFloor: Double?
        private var displayedPose: WorldCameraPose?
        private var lastFrameTime: CFTimeInterval?

        init(loadStateChanged: @escaping @MainActor (WorldSceneryLoadState) -> Void) {
            self.loadStateChanged = loadStateChanged
        }

        func attach(to map: MKMapView) {
            self.map = map
        }

        func detach() {
            map?.delegate = nil
            map = nil
            displayedPose = nil
            lastFrameTime = nil
        }

        func update(pose: WorldCameraPose) {
            guard loadState != .failed, let map else { return }
            var pose = pose
            if pose.altitudeMeters < 3_000 {
                let incoming = pose.altitudeMeters
                if let floor = departureAltitudeFloor {
                    pose = WorldCameraPose(
                        coordinate: pose.coordinate,
                        altitudeMeters: max(floor, incoming),
                        headingDegrees: pose.headingDegrees,
                        tiltDegrees: pose.tiltDegrees,
                        rollDegrees: pose.rollDegrees,
                        rangeMeters: pose.rangeMeters,
                        fieldOfViewDegrees: pose.fieldOfViewDegrees
                    )
                }
                departureAltitudeFloor = max(departureAltitudeFloor ?? incoming, incoming)
            } else {
                departureAltitudeFloor = nil
            }

            let now = CACurrentMediaTime()
            let delta = lastFrameTime.map { now - $0 } ?? 0
            lastFrameTime = now
            // Keep altitude responsive during compressed QA climbs — heavy
            // smoothing reads as feet stuck low while the HUD keeps ticking up.
            let timeConstant = FlightSession.shortFlightsEnabled ? 0.08 : 0.35
            let blend = delta > 0 ? min(1, 1 - exp(-delta / timeConstant)) : 1
            let smoothed = Self.blendedPose(from: displayedPose ?? pose, to: pose, amount: blend)
            displayedPose = smoothed

            let projection = WorldSceneryProjection(pose: smoothed)
            map.camera = MKMapCamera(
                lookingAtCenter: projection.targetCoordinate,
                fromDistance: projection.rangeMeters,
                pitch: projection.tiltDegrees,
                heading: projection.headingDegrees
            )
        }

        private static func blendedPose(
            from source: WorldCameraPose,
            to target: WorldCameraPose,
            amount: Double
        ) -> WorldCameraPose {
            let t = min(1, max(0, amount))
            let sourceECEF = FlightGeodesy.ecef(
                FlightGeodeticPoint(
                    coordinate: source.coordinate,
                    altitudeMeters: source.altitudeMeters
                )
            )
            let targetECEF = FlightGeodesy.ecef(
                FlightGeodeticPoint(
                    coordinate: target.coordinate,
                    altitudeMeters: target.altitudeMeters
                )
            )
            let blendedECEF = sourceECEF + (targetECEF - sourceECEF) * t
            let blendedPoint = FlightGeodesy.geodetic(fromECEF: blendedECEF)
            let heading = lerpAngleDegrees(source.headingDegrees, target.headingDegrees, t: t)
            let tilt = source.tiltDegrees + (target.tiltDegrees - source.tiltDegrees) * t
            let roll = source.rollDegrees + (target.rollDegrees - source.rollDegrees) * t
            let range: Double?
            if let sourceRange = source.rangeMeters, let targetRange = target.rangeMeters {
                range = sourceRange + (targetRange - sourceRange) * t
            } else {
                range = target.rangeMeters ?? source.rangeMeters
            }
            let fieldOfView = source.fieldOfViewDegrees
                + (target.fieldOfViewDegrees - source.fieldOfViewDegrees) * t
            return WorldCameraPose(
                coordinate: blendedPoint.coordinate,
                altitudeMeters: blendedPoint.altitudeMeters,
                headingDegrees: heading,
                tiltDegrees: tilt,
                rollDegrees: roll,
                rangeMeters: range,
                fieldOfViewDegrees: fieldOfView
            )
        }

        private static func lerpAngleDegrees(_ from: Double, _ to: Double, t: Double) -> Double {
            var delta = (to - from).truncatingRemainder(dividingBy: 360)
            if delta > 180 { delta -= 360 }
            if delta < -180 { delta += 360 }
            return from + delta * t
        }

        func mapViewWillStartLoadingMap(_ mapView: MKMapView) {
            // Keep a previously completed frame visible while MapKit refreshes
            // tiles for the next camera. A failed layer stays hidden until a
            // fresh render succeeds.
            if loadState == .failed {
                publish(.loading)
            }
        }

        func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
            // Continuous flight motion can prevent `fullyRendered` from ever
            // becoming true. Any completed render is a usable best-available
            // frame; an explicit load error below still hides it immediately.
            guard loadState != .failed else { return }
            publish(.ready)
        }

        func mapViewDidFailLoadingMap(_ mapView: MKMapView, withError error: Error) {
            if !didFallbackFromFlyover, mapView.mapType == .satelliteFlyover {
                didFallbackFromFlyover = true
                mapView.mapType = .hybridFlyover
                publish(.loading)
                return
            }
            publish(.failed)
        }

        private func publish(_ state: WorldSceneryLoadState) {
            guard state != loadState else { return }
            loadState = state
            // Delegate callbacks are normally main-thread, but deferring also
            // avoids mutating SwiftUI state during a representable update.
            Task { @MainActor [loadStateChanged] in
                loadStateChanged(state)
            }
        }
    }
}
