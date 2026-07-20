import WidgetKit
import SwiftUI
import ActivityKit

@main
struct VoyageWidgets: WidgetBundle {
    var body: some Widget {
        FlightLiveActivity()
    }
}

/// The flight on the lock screen and in the Dynamic Island: route, live
/// countdown, phase, and a plane riding the progress bar.
struct FlightLiveActivity: Widget {
    // Widget target can't see the app's Theme — night-sky palette inlined.
    private static let accent = Color(red: 0x4E / 255, green: 0x8C / 255, blue: 0xFF / 255)
    private static let skyTop = Color(red: 0x0A / 255, green: 0x10 / 255, blue: 0x30 / 255)
    private static let skyBottom = Color(red: 0x1B / 255, green: 0x24 / 255, blue: 0x47 / 255)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FlightActivityAttributes.self) { context in
            lockScreenCard(context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.originCode)
                        .font(.system(size: 22, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.destinationCode)
                        .font(.system(size: 22, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        countdown(context, font: .system(size: 24, weight: .bold, design: .monospaced))
                        Text(context.state.phaseCaption)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    progressBar(context)
                        .padding(.horizontal, 6)
                        .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: context.state.phaseSymbol)
                    .foregroundStyle(Self.accent)
            } compactTrailing: {
                countdown(context, font: .system(size: 13, weight: .semibold, design: .monospaced))
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: "airplane")
                    .foregroundStyle(Self.accent)
            }
            .keylineTint(Self.accent)
        }
    }

    // MARK: Lock screen

    private func lockScreenCard(_ context: ActivityViewContext<FlightActivityAttributes>) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(context.attributes.originCode)
                    .font(.system(size: 26, weight: .heavy, design: .monospaced))
                Spacer()
                VStack(spacing: 1) {
                    Image(systemName: context.state.phaseSymbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Self.accent)
                    if let via = context.attributes.viaCode {
                        Text("via \(via)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                Spacer()
                Text(context.attributes.destinationCode)
                    .font(.system(size: 26, weight: .heavy, design: .monospaced))
            }
            .foregroundStyle(.white)

            progressBar(context)

            HStack {
                Text(context.state.phaseCaption)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.65))
                Spacer()
                if context.state.concluded {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Self.accent)
                } else {
                    countdown(context, font: .system(size: 16, weight: .bold, design: .monospaced))
                }
            }
        }
        .padding(16)
        .background(
            LinearGradient(colors: [Self.skyTop, Self.skyBottom],
                           startPoint: .top, endPoint: .bottom)
        )
        .activityBackgroundTint(Self.skyTop)
        .activitySystemActionForegroundColor(.white)
    }

    // MARK: Pieces

    @ViewBuilder
    private func countdown(_ context: ActivityViewContext<FlightActivityAttributes>,
                           font: Font) -> some View {
        if context.state.concluded {
            Text("00:00")
                .font(font)
                .foregroundStyle(.white.opacity(0.6))
        } else {
            Text(timerInterval: Date.now...max(Date.now, context.state.arrival),
                 countsDown: true)
                .font(font)
                .foregroundStyle(.white)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }

    private func progressBar(_ context: ActivityViewContext<FlightActivityAttributes>) -> some View {
        let range = context.state.departure...max(context.state.departure + 1, context.state.arrival)
        return VStack(spacing: 3) {
            ProgressView(timerInterval: range, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(Self.accent)

            if context.state.legCount > 1 {
                Text("Leg \(context.state.legNumber) of \(context.state.legCount) · \(context.attributes.flightNumber)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
