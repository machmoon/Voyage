import SwiftUI

/// Metal atmosphere and camera-relative cabin layers shared by every scenery
/// provider. Keeping them outside the map prevents cloud or wing geometry from
/// changing when the streamed provider falls back.
struct FlightAtmosphereLayer: View {
    let phase: LegPhase
    let phaseProgress: Double
    let altitudeFraction: Double
    let elapsed: TimeInterval
    let condition: SkyCondition
    let visibility: Double
    let isNight: Bool
    let goldenHour: Bool
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(.white)
                .colorEffect(ShaderLibrary.flightAtmosphere(
                    .float2(proxy.size),
                    .float(Float((reduceMotion ? 0.35 : elapsed).truncatingRemainder(dividingBy: 4096))),
                    .float(Float(condition.cloudAmount)),
                    .float(Float(min(1, max(0.08, visibility)))),
                    .float(Float(min(1, max(0, altitudeFraction)))),
                    .float(Float(phase.rawValue)),
                    .float(Float(min(1, max(0, phaseProgress)))),
                    .float(Float(precipitationKind)),
                    .float(isNight ? 1 : 0),
                    .float(goldenHour ? 1 : 0)
                ))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var precipitationKind: Double {
        switch condition {
        case .rain: return 1
        case .snow: return 2
        case .storm: return 3
        default: return 0
        }
    }
}

struct PassengerWingLayer: View {
    let side: WindowSide
    let bankDegrees: Double
    let elapsed: TimeInterval
    let isNight: Bool
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(.white)
                .colorEffect(ShaderLibrary.passengerWing(
                    .float2(proxy.size),
                    .float(side == .left ? 0 : 1),
                    .float(Float(reduceMotion ? 0 : bankDegrees)),
                    .float(isNight ? 1 : 0),
                    .float(Float((reduceMotion ? 0.35 : elapsed).truncatingRemainder(dividingBy: 4096)))
                ))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Subtle pane reflections and edge falloff. This is intentionally separate
/// from the map and wing so it always stays camera-relative.
struct PassengerGlassLayer: View {
    let condition: SkyCondition
    let isNight: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    .white.opacity(isNight ? 0.045 : 0.105),
                    .clear,
                    Color(hex: "8AB8E8").opacity(isNight ? 0.035 : 0.055),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [.clear, .black.opacity(isNight ? 0.16 : 0.08)],
                center: .center,
                startRadius: 80,
                endRadius: 360
            )
            if condition.isPrecipitating {
                LinearGradient(
                    colors: [.white.opacity(0.08), .clear, .white.opacity(0.025)],
                    startPoint: .top,
                    endPoint: .bottomTrailing
                )
                .blendMode(.screen)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
