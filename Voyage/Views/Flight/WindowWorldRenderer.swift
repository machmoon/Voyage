import Metal
import SwiftUI

enum WindowWorldRendererSelection: Equatable {
    case authoredSFO
    case procedural
}

/// Deterministic renderer selection. Keeping the decision outside either
/// renderer makes unsupported airports and accessibility behavior explicit.
enum WindowWorldRendererPolicy {
    static func selection(for frame: AirportWorldFrame, phase: LegPhase,
                          reduceMotion: Bool, metalAvailable: Bool) -> WindowWorldRendererSelection {
        guard metalAvailable, !reduceMotion, frame.airportCode == "SFO",
              phase == .takeoffRoll || phase == .climb else {
            return .procedural
        }
        return .authoredSFO
    }
}

/// Internal window-world boundary. Both the authored and procedural paths
/// consume the same frozen `AirportWorldFrame`; neither reads wall-clock time.
struct WindowWorldRenderer<Procedural: View>: View {
    let frame: AirportWorldFrame
    let phase: LegPhase
    let isNight: Bool
    let condition: SkyCondition
    let reduceMotion: Bool
    @ViewBuilder let procedural: () -> Procedural

    var body: some View {
        switch WindowWorldRendererPolicy.selection(
            for: frame,
            phase: phase,
            reduceMotion: reduceMotion,
            metalAvailable: MTLCreateSystemDefaultDevice() != nil
        ) {
        case .authoredSFO:
            SFOAirportWorldView(frame: frame, isNight: isNight, condition: condition)
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(frame.visibility < 0.5 ? 0.18 : 0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                }
                .accessibilityLabel("Passenger window view departing San Francisco")
        case .procedural:
            procedural()
        }
    }
}
