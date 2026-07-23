import MapKit
import UIKit

/// Preheats Apple's satellite tiles around the origin airport the moment a focus
/// flight is booked, so by the time the in-flight real-world window mounts,
/// MapKit already has a rendered frame — the procedural fallback never flashes.
///
/// MapKit only fetches tiles for a map that is in a window, so this parks a tiny,
/// invisible `MKMapView` behind the app's window for the length of the boarding
/// ritual, then tears it down. Only the *region* matters for the tile cache, not
/// exact framing.
///
/// The warm map is also the earliest place that can honestly answer "does the
/// satellite have a frame yet?", so it reports into `DepartureReadiness` —
/// that's what lets the departure curtain hold until the window is loadable.
@MainActor
final class MapWarmer {
    static let shared = MapWarmer()

    /// The warm map is released by the in-flight window as soon as *it* has a
    /// rendered frame. This is only the backstop for a ritual that is abandoned
    /// or left sitting: long enough that it can never expire mid-boarding,
    /// short enough that an invisible `MKMapView` can't be leaked for a whole
    /// focus flight.
    private static let maximumWarmDuration: Duration = .seconds(300)

    private var mapView: MKMapView?
    private var teardown: Task<Void, Never>?
    private let delegate = WarmMapDelegate()

    private init() {}

    /// Warm the tiles around `coordinate`, looking along `headingDegrees` from a
    /// takeoff-like low, near-horizon camera. No-op if a scene window isn't found.
    func warm(around coordinate: CLLocationCoordinate2D, headingDegrees: Double) {
        cancel()
        DepartureReadiness.shared.resetForNewBooking()

        guard let window = activeWindow() else { return }

        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 320, height: 320))
        map.delegate = delegate
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

        teardown = Task { [weak self] in
            try? await Task.sleep(for: Self.maximumWarmDuration)
            guard !Task.isCancelled else { return }
            self?.cancel()
        }
    }

    /// Release the warm map. Called by the in-flight window once it owns a
    /// rendered frame of its own, and whenever a booking is abandoned — never
    /// leave an `MKMapView` alive in flight.
    func cancel() {
        teardown?.cancel()
        teardown = nil
        mapView?.delegate = nil
        mapView?.removeFromSuperview()
        mapView = nil
    }

    private func activeWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
    }
}

/// Reports the warm map's first completed render into the shared readiness
/// signal. A failure stays silent: the departure gate's ceiling covers it, and
/// the in-flight window may still succeed on its own.
@MainActor
private final class WarmMapDelegate: NSObject, MKMapViewDelegate {
    func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
        DepartureReadiness.shared.markMapRendered()
    }
}
