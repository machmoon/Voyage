import Foundation
import UserNotifications
import Observation

/// A flight booked for later. Boarding opens 10 minutes before departure
/// and closes 15 minutes after — miss the window and the flight is gone.
struct ScheduledFlight: Codable, Equatable {
    let destinationCode: String
    let departure: Date

    static let boardingLead: TimeInterval = 10 * 60
    static let boardingClose: TimeInterval = 15 * 60

    var boardingOpens: Date { departure.addingTimeInterval(-Self.boardingLead) }
    var boardingCloses: Date { departure.addingTimeInterval(Self.boardingClose) }

    var destination: Airport { Airport.byCode(destinationCode) }

    enum Status {
        case upcoming
        case boarding
        case expired
    }

    func status(at date: Date = .now) -> Status {
        if date < boardingOpens { return .upcoming }
        if date <= boardingCloses { return .boarding }
        return .expired
    }
}

/// Persists the single scheduled flight and manages its boarding notification.
@Observable
final class FlightScheduler {
    static let shared = FlightScheduler()

    private static let storageKey = "scheduledFlight"
    private static let notificationID = "voyage.boarding"

    private(set) var scheduled: ScheduledFlight?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let flight = try? JSONDecoder().decode(ScheduledFlight.self, from: data) {
            scheduled = flight
        }
    }

    func schedule(destination: Airport, departure: Date, origin: Airport) {
        let flight = ScheduledFlight(destinationCode: destination.code, departure: departure)
        scheduled = flight
        persist()

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            let number = RoutePlanner.flightNumber(from: origin, to: destination)
            content.title = "Now boarding — \(number) to \(destination.city)"
            content.body = "Your flight departs in 10 minutes. Boarding closes 15 minutes after departure."
            content.sound = .default

            let interval = flight.boardingOpens.timeIntervalSinceNow
            guard interval > 1 else { return }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let request = UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: trigger)
            center.add(request)
        }
    }

    func cancel() {
        scheduled = nil
        persist()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
    }

    /// Drops the stored flight if its boarding window has passed.
    func pruneExpired() {
        if let flight = scheduled, flight.status() == .expired {
            cancel()
        }
    }

    private func persist() {
        if let flight = scheduled, let data = try? JSONEncoder().encode(flight) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.storageKey)
        }
    }
}
