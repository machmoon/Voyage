import Foundation
import Observation

/// Shared "the satellite window has a frame" signal for one departure.
///
/// The departure curtain exists so the real-world window has time to load; it
/// must never hand off to an unloaded pane. Two places can satisfy the signal,
/// and either is enough:
///
/// * `MapWarmer` — the invisible warm map parked at the origin while the
///   traveller picks a seat and tears the pass. It renders the same satellite
///   tiles the window will use.
/// * `RealWorldTwinView` — the in-flight window itself, once MapKit reports a
///   rendered frame.
///
/// Reset when a new flight is booked so a stale success can't wave through a
/// cold departure.
@MainActor
@Observable
final class DepartureReadiness {
    static let shared = DepartureReadiness()

    /// True once MapKit has rendered a satellite frame for this departure.
    private(set) var mapHasRenderedFrame = false

    init() {}

    func markMapRendered() {
        mapHasRenderedFrame = true
    }

    /// Called when a new flight is booked — the next departure starts cold.
    func resetForNewBooking() {
        mapHasRenderedFrame = false
    }
}

/// Pure, testable policy for how long the "cleared for departure" curtain
/// holds. Deliberately free of MapKit, network, and SwiftUI so unit tests can
/// walk its boundaries without touching either.
enum DepartureGate {
    /// The curtain never flashes past this, so the beat always reads as
    /// intentional rather than as a stutter.
    static func minimumHold(shortFlights: Bool) -> TimeInterval {
        shortFlights ? 1.6 : 2.8
    }

    /// The hard ceiling. The app *always* departs — a map that never reports
    /// in costs the traveller this much and no more.
    static func maximumHold(shortFlights: Bool) -> TimeInterval {
        shortFlights ? 3.0 : 7.0
    }

    /// Whether waiting on the map signal is meaningful at all.
    ///
    /// Illustrated mode mounts no map, a process forced offline will never
    /// stream a tile, and an offline device has nothing to wait for. In every
    /// one of those cases the curtain falls straight through to the fixed
    /// minimum — we never gate on a signal that cannot arrive.
    static func waitsForMap(
        worldMode: WindowWorldMode,
        streamedSceneryAllowed: Bool,
        isOnline: Bool
    ) -> Bool {
        worldMode == .real && streamedSceneryAllowed && isOnline
    }

    /// The gating rule, in one place:
    ///
    /// * below `minimum` — hold, always;
    /// * at or past `maximum` — depart, always;
    /// * in between — depart as soon as the map has a frame, or immediately if
    ///   this departure isn't waiting on one.
    static func shouldDepart(
        mapHasRenderedFrame: Bool,
        elapsed: TimeInterval,
        minimum: TimeInterval,
        maximum: TimeInterval,
        waitsForMap: Bool
    ) -> Bool {
        let ceiling = max(minimum, maximum)
        if elapsed >= ceiling { return true }
        if elapsed < minimum { return false }
        return !waitsForMap || mapHasRenderedFrame
    }
}
