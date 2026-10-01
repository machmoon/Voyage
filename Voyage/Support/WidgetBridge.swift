import Foundation
import WidgetKit

/// App side of the Home Screen widget: flattens what the app knows into a
/// `WidgetSnapshot` and reloads timelines only when it changed.
enum WidgetBridge {
    private static var isTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// From Home: the booked flight and the quick route. Keeps the in-flight
    /// leg, which only the flight itself writes.
    static func publish(origin: Airport, quickDestination: Airport?, scheduled: ScheduledFlight?) {
        guard !isTestHost else { return }
        var snapshot = WidgetSnapshotStore.load()
        snapshot.scheduled = scheduled.map { flight in
            let destination = flight.destination
            return WidgetSnapshot.ScheduledLeg(
                originCode: origin.code,
                destinationCode: destination.code,
                destinationCity: destination.city,
                flightNumber: flight.flightNumber
                    ?? RoutePlanner.flightNumber(from: origin, to: destination),
                departure: flight.departure,
                boardingOpens: flight.boardingOpens,
                boardingCloses: flight.boardingCloses,
                duration: RoutePlanner.itinerary(from: origin, to: destination).totalFocusDuration,
                courseDegrees: GreatCircle.bearing(from: origin.coordinate, to: destination.coordinate)
            )
        }
        snapshot.quickRoute = quickDestination.map { destination in
            WidgetSnapshot.QuickRoute(
                originCode: origin.code,
                destinationCode: destination.code,
                duration: RoutePlanner.itinerary(from: origin, to: destination).totalFocusDuration,
                destinationCity: destination.city,
                courseDegrees: GreatCircle.bearing(from: origin.coordinate, to: destination.coordinate)
            )
        }
        if WidgetSnapshotStore.save(snapshot) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// From the flight: the leg in the air, or nil once it is over. Called on
    /// the same transitions as the Live Activity.
    @MainActor
    static func flight(_ session: FlightSession?) {
        guard !isTestHost else { return }
        let leg = session.flatMap { session -> WidgetSnapshot.ActiveLeg? in
            guard session.stage == .inFlight else { return nil }
            let current = session.currentLeg
            let now = session.now
            return WidgetSnapshot.ActiveLeg(
                originCode: current.origin.code,
                destinationCode: current.destination.code,
                destinationCity: current.destination.city,
                departure: now.addingTimeInterval(-session.legElapsed),
                arrival: now.addingTimeInterval(session.legRemaining),
                seat: session.seat == "—" ? nil : session.seat,
                bags: session.intentions.isEmpty ? nil : session.intentions.count,
                courseDegrees: GreatCircle.bearing(from: current.origin.coordinate,
                                                   to: current.destination.coordinate)
            )
        }
        if WidgetSnapshotStore.setActive(leg) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
