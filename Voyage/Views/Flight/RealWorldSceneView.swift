import SwiftUI
import MapKit
import Network

/// Real satellite scenery for takeoff and landing: an Apple satellite-flyover
/// camera choreographed along the airport's actual runway, framed as if seen
/// from a side window. WindowSceneView composites its procedural sky, weather,
/// and wing over this layer and crossfades back to the fully procedural
/// renderer once the ground stops reading at altitude.
struct RealWorldSceneView: UIViewRepresentable {
    let airport: Airport
    let phase: LegPhase
    /// 0 = on the ground, 1 = cruise altitude.
    let altitudeFraction: Double
    let isLeftSide: Bool

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.mapType = .satelliteFlyover
        map.isUserInteractionEnabled = false
        map.showsCompass = false
        map.showsScale = false
        map.pointOfInterestFilter = .excludingAll
        map.isPitchEnabled = true
        context.coordinator.attach(to: map)
        context.coordinator.apply(view: self, resetClock: true)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.apply(view: self, resetClock: false)
    }

    static func dismantleUIView(_ map: MKMapView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Drives the flyover camera from a display link so motion stays smooth
    /// between the session's once-a-second state updates.
    @MainActor
    final class Coordinator {
        private weak var map: MKMapView?
        private var link: CADisplayLink?
        private var view: RealWorldSceneView?
        private var phaseStart = CACurrentMediaTime()
        private var lastPhase: LegPhase?

        func attach(to map: MKMapView) {
            self.map = map
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        func detach() {
            link?.invalidate()
            link = nil
            map = nil
        }

        func apply(view: RealWorldSceneView, resetClock: Bool) {
            if resetClock || view.phase != lastPhase {
                phaseStart = CACurrentMediaTime()
                lastPhase = view.phase
            }
            self.view = view
        }

        @objc private func tick() {
            guard let map, let view, let runway = view.airport.runway else { return }
            map.camera = Self.camera(
                for: view.phase,
                elapsed: CACurrentMediaTime() - phaseStart,
                altitudeFraction: view.altitudeFraction,
                airport: view.airport,
                runway: runway,
                isLeftSide: view.isLeftSide
            )
        }

        /// Camera framing for the current instant. We keep the real airport
        /// centered and orbit it — pulling the vantage back and lower as the
        /// flavor altitude climbs — rather than dead-reckoning a camera
        /// position that could drift off the airfield into open water.
        static func camera(for phase: LegPhase,
                           elapsed: Double,
                           altitudeFraction: Double,
                           airport: Airport,
                           runway: Airport.Runway,
                           isLeftSide: Bool) -> MKMapCamera {
            let alt = min(1, max(0, altitudeFraction))

            // Low and close on the ground so terminals and the skyline fill the
            // pane; pull back and tilt toward top-down as we gain height.
            let distance = 1_250 + alt * 22_000
            let pitch = max(38.0, 76.0 - alt * 34.0)

            // A gentle pan gives the static airfield a sense of motion. Takeoff
            // and climb sweep one way from the runway line; the approach swings
            // back toward it. The window side picks which shoulder we orbit over.
            let drift: Double
            switch phase {
            case .takeoffRoll, .climb:
                drift = min(26, elapsed * 1.4)
            case .landing:
                drift = -min(20, elapsed * 1.1)
            default: // descent / final approach
                drift = 24 - min(48, elapsed * 0.18)
            }
            let heading = normalizedHeading(runway.heading + (isLeftSide ? -55 : 55) + drift)

            return MKMapCamera(lookingAtCenter: airport.coordinate,
                               fromDistance: distance,
                               pitch: pitch,
                               heading: heading)
        }

        private static func normalizedHeading(_ degrees: Double) -> Double {
            let wrapped = degrees.truncatingRemainder(dividingBy: 360)
            return wrapped < 0 ? wrapped + 360 : wrapped
        }
    }
}

/// Process-wide reachability signal. Satellite tiles need the network; when it
/// drops, the window falls back to the procedural renderer instead of showing
/// MapKit's blank grid.
@Observable
@MainActor
final class RealSceneryReachability {
    static let shared = RealSceneryReachability()

    private(set) var isOnline = true
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = path.status == .satisfied
            }
        }
        monitor.start(queue: DispatchQueue(label: "voyage.scenery.reachability"))
    }
}
