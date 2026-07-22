import MapKit
import SwiftUI

/// Continuous in-window world renderer. Apple's satellite flyover is the one
/// streamed provider; the deterministic procedural world is the complete
/// offline and transition frame beneath it.
struct RealWorldTwinView<ProceduralFallback: View, ForegroundOverlay: View>: View {
    let pose: WorldCameraPose
    let isActive: Bool
    let realWorldTwinEnabled: Bool
    let reduceMotion: Bool

    private let proceduralFallback: () -> ProceduralFallback
    private let foregroundOverlay: () -> ForegroundOverlay

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @ObservedObject private var availability = WorldSceneryAvailability.shared
    @State private var mapKitLoadState: WorldSceneryLoadState = .loading

    init(
        pose: WorldCameraPose,
        isActive: Bool,
        realWorldTwinEnabled: Bool,
        reduceMotion: Bool,
        @ViewBuilder proceduralFallback: @escaping () -> ProceduralFallback,
        @ViewBuilder foregroundOverlay: @escaping () -> ForegroundOverlay
    ) {
        self.pose = pose
        self.isActive = isActive
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
                MapKitSceneryView(
                    pose: pose,
                    loadStateChanged: mapKitLoadStateDidChange
                )
                .opacity(mapKitIsVisible ? 1 : 0)
                .transition(.opacity)
            }

            AttributionProtectedOverlay {
                ZStack {
                    WorldAtmosphereOverlay(altitudeMeters: pose.altitudeMeters)

                    // Wing, glass, precipitation, and richer Metal atmosphere
                    // stay outside either SDK and outside its attribution zone.
                    foregroundOverlay()
                }
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
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Real-world passenger window scenery")
        .accessibilityIdentifier("real-world-twin-scenery")
    }

    private var provider: WorldSceneryProviderKind {
        WorldSceneryProviderPolicy.provider(
            realWorldTwinEnabled: realWorldTwinEnabled,
            isVisible: isActive,
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
        WorldSceneryLayerPolicy.mapKitIsVisible(
            under: provider,
            loadState: mapKitLoadState
        )
    }

    private func mapKitLoadStateDidChange(_ state: WorldSceneryLoadState) {
        guard mapKitLoadState != state else { return }
        mapKitLoadState = state
    }
}

extension RealWorldTwinView where ForegroundOverlay == EmptyView {
    init(
        pose: WorldCameraPose,
        isActive: Bool,
        realWorldTwinEnabled: Bool,
        reduceMotion: Bool,
        @ViewBuilder proceduralFallback: @escaping () -> ProceduralFallback
    ) {
        self.init(
            pose: pose,
            isActive: isActive,
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
        isActive: Bool,
        realWorldTwinEnabled: Bool,
        reduceMotion: Bool
    ) {
        self.init(
            pose: pose,
            isActive: isActive,
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

private struct WorldAtmosphereOverlay: View {
    let altitudeMeters: Double

    var body: some View {
        let haze = min(0.18, max(0.035, altitudeMeters / 120_000))
        LinearGradient(
            stops: [
                .init(color: Color(red: 0.62, green: 0.79, blue: 0.93).opacity(haze), location: 0),
                .init(color: .white.opacity(haze * 0.55), location: 0.42),
                .init(color: .clear, location: 0.78),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .blendMode(.screen)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
        private var lastPose: WorldCameraPose?

        init(loadStateChanged: @escaping @MainActor (WorldSceneryLoadState) -> Void) {
            self.loadStateChanged = loadStateChanged
        }

        func attach(to map: MKMapView) {
            self.map = map
        }

        func detach() {
            map?.delegate = nil
            map = nil
        }

        func update(pose: WorldCameraPose) {
            // A failed hidden map must not continue receiving 60/30 Hz camera
            // writes that provoke tile and mesh work behind the fallback.
            guard loadState != .failed, let map, pose != lastPose else { return }
            lastPose = pose
            let projection = WorldSceneryProjection(pose: pose)
            map.camera = MKMapCamera(
                lookingAtCenter: projection.targetCoordinate,
                fromDistance: projection.rangeMeters,
                pitch: projection.tiltDegrees,
                heading: projection.headingDegrees
            )
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
