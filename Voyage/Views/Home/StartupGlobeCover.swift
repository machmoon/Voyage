import SwiftUI

/// Calm cover held over the Home / onboarding satellite globe at cold start,
/// then dissolved once MapKit has had time to paint its first imagery tiles.
///
/// Without it, launch shows the globe's blank black first frames — MapKit's
/// empty pane before the Earth streams in — as a flash between the navy launch
/// screen and the real UI. This holds the exact departure-curtain gradient
/// (`0D1531 → 050713`, which meets the navy `LaunchBackground` at the top and
/// darkens to near-black) over that void, so the hand-off from launch screen to
/// first rendered globe reads as one continuous surface, then crossfades away.
///
/// Timing is owned by the pure `StartupGlobeGate`; the hold is bounded, so an
/// offline launch that never streams a tile still reveals the deterministic
/// globe instead of holding forever. `StartupGlobeCoordinator` suppresses the
/// cover on any later globe in the session (returning from a flight, or Home
/// after onboarding) so it only ever plays on the process's first paint.
///
/// Drop it into the globe's `ZStack` directly above the map and below the
/// foreground chrome — the same layering the in-flight window uses for its own
/// loading cover.
struct StartupGlobeCover: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        LinearGradient(
            colors: [Color(hex: "0D1531"), Color(hex: "050713")],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
        .opacity(revealed ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            guard StartupGlobeGate.shouldPlayCover(
                hasShownGlobeThisSession: StartupGlobeCoordinator.shared.hasShownGlobe
            ) else {
                // A warm globe is already loaded — reveal instantly, no stutter.
                revealed = true
                return
            }
            StartupGlobeCoordinator.shared.markGlobeShown()
            try? await Task.sleep(for: .seconds(StartupGlobeGate.holdDuration))
            withAnimation(.easeOut(duration: StartupGlobeGate.fadeDuration(reduceMotion: reduceMotion))) {
                revealed = true
            }
        }
    }
}
