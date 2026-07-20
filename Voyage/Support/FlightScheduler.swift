import Foundation
import UserNotifications
import Observation

/// A flight booked for later. Boarding opens 10 minutes before departure
/// and closes 15 minutes after — miss the window and the flight is gone.
struct ScheduledFlight: Codable, Equatable {
    let destinationCode: String
    let departure: Date
    /// Real flight number of the booked departure ("AC 741"). Optional so
    /// flights persisted by older builds still decode.
    var flightNumber: String?

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
final class FlightScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = FlightScheduler()

    private static let storageKey = "scheduledFlight"
    private static let notificationID = "voyage.boarding"

    private(set) var scheduled: ScheduledFlight?
    /// True when the user has notifications denied — the boarding call
    /// can't ring, and the UI should say so instead of silently failing.
    private(set) var notificationsDenied = false

    private override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let flight = try? JSONDecoder().decode(ScheduledFlight.self, from: data) {
            scheduled = flight
        }
        // Without a delegate, iOS silently swallows the boarding call whenever
        // the app happens to be foregrounded when it fires.
        UNUserNotificationCenter.current().delegate = self
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func schedule(destination: Airport, departure: Date, origin: Airport,
                  flightNumber: String? = nil) {
        let flight = ScheduledFlight(destinationCode: destination.code,
                                     departure: departure,
                                     flightNumber: flightNumber)
        scheduled = flight
        persist()

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { self.notificationsDenied = !granted }
            guard granted else { return }
            let content = UNMutableNotificationContent()
            let number = flightNumber ?? RoutePlanner.flightNumber(from: origin, to: destination)
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

    /// Drops the stored flight if its boarding window has passed, and
    /// refreshes whether the boarding call can actually ring.
    func pruneExpired() {
        if let flight = scheduled, flight.status() == .expired {
            cancel()
        }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationsDenied = settings.authorizationStatus == .denied
            }
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
