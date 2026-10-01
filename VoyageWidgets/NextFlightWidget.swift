import WidgetKit
import SwiftUI

/// Reads what the app last wrote to the App Group. A flight in the air gets
/// one entry per minute up to its arrival, so the minutes, the slats and the
/// plane all move on their own with no reload; a booked flight gets entries
/// at now, boarding open and boarding closed, the only times it changes.
/// Provider shape after apple/sample-backyard-birds
/// `Widgets/Backyard/BackyardSnapshotTimelineProvider.swift`
/// (`AppIntentTimelineProvider`, the style arriving as the configuration).
struct NextFlightProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NextFlightEntry {
        NextFlightEntry(date: .now, snapshot: .empty)
    }

    func snapshot(for configuration: NextFlightConfigurationIntent, in context: Context) async -> NextFlightEntry {
        NextFlightEntry(date: .now, snapshot: WidgetSnapshotStore.load(), style: configuration.style)
    }

    func timeline(for configuration: NextFlightConfigurationIntent, in context: Context) async -> Timeline<NextFlightEntry> {
        let snapshot = WidgetSnapshotStore.load()
        let dates = Self.entryDates(for: snapshot, now: .now)
        return Timeline(entries: dates.map { NextFlightEntry(date: $0, snapshot: snapshot, style: configuration.style) },
                        policy: .never)
    }

    /// Kept separate so the tests can check it.
    static func entryDates(for snapshot: WidgetSnapshot, now: Date) -> [Date] {
        var dates = [now]
        if let leg = snapshot.active, leg.arrival > now {
            // Whole minutes after now, until arrival, capped at six hours.
            let first = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 60).rounded(.down) * 60 + 60)
            var t = first
            while t < leg.arrival, dates.count < 360 {
                dates.append(t)
                t = t.addingTimeInterval(60)
            }
            dates.append(leg.arrival)
        }
        if let leg = snapshot.scheduled {
            dates += [leg.boardingOpens, leg.boardingCloses].filter { $0 > now }
        }
        return Array(Set(dates)).sorted()
    }
}

struct NextFlightWidget: Widget {
    private let kind = "NextFlight"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: NextFlightConfigurationIntent.self,
                               provider: NextFlightProvider()) { entry in
            NextFlightFamilyView(entry: entry)
        }
        .configurationDisplayName("Next flight")
        .description("Your next flight, or the one you are on. Edit the widget to choose its style.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

private struct NextFlightFamilyView: View {
    var entry: NextFlightEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        NextFlightWidgetView(entry: entry, family: family)
    }
}
