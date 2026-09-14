import Foundation
import SwiftData
import os

/// The one fact about an in-progress flight that must outlive the process.
///
/// `FlightSession` only writes a `LogbookEntry` from `finishSession`, which
/// needs the app to be running. If iOS ends a backgrounded Voyage during a
/// flight, nothing ever writes the entry: the next launch opens on the globe
/// as if the flight never happened. This record is written when the pass is
/// torn, updated per leg, and cleared the moment the logbook entry lands, so
/// a launch that finds one knows a flight was cut short and can log it.
///
/// Stored the same way `FlightScheduler` keeps its scheduled flight: a small
/// `Codable` value in `UserDefaults` (`Voyage/Support/FlightScheduler.swift`).
struct InFlightRecord: Codable, Equatable {
    var originCode: String
    var destinationCode: String
    var connectionCode: String?
    var flightNumber: String
    var seat: String
    var intentions: [String]
    var departedAt: Date
    /// Focus and miles credited by legs that had already landed.
    var completedFocusSeconds: TimeInterval
    var completedMiles: Double
    /// The leg in progress when the record was last written.
    var legStartedAt: Date
    var legDuration: TimeInterval
    var scheduledSeconds: TimeInterval
}

enum InterruptedFlightRecovery {
    static let key = "voyage.inFlightRecord"
    private static let logger = Logger(subsystem: "com.patrickliu.voyage", category: "recovery")

    static func save(_ record: InFlightRecord, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: key)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    static func pending(defaults: UserDefaults = .standard) -> InFlightRecord? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(InFlightRecord.self, from: data)
    }

    /// Writes the logbook entry for a flight the process did not survive and
    /// clears the record. Returns the entry so the caller can tell the traveler.
    ///
    /// Time in the interrupted leg counts up to the moment of the last write
    /// plus the leg's length, never beyond: the app cannot know when it died,
    /// so it credits the leg as far as it could possibly have run.
    @discardableResult
    static func recover(into context: ModelContext,
                        now: Date = .now,
                        defaults: UserDefaults = .standard) -> LogbookEntry? {
        guard let record = pending(defaults: defaults) else { return nil }
        clear(defaults: defaults)

        let legElapsed = min(max(0, now.timeIntervalSince(record.legStartedAt)), record.legDuration)
        // Same floor as `FlightSession.finishSession`: a process that died in
        // the first minute of a flight has nothing worth a logbook row or an
        // alert on the next launch.
        guard record.completedFocusSeconds + legElapsed >= FlightSession.minimumLoggedFocus else { return nil }
        let entry = LogbookEntry(
            date: min(now, record.legStartedAt.addingTimeInterval(record.legDuration)),
            originCode: record.originCode,
            destinationCode: record.destinationCode,
            connectionCode: record.connectionCode,
            flightNumber: record.flightNumber,
            seat: record.seat,
            miles: record.completedMiles,
            focusSeconds: min(record.completedFocusSeconds + legElapsed, record.scheduledSeconds),
            completed: false,
            intentions: record.intentions,
            intentionsCompleted: Array(repeating: false, count: record.intentions.count),
            scheduledSeconds: record.scheduledSeconds,
            departedAt: record.departedAt,
            outcome: .interrupted
        )
        context.insert(entry)
        do {
            try context.save()
        } catch {
            logger.error("Could not save the recovered flight: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        return entry
    }
}
