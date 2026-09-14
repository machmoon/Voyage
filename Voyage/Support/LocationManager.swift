import Foundation
import CoreLocation
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// The outcome of a single location request.
enum LocationFix {
    case location(CLLocation)
    case unavailable
}

/// The slice of CoreLocation the origin resolver needs.
///
/// The seam exists so the one-shot resolution rules (permission only when
/// undetermined, one fix, silent failure) can be tested without CoreLocation's
/// XPC. Structure follows AsyncLocationKit, which injects the location manager
/// the same way: see `Sources/AsyncLocationKit/AsyncLocationManager.swift`
/// (`init(locationManager:desiredAccuracy:allowsBackgroundLocationUpdates:)`).
@MainActor
protocol LocationRequesting: AnyObject {
    func authorizationStatus() async -> CLAuthorizationStatus
    /// Prompts for When In Use and returns the status it settles on.
    func requestWhenInUseAuthorization() async -> CLAuthorizationStatus
    /// Asks for one fix. Never throws: a failure is `.unavailable`.
    func requestLocation() async -> LocationFix
}

/// CoreLocation-backed `LocationRequesting`.
///
/// Everything here is deliberately lazy. `CLLocationManager()`'s initializer,
/// its `authorizationStatus` getter and `requestWhenInUseAuthorization()` each
/// make a *synchronous* XPC round trip to `locationd`. Doing that from a
/// SwiftUI `.onAppear` puts the main thread into a synchronous wait while
/// FrontBoard is still timing scene creation, which is a 0x8BADF00D
/// `scene-create` watchdog kill on a machine that is under load or cold. So no
/// CoreLocation object is created, and no CoreLocation property is read, until
/// the app is active and the scene is already on screen.
///
/// The manager stays on the main actor on purpose. CLLocationManager captures
/// the run loop it is created on and delivers its delegate callbacks there, so
/// creating it on an arbitrary background queue is unsupported. Both of the
/// maintained async wrappers do the same: AsyncLocationKit documents
/// "Always initialize `AsyncLocationManager` synchronously on the main thread"
/// (`Sources/AsyncLocationKit/AsyncLocationManager.swift`), and SwiftLocation
/// keeps a single `CLLocationManager` behind its async bridge
/// (`Sources/SwiftLocation/Location.swift`).
@MainActor
final class CoreLocationRequester: NSObject, LocationRequesting {
    private var manager: CLLocationManager?
    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var fixContinuation: CheckedContinuation<LocationFix, Never>?

    /// The manager, created on first use and never before the app is active.
    private func activeManager() async -> CLLocationManager {
        await Self.waitUntilApplicationIsActive()
        if let manager { return manager }
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        self.manager = manager
        return manager
    }

    func authorizationStatus() async -> CLAuthorizationStatus {
        await activeManager().authorizationStatus
    }

    func requestWhenInUseAuthorization() async -> CLAuthorizationStatus {
        let manager = await activeManager()
        guard manager.authorizationStatus == .notDetermined else {
            return manager.authorizationStatus
        }
        return await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    func requestLocation() async -> LocationFix {
        let manager = await activeManager()
        return await withCheckedContinuation { continuation in
            fixContinuation = continuation
            // `requestLocation()` always answers, with a fix or an error, so
            // the continuation is resumed exactly once by the delegate below.
            manager.requestLocation()
        }
    }

    /// Suspends until the process is foreground-active.
    ///
    /// During a normal launch `.onAppear` runs while the scene is still being
    /// built and the app is `.inactive`, so this costs roughly one frame. On a
    /// background or prewarm launch it waits, which is the point: no locationd
    /// traffic at all until there is a screen to resolve an origin for.
    private static func waitUntilApplicationIsActive() async {
        #if canImport(UIKit)
        if UIApplication.shared.applicationState == .active { return }
        let box = ObserverBox()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            box.token = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                box.stopObserving()
                continuation.resume()
            }
        }
        #endif
    }

    /// Holds the one-shot activation observer so it can unregister itself.
    ///
    /// `@unchecked Sendable` because both the write and the read happen on the
    /// main queue: the registration runs on the main actor, and the block is
    /// delivered on `OperationQueue.main`.
    private final class ObserverBox: @unchecked Sendable {
        var token: NSObjectProtocol?

        func stopObserving() {
            guard let token else { return }
            NotificationCenter.default.removeObserver(token)
            self.token = nil
        }
    }

    // MARK: - CLLocationManagerDelegate

    private func finishAuthorization(_ status: CLAuthorizationStatus) {
        guard status != .notDetermined, let continuation = authorizationContinuation else { return }
        authorizationContinuation = nil
        continuation.resume(returning: status)
    }

    private func finishFix(_ fix: LocationFix) {
        guard let continuation = fixContinuation else { return }
        fixContinuation = nil
        continuation.resume(returning: fix)
    }
}

