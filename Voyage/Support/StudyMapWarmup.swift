import Foundation

/// When the in-flight flight-tracker map card should be mounted, and when its
/// first paint still needs covering.
///
/// The window's satellite twin is a `UIViewRepresentable` and can report a
/// rendered frame through `MKMapViewDelegate`. The study map is SwiftUI's
/// `Map`, which exposes no such callback — there is no readiness signal to
/// gate on, so this is a *warm-up* policy rather than a readiness gate: mount
/// the map early and invisibly so it is never cold when the traveller first
/// taps Map, and derive "does the first paint still need covering?" from how
/// long the map has been mounted.
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

    /// How long a freshly mounted map is covered while it takes its first
    /// paint. A pre-warmed map has been mounted far longer than this by the
    /// time it is revealed, so it shows no cover at all.
    static let firstPaintCover: TimeInterval = 0.6

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

    /// Whether the calm cover still hides the map's first paint.
    ///
    /// Driven purely by how long the map has been mounted, which is what makes
    /// the warm path free: a map warmed seconds ago is already past the cover
    /// interval, so revealing it shows live tiles with no cover and no pop.
    static func showsFirstPaintCover(secondsMounted: TimeInterval?) -> Bool {
        guard let secondsMounted else { return true }
        return secondsMounted < firstPaintCover
    }
}
