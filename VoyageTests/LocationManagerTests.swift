import XCTest
import CoreLocation
@testable import Voyage

/// A stand-in for CoreLocation. Records what was asked of it so the one-shot
/// rules can be checked without any XPC to `locationd`.
@MainActor
private final class StubRequester: LocationRequesting {
    var status: CLAuthorizationStatus
    var statusAfterPrompt: CLAuthorizationStatus
    var fix: LocationFix

    private(set) var authorizationRequests = 0
    private(set) var locationRequests = 0

    init(status: CLAuthorizationStatus,
         statusAfterPrompt: CLAuthorizationStatus = .authorizedWhenInUse,
         fix: LocationFix = .unavailable) {
        self.status = status
        self.statusAfterPrompt = statusAfterPrompt
        self.fix = fix
    }

    func authorizationStatus() async -> CLAuthorizationStatus { status }

    func requestWhenInUseAuthorization() async -> CLAuthorizationStatus {
        authorizationRequests += 1
        status = statusAfterPrompt
        return statusAfterPrompt
    }

    func requestLocation() async -> LocationFix {
        locationRequests += 1
        return fix
    }
}

@MainActor
final class LocationManagerTests: XCTestCase {

    /// Somewhere over Cambridge, MA. Nearest catalog airport is BOS.
    private let nearBoston = CLLocation(latitude: 42.3736, longitude: -71.1097)
    /// Somewhere over Queens, NY. Nearest catalog airport is JFK.
    private let nearNewYork = CLLocation(latitude: 40.7282, longitude: -73.7949)

    private var originalOrigin = "BOS"

    override func setUp() async throws {
        try await super.setUp()
        originalOrigin = SettingsStore.shared.resolvedOriginCode
    }

    override func tearDown() async throws {
        SettingsStore.shared.resolvedOriginCode = originalOrigin
        try await super.tearDown()
    }

    private func resolve(_ stub: StubRequester) async -> LocationManager {
        let manager = LocationManager(requester: { stub })
        manager.resolveHomeAirport()
        let task = manager.resolveTask
        await task?.value
        return manager
    }

    func testAuthorizedResolutionStoresNearestAirport() async {
        SettingsStore.shared.resolvedOriginCode = "SFO"
        let stub = StubRequester(status: .authorizedWhenInUse, fix: .location(nearNewYork))
        let manager = await resolve(stub)

        XCTAssertEqual(SettingsStore.shared.resolvedOriginCode, Airport.nearest(to: nearNewYork).code)
        XCTAssertEqual(SettingsStore.shared.resolvedOriginCode, "JFK")
        XCTAssertEqual(stub.authorizationRequests, 0, "Permission is only requested when undetermined")
        XCTAssertEqual(stub.locationRequests, 1)
        XCTAssertFalse(manager.resolving)
    }

    func testUndeterminedAuthorizationIsRequestedOnce() async {
        let stub = StubRequester(status: .notDetermined,
                                 statusAfterPrompt: .authorizedWhenInUse,
                                 fix: .location(nearBoston))
        let manager = await resolve(stub)

        XCTAssertEqual(stub.authorizationRequests, 1)
        XCTAssertEqual(stub.locationRequests, 1)
        XCTAssertEqual(SettingsStore.shared.resolvedOriginCode, "BOS")

        // A second appearance must not re-prompt or re-request once resolved.
        manager.resolveHomeAirport()
        await manager.resolveTask?.value
        XCTAssertEqual(stub.authorizationRequests, 1)
        XCTAssertEqual(stub.locationRequests, 1)
    }

    func testDeniedAuthorizationKeepsStoredOrigin() async {
        SettingsStore.shared.resolvedOriginCode = "LAX"
        let stub = StubRequester(status: .denied, fix: .location(nearBoston))
        _ = await resolve(stub)

        XCTAssertEqual(stub.locationRequests, 0, "A denied traveler is never asked for a fix")
        XCTAssertEqual(SettingsStore.shared.resolvedOriginCode, "LAX",
                       "Failure silently keeps the stored default")
    }

    func testDeclinedPromptKeepsStoredOrigin() async {
        SettingsStore.shared.resolvedOriginCode = "LAX"
        let stub = StubRequester(status: .notDetermined,
                                 statusAfterPrompt: .denied,
                                 fix: .location(nearBoston))
        _ = await resolve(stub)

        XCTAssertEqual(stub.authorizationRequests, 1)
        XCTAssertEqual(stub.locationRequests, 0)
        XCTAssertEqual(SettingsStore.shared.resolvedOriginCode, "LAX")
    }

    func testUnavailableFixKeepsStoredOriginAndAllowsRetry() async {
        SettingsStore.shared.resolvedOriginCode = "LAX"
        let stub = StubRequester(status: .authorizedWhenInUse, fix: .unavailable)
        let manager = await resolve(stub)

        XCTAssertEqual(SettingsStore.shared.resolvedOriginCode, "LAX")

        // Nothing resolved, so a later appearance is allowed to try again.
        stub.fix = .location(nearBoston)
        manager.resolveHomeAirport()
        await manager.resolveTask?.value
        XCTAssertEqual(stub.locationRequests, 2)
        XCTAssertEqual(SettingsStore.shared.resolvedOriginCode, "BOS")
    }

    /// The crash this guards: `LocationManager()` runs inside SwiftUI's
    /// `@State` initializer during view-body evaluation, so it must not build
    /// or touch a `CLLocationManager`.
    func testInitDoesNotBuildTheRequester() async {
        let factory = CountingFactory()
        let manager = LocationManager(requester: { factory.make() })
        XCTAssertEqual(factory.built, 0, "No CoreLocation object may be created at init time")
        XCTAssertFalse(manager.resolving)

        manager.resolveHomeAirport()
        await manager.resolveTask?.value
        XCTAssertEqual(factory.built, 1, "The requester is built lazily, once, off the launch path")
    }
}

@MainActor
private final class CountingFactory {
    private(set) var built = 0

    func make() -> LocationRequesting {
        built += 1
        return StubRequester(status: .denied)
    }
}

// MARK: - Catalog reach

@MainActor
final class NearestAirportBoundsTests: XCTestCase {
    /// Central London: 5,500 km from the closest catalog airport (BOS).
    private let london = CLLocation(latitude: 51.5074, longitude: -0.1278)
    /// Cambridge, MA: a few km from BOS.
    private let nearBoston = CLLocation(latitude: 42.3736, longitude: -71.1097)

    func testNearestWithinBoundReturnsTheAirportWhenClose() {
        XCTAssertEqual(Airport.nearest(to: nearBoston, within: LocationManager.maximumOriginDistance)?.code, "BOS")
    }

    func testNearestWithinBoundIsNilAcrossAnOcean() {
        XCTAssertNil(Airport.nearest(to: london, within: LocationManager.maximumOriginDistance),
                     "A traveler outside the catalog's reach must not be told their location is JFK")
    }
}
