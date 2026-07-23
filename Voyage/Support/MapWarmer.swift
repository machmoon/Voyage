import MapKit
import UIKit

/// Preheats Apple's satellite tiles around the origin airport the moment a focus
/// flight is booked, so by the time the in-flight real-world window mounts,
/// MapKit already has a rendered frame — the procedural fallback never flashes.
///
/// MapKit only fetches tiles for a map that is in a window, so this parks a tiny,
/// invisible `MKMapView` behind the app's window for a short while, then tears it
/// down. Only the *region* matters for the tile cache, not exact framing.
@MainActor
final class MapWarmer {
    static let shared = MapWarmer()

    private var mapView: MKMapView?
    private var teardown: Task<Void, Never>?

    private init() {}

    /// Warm the tiles around `coordinate`, looking along `headingDegrees` from a
    /// takeoff-like low, near-horizon camera. No-op if a scene window isn't found.
    func warm(around coordinate: CLLocationCoordinate2D, headingDegrees: Double) {
        guard let window = activeWindow() else { return }

        cancel()

        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 320, height: 320))
        map.mapType = .satelliteFlyover
        map.isUserInteractionEnabled = false
        map.isHidden = false
        map.alpha = 0.02          // effectively invisible, but still renders tiles
        map.camera = MKMapCamera(
            lookingAtCenter: coordinate,
            fromDistance: 6_000,
            pitch: 72,
            heading: headingDegrees
        )
        window.insertSubview(map, at: 0)
        mapView = map

        // Keep it alive across the boarding ritual (seat → bag → pass → curtain),
        // then remove it so it never lingers or costs memory in flight.
        teardown = Task { [weak self] in
            try? await Task.sleep(for: .seconds(40))
            self?.cancel()
        }
    }

    func cancel() {
        teardown?.cancel()
        teardown = nil
        mapView?.removeFromSuperview()
        mapView = nil
    }

    private func activeWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
    }
}
