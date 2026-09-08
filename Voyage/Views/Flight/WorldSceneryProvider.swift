import Combine
import CoreGraphics
import CoreLocation
import Foundation
import Network

/// Renderer-neutral geodetic camera used by every scenery provider.
///
/// `coordinate` and `altitudeMeters` describe the passenger camera, while
/// `headingDegrees` and `tiltDegrees` describe its look direction. Tilt uses
/// the map convention: 0° looks straight down and 90° looks at the horizon.
/// When `rangeMeters` is supplied by the trajectory it is preserved exactly;
/// otherwise providers derive a slant range from altitude and tilt.
struct WorldCameraPose: Equatable {
    let coordinate: CLLocationCoordinate2D
    let altitudeMeters: Double
    let headingDegrees: Double
    let tiltDegrees: Double
    let rollDegrees: Double
    let rangeMeters: Double?
    let fieldOfViewDegrees: Double

    init(
        coordinate: CLLocationCoordinate2D,
        altitudeMeters: Double,
        headingDegrees: Double,
        tiltDegrees: Double,
        rollDegrees: Double,
        rangeMeters: Double? = nil,
        fieldOfViewDegrees: Double
    ) {
        self.coordinate = coordinate
        self.altitudeMeters = altitudeMeters
        self.headingDegrees = headingDegrees
        self.tiltDegrees = tiltDegrees
        self.rollDegrees = rollDegrees
        self.rangeMeters = rangeMeters
        self.fieldOfViewDegrees = fieldOfViewDegrees
    }

    static func == (lhs: WorldCameraPose, rhs: WorldCameraPose) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
            lhs.coordinate.longitude == rhs.coordinate.longitude &&
            lhs.altitudeMeters == rhs.altitudeMeters &&
            lhs.headingDegrees == rhs.headingDegrees &&
            lhs.tiltDegrees == rhs.tiltDegrees &&
            lhs.rollDegrees == rhs.rollDegrees &&
            lhs.rangeMeters == rhs.rangeMeters &&
            lhs.fieldOfViewDegrees == rhs.fieldOfViewDegrees
    }
}

extension WorldCameraPose {
    /// Canonical bridge from the deterministic trajectory into every scenery
    /// provider. Passenger pitch is elevation from the horizon, whereas both
    /// map SDKs use tilt from nadir.
    init(_ pose: PassengerCameraPose) {
        self.init(
            coordinate: pose.coordinate,
            altitudeMeters: pose.altitudeMeters,
            headingDegrees: pose.headingDegrees,
            tiltDegrees: min(90, max(0, 90 + pose.pitchDegrees)),
            rollDegrees: pose.rollDegrees,
            rangeMeters: pose.rangeMeters,
            fieldOfViewDegrees: pose.fieldOfViewDegrees
        )
    }
}

enum WorldSceneryProviderKind: Equatable {
    case mapKit
    case procedural
}

/// MapKit lifecycle used to keep its streamed layer off the deterministic
/// fallback until it has rendered a usable frame.
enum WorldSceneryLoadState: Equatable {
    case loading
    case ready
    case failed

    var hasRenderableFrame: Bool { self == .ready }
}

/// Space kept free of cabin/weather overlays and inset from rounded window
/// corners so MapKit's own attribution remains fully legible. MapKit is the
/// only satellite provider shipped, and App Review 5.2.5 turns on that credit
/// staying visible, so nothing may be drawn over this band.
enum WorldSceneryAttributionLayout {
    static let protectedHeight: CGFloat = 52
    static let horizontalInset: CGFloat = 28
    static let bottomInset: CGFloat = 44
}

/// Unit-testable layer policy. Exactly one streamed 3D engine is mounted at a
/// time; the procedural world is the complete transition/failure frame.
struct WorldSceneryLayerPolicy {
    static func needsMapKit(under provider: WorldSceneryProviderKind) -> Bool {
        provider == .mapKit
    }

    static func mapKitIsVisible(
        under provider: WorldSceneryProviderKind,
        loadState: WorldSceneryLoadState
    ) -> Bool {
        needsMapKit(under: provider) && loadState.hasRenderableFrame
    }

}

/// Runtime inputs used to choose a provider. Apple's satellite flyover is the
/// only streamed source; everything else falls back to the deterministic
/// procedural world, which is always a complete frame.
struct WorldSceneryProviderPolicy {
    static func provider(
        realWorldTwinEnabled: Bool,
        appIsActive: Bool,
        isOnline: Bool,
        thermalState: ProcessInfo.ThermalState
    ) -> WorldSceneryProviderKind {
        guard realWorldTwinEnabled, appIsActive else {
            return .procedural
        }
        guard isOnline else { return .procedural }

        // Streamed tiles and their mesh work are the expensive part of the
        // window. Drop to the procedural world once the OS reports serious
        // thermal pressure rather than competing with it.
        guard thermalState != .serious, thermalState != .critical else {
            return .procedural
        }
        return .mapKit
    }
}

