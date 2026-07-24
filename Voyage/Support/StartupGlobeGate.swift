import Foundation

/// Pure, testable policy for the cold-start cover that hides the satellite
/// globe's blank first frames.
///
/// At launch the Home / onboarding globe — a SwiftUI `Map` in
/// `.imagery(elevation:.realistic)` — paints an empty black pane (space, no
/// Earth) for a beat before MapKit streams its first imagery tiles. That black
/// void is the "background placeholder" flash. The in-flight window solves the
/// same problem with a calm cover held on a real MapKit render signal, but
/// SwiftUI's `Map` exposes no "did render" callback, so the cold-start cover is
/// held on a short **bounded** timer instead.
///
/// Deliberately free of MapKit and SwiftUI so unit tests can walk its
/// boundaries. The hold is finite by construction: the cover can never outlive
/// `holdDuration`, so an offline launch that never streams a tile still hands
/// through to the deterministic globe rather than holding forever.
enum StartupGlobeGate {
    /// How long the calm cover stays fully opaque before it dissolves — long
    /// enough to swallow MapKit's blank first frames, short enough that the
    /// launch still feels like a launch rather than a stall.
    static let holdDuration: TimeInterval = 1.0

    /// The crossfade that dissolves the cover once the hold elapses. Instant
    /// under Reduce Motion (no animation), but the hold itself is unchanged so
    /// the black frames are still swallowed.
    static func fadeDuration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0 : 0.45
    }

    /// The cover plays only on the session's *first* globe. A warm globe —
    /// returning to Home after a flight, or Home crossfading in from onboarding
    /// where MapKit already cached the tiles — reveals instantly, so the calm
    /// surface never stutters over an already-loaded Earth.
    static func shouldPlayCover(hasShownGlobeThisSession: Bool) -> Bool {
        !hasShownGlobeThisSession
    }
}

/// Session-scoped memory of whether a globe has already loaded once, so the
/// cold-start cover fires only on the genuine first paint of the process and
/// never re-covers an already-warm globe.
@MainActor
final class StartupGlobeCoordinator {
    static let shared = StartupGlobeCoordinator()

    private(set) var hasShownGlobe = false

    init() {}

    func markGlobeShown() {
        hasShownGlobe = true
    }
}
