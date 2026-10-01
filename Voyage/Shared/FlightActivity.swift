import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Live Activity contract shared between the app and the widget extension:
/// a flight in progress on the lock screen / Dynamic Island.
struct FlightActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// "Climbing", "Cruise · deep work", etc.
        var phaseCaption: String
        /// SF Symbol for the current phase.
        var phaseSymbol: String
        /// When this leg lands — the widget renders a live countdown to it.
        var arrival: Date
        /// When this leg departed, for the progress bar.
        var departure: Date
        /// 1-based leg number and total legs (connections).
        var legNumber: Int
        var legCount: Int
        /// True once the session has ended (landed/diverted) — final frame.
        var concluded: Bool
        /// Set while the app is backgrounded mid-flight: the instant the
        /// flight diverts unless the traveller comes back. The lock screen is
        /// exactly where they are when this matters, so the card counts down
        /// to it instead of to a landing that will not happen. Optional so a
        /// state encoded by an older build still decodes.
        var graceDeadline: Date? = nil
    }

    var originCode: String
    var destinationCode: String
    var viaCode: String?
    var flightNumber: String
}
#endif
