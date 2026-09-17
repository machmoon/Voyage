import Foundation

/// When the in-flight flight-tracker map card should be mounted, and when its
/// tiles still need covering.
///
/// The map opens by default, so it is mounted from the start of the flight and
/// the warm pass only matters to a traveller who switched to the window before
/// the map ever showed. The cover is a readiness gate: `FlightMapView` reports
/// MapKit's full render, and until then the traveller sees a calm cover rather
/// than MapKit's grey loading grid.
///
/// Deliberately pure: no MapKit, no SwiftUI, no clock of its own.
enum StudyMapWarmup {

    // MARK: Timings

    /// Let the window scene arm and takeoff settle before spending anything on
    /// a hidden map. Nothing competes with the first seconds of the flight.
    static func warmStartDelay(shortFlights: Bool) -> TimeInterval {
        shortFlights ? 0.4 : 1.5
    }

    /// How long the hidden warm mount lives. Long enough for MapKit to pull and
    /// cache the route's tiles; after that the on-disk tile cache carries the
    /// warmth and the live map is released.
    static func warmDuration(shortFlights: Bool) -> TimeInterval {
        shortFlights ? 8 : 20
    }

    /// Keep the map alive briefly after switching away, so flicking Map →
    /// Window → Map is instant instead of paying a remount each time.
    static func keepAliveAfterLeaving(shortFlights: Bool) -> TimeInterval {
        shortFlights ? 5 : 120
    }

    /// The longest the cover waits for a full render. A camera that keeps
    /// moving (Follow) can stop MapKit from ever reporting one, and the map is
    /// still worth seeing then.
    static let tileCoverCeiling: TimeInterval = 5

    // MARK: Policy

    /// Warming only makes sense if MapKit can actually fetch something. Offline
    /// (or a process forced offline for QA) there is nothing to warm, so we
    /// skip it entirely and degrade to the previous mount-on-switch behaviour
    /// rather than burning a renderer for nothing.
    static func warmingIsUseful(streamedSceneryAllowed: Bool, isOnline: Bool) -> Bool {
        streamedSceneryAllowed && isOnline
    }

    /// Whether the map card should exist in the hierarchy right now.
    ///
    /// - `isShowingMap`: the traveller is looking at it — always mounted.
    /// - `secondsSinceLeftMap`: within the keep-alive, stay mounted.
    /// - `secondsSinceInFlightBegan`: inside the warm window, mount hidden.
    ///
    /// Everything else is unmounted, so a long cruise never carries a live
    /// `MKMapView` the traveller isn't looking at.
    static func shouldMountMap(
        isShowingMap: Bool,
        hasOpenedMap: Bool,
        secondsSinceInFlightBegan: TimeInterval?,
        secondsSinceLeftMap: TimeInterval?,
        warmingIsUseful: Bool,
        shortFlights: Bool = false
    ) -> Bool {
        if isShowingMap { return true }

        if let sinceLeft = secondsSinceLeftMap,
           sinceLeft < keepAliveAfterLeaving(shortFlights: shortFlights) {
            return true
        }

        // The warm pass is a one-shot ahead of first use. Once the traveller
        // has opened the map, the tile cache is hot and the keep-alive above is
        // the only thing that should hold it.
        guard !hasOpenedMap, warmingIsUseful, let elapsed = secondsSinceInFlightBegan else {
            return false
        }
        let start = warmStartDelay(shortFlights: shortFlights)
        return elapsed >= start && elapsed < start + warmDuration(shortFlights: shortFlights)
    }

    /// Whether the calm cover still hides the map.
    ///
    /// * rendered — never covered;
    /// * failed, or offline — covered, since there is nothing but grid to show;
    /// * loading — covered until the ceiling.
    static func showsTileCover(
        tiles: WorldSceneryLoadState,
        isOnline: Bool,
        ceilingPassed: Bool
    ) -> Bool {
        switch tiles {
        case .ready: return false
        case .failed: return true
        case .loading: return !isOnline || !ceilingPassed
        }
    }
}