enum WorldSceneryConfiguration {
    /// Deterministic CI/QA seam. It selects the exact same offline provider
    /// policy as a lost network path without mutating flight/session state.
    static var streamedSceneryAllowedByProcess: Bool {
        ProcessInfo.processInfo.environment["VOYAGE_FORCE_OFFLINE_SCENERY"] != "1"
    }
}

/// Shared network and thermal signal for renderer selection. It deliberately
/// does not own any SDK objects, keeping failure/fallback policy testable.
@MainActor
final class WorldSceneryAvailability: ObservableObject {
    static let shared = WorldSceneryAvailability()

    @Published private(set) var isOnline: Bool
    @Published private(set) var isConstrained: Bool
    @Published private(set) var thermalState: ProcessInfo.ThermalState

    private let pathMonitor: NWPathMonitor
    private let monitorQueue = DispatchQueue(label: "voyage.world-scenery.reachability", qos: .utility)
    private var thermalObserver: NSObjectProtocol?

    private init(
        pathMonitor: NWPathMonitor = NWPathMonitor(),
        processInfo: ProcessInfo = .processInfo
    ) {
        self.pathMonitor = pathMonitor
        // Begin conservatively so an offline cold launch cannot briefly mount
        // a streamed provider over the complete procedural frame. NWPathMonitor
        // promotes the provider only after it observes a satisfied path.
        self.isOnline = false
        self.isConstrained = false
        self.thermalState = processInfo.thermalState

        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.isOnline = path.status == .satisfied
                self?.isConstrained = path.isConstrained
            }
        }
        pathMonitor.start(queue: monitorQueue)

        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: processInfo,
            queue: .main
        ) { [weak self, weak processInfo] _ in
            guard let processInfo else { return }
            Task { @MainActor [weak self] in
                self?.thermalState = processInfo.thermalState
            }
        }
    }

    deinit {
        pathMonitor.cancel()
        if let thermalObserver {
            NotificationCenter.default.removeObserver(thermalObserver)
        }
    }
}

/// Provider-neutral orientation/range plus the MapKit look-at target derived
/// from the passenger eye pose. Expressed as an eye coordinate plus an
/// equivalent orbit, because MapKit's camera API is target-based.
struct WorldSceneryProjection {
    let targetCoordinate: CLLocationCoordinate2D
    let targetAltitudeMeters: Double
    let headingDegrees: Double
    let tiltDegrees: Double
    let rollDegrees: Double
    let rangeMeters: Double
    let fieldOfViewDegrees: Double

    init(pose: WorldCameraPose) {
        let altitude = max(2.4, pose.altitudeMeters.isFinite ? pose.altitudeMeters : 2.4)
        let tilt = min(87.5, max(0, pose.tiltDegrees.isFinite ? pose.tiltDegrees : 75))
        let heading = Self.normalizedDegrees(pose.headingDegrees)
        let radiansFromNadir = tilt * .pi / 180

        let derivedRange = altitude / max(0.043619, cos(radiansFromNadir))
        let range = min(450_000, max(8, pose.rangeMeters ?? derivedRange))
        let horizontalDistance = min(450_000, max(0, range * sin(radiansFromNadir)))
        let verticalDistance = range * cos(radiansFromNadir)

        self.targetCoordinate = Self.destination(
            from: pose.coordinate,
            bearingDegrees: heading,
            distanceMeters: horizontalDistance
        )
        // MapKit's target/range/tilt orbit resolves back to the geodetic
        // passenger camera, including a window-height tarmac view.
        self.targetAltitudeMeters = altitude - verticalDistance
        self.headingDegrees = heading
        self.tiltDegrees = tilt
        self.rollDegrees = min(45, max(-45, pose.rollDegrees.isFinite ? pose.rollDegrees : 0))
        self.rangeMeters = range
        self.fieldOfViewDegrees = min(100, max(20, pose.fieldOfViewDegrees.isFinite ? pose.fieldOfViewDegrees : 55))
    }

    private static func destination(
        from coordinate: CLLocationCoordinate2D,
        bearingDegrees: Double,
        distanceMeters: Double
    ) -> CLLocationCoordinate2D {
        let earthRadius = 6_371_008.8
        let angularDistance = distanceMeters / earthRadius
        let bearing = bearingDegrees * .pi / 180
        let latitude = coordinate.latitude * .pi / 180
        let longitude = coordinate.longitude * .pi / 180

        let targetLatitude = asin(
            sin(latitude) * cos(angularDistance) +
                cos(latitude) * sin(angularDistance) * cos(bearing)
        )
        let targetLongitude = longitude + atan2(
            sin(bearing) * sin(angularDistance) * cos(latitude),
            cos(angularDistance) - sin(latitude) * sin(targetLatitude)
        )

        return CLLocationCoordinate2D(
            latitude: targetLatitude * 180 / .pi,
            longitude: normalizedLongitude(targetLongitude * 180 / .pi)
        )
    }

    private static func normalizedDegrees(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        let result = degrees.truncatingRemainder(dividingBy: 360)
        return result < 0 ? result + 360 : result
    }

    private static func normalizedLongitude(_ degrees: Double) -> Double {
        var result = (degrees + 180).truncatingRemainder(dividingBy: 360)
        if result < 0 { result += 360 }
        return result - 180
    }
}
