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
    }

    var originCode: String
    var destinationCode: String
    var viaCode: String?
    var flightNumber: String
}
#endif
