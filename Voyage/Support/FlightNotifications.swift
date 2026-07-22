import Foundation
import UserNotifications

/// Local notifications for boarding, focus reminders, and post-flight sharing —
/// the lock-screen presence when you're not inside the app.
@MainActor
enum FlightNotifications {
    private static let departFocusID = "voyage.departFocus"
    private static let landingID = "voyage.landing"
    private static let finalCallID = "voyage.finalCall"

    static func postDepartFocusReminder(for session: FlightSession) {
        let content = UNMutableNotificationContent()
        content.title = "Now departing \(session.itinerary.origin.code) → \(session.itinerary.destination.code)"
        content.body = "Swipe down → Control Center → Focus → Do Not Disturb for an uninterrupted flight. Voyage can't silence your phone for you."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: Self.departFocusID,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    static func postFinalCallNotification(for session: FlightSession) {
        let content = UNMutableNotificationContent()
        content.title = "Final boarding call — \(session.currentLeg.destination.code)"
        content.body = "Your connection departs in 3 minutes. Open Voyage to board."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: Self.finalCallID,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    static func postLandingNotification(for session: FlightSession) {
        let dest = session.itinerary.destination
        let content = UNMutableNotificationContent()
        content.title = "Landed in \(dest.city)"
        content.body = "+\(Int(session.completedMiles).formatted()) miles · \(session.itinerary.totalFocusDuration.shortDurationText) focus — open Voyage to stamp your passport and share your flight."
        content.sound = UNNotificationSound(named: UNNotificationSoundName("default"))

        let request = UNNotificationRequest(
            identifier: Self.landingID,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

}