// CLLocationManager is not thread-safe: it captures the run loop it was created
// on and delivers these callbacks there, which here is the main one. The
// conformance is `@preconcurrency` so the methods stay main-actor isolated with
// the rest of the class, which keeps the manager inside exactly one isolation
// domain instead of hopping out to `nonisolated` and back.
extension CoreLocationRequester: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        finishAuthorization(manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finishFix(locations.last.map { LocationFix.location($0) } ?? .unavailable)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finishFix(.unavailable)
    }
}

/// Requests location once and resolves the nearest airport as the origin.
///
/// There is no "home airport" to pick: the origin is always the airport
/// nearest the traveler, resolved automatically into
/// `SettingsStore.shared.resolvedOriginCode`.
@MainActor
@Observable
final class LocationManager {
    /// True while we're waiting on permission or a fix.
    private(set) var resolving = false

    /// The in-flight resolution. Exposed so tests can await it.
    @ObservationIgnored private(set) var resolveTask: Task<Void, Never>?

    /// How the CoreLocation adapter is built, supplied at construction and
    /// never mutated afterwards. An immutable `nonisolated let` rather than a
    /// settable property so the initializers stay isolation-free (the default
    /// one has to run during SwiftUI view-body evaluation) and so there is no
    /// test-only branch on the production path.
    @ObservationIgnored private nonisolated let makeRequester: @Sendable @MainActor () -> LocationRequesting
    @ObservationIgnored private var requester: LocationRequesting?
    @ObservationIgnored private var running = false
    @ObservationIgnored private var resolved = false

    /// Cheap and CoreLocation-free on purpose. SwiftUI evaluates
    /// `@State private var locationManager = LocationManager()` every time the
    /// owning view value is built, so this initializer runs during view-body
    /// evaluation and must not touch locationd.
    nonisolated convenience init() {
        self.init(requester: { CoreLocationRequester() })
    }

    /// Farthest a sensed location may be from a catalog airport and still be
    /// called "nearest". 1,500 km covers every catalog city from its region
    /// and nothing across an ocean.
    nonisolated static let maximumOriginDistance: CLLocationDistance = 1_500_000

    /// Designated initializer. Tests pass a stub in place of CoreLocation.
    nonisolated init(requester: @escaping @Sendable @MainActor () -> LocationRequesting) {
        makeRequester = requester
    }

    /// One-shot: ask for permission if needed, then set the nearest airport
    /// as the resolved origin. Silently keeps the stored default on failure.
    ///
    /// Returns immediately. The CoreLocation work runs later, off the
    /// scene-create critical path. Safe to call on every appearance: it is a
    /// no-op once an origin has resolved, and while a resolution is running.
    func resolveHomeAirport() {
        guard !resolved, !running else { return }
        running = true
        resolving = true
        resolveTask = Task {
            await resolve()
            running = false
        }
    }

    private func resolve() async {
        defer { resolving = false }

        let requester = self.requester ?? makeRequester()
        self.requester = requester

        var status = await requester.authorizationStatus()
        if status == .notDetermined {
            status = await requester.requestWhenInUseAuthorization()
        }
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        guard case .location(let location) = await requester.requestLocation() else { return }

        // Outside the catalog's reach the app has no honest "nearest"
        // airport, so it leaves the origin unknown and Home offers "Set your
        // airport" instead of drawing a location glyph next to a guess.
        guard let nearest = Airport.nearest(to: location, within: Self.maximumOriginDistance) else { return }
        resolved = true
        SettingsStore.shared.resolvedOriginCode = nearest.code
    }
}
