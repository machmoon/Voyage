import Foundation
import CoreLocation
import Observation

/// Requests location once and resolves the nearest home airport.
@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    /// True while we're waiting on permission or a fix.
    private(set) var resolving = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// One-shot: ask for permission if needed, then set the nearest airport
    /// as the resolved origin. Silently keeps the stored default on failure.
    func resolveHomeAirport() {
        switch manager.authorizationStatus {
        case .notDetermined:
            resolving = true
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            resolving = true
            manager.requestLocation()
        default:
            resolving = false
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if resolving { manager.requestLocation() }
        case .denied, .restricted:
            DispatchQueue.main.async { [weak self] in
                self?.resolving = false
            }
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            DispatchQueue.main.async { [weak self] in self?.resolving = false }
            return
        }
        let code = Airport.nearest(to: location).code
        DispatchQueue.main.async { [weak self] in
            self?.resolving = false
            SettingsStore.shared.resolvedOriginCode = code
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.resolving = false
        }
    }
}
