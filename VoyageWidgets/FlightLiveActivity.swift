import WidgetKit
import SwiftUI
import ActivityKit

/// The flight on the lock screen and in the Dynamic Island. Every
/// presentation is built from one `FlightCard` (see `FlightActivityViews`);
/// region layout and content margins follow apple/sample-food-truck
/// `Widgets/TruckActivityWidget.swift`.
struct FlightLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FlightActivityAttributes.self) { context in
            FlightLockScreenView(card: Self.card(context))
                .activityBackgroundTint(WidgetTheme.horizonNight)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let card = Self.card(context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    FlightIslandPlace(card: card)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    FlightIslandCaption(card: card)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    FlightIslandBottom(card: card)
                }
            } compactLeading: {
                FlightIslandGlyph(card: card)
            } compactTrailing: {
                FlightCountdown(card: card, size: 14)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 56)
            } minimal: {
                FlightIslandMinimal(card: card)
            }
            .contentMargins([.leading, .top, .bottom], 6, for: .compactLeading)
            .contentMargins(.all, 4, for: .minimal)
            .keylineTint(card.ink)
        }
    }

    private static func card(_ context: ActivityViewContext<FlightActivityAttributes>) -> FlightCard {
        FlightCard(attributes: context.attributes, state: context.state, isStale: context.isStale)
    }
}
