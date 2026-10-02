import DeviceActivity
import Foundation
import os

private let log = Logger(subsystem: "com.patrickliu.voyage.deviceactivity", category: "DeviceActivity")

/// Airplane Mode's safety net. The app arms one interval per flight, ending
/// at the itinerary's scheduled end plus a margin; when it ends, this lowers
/// the shields unless a later flight owns them. So a flight whose app was
/// killed cannot leave the phone blocked.
///
/// This is Foqos's monitor (awaseem/foqos
/// `FoqosDeviceMonitor/DeviceActivityMonitorExtension.swift` at 4f6864c,
/// MIT): a `DeviceActivityMonitor` subclass named in Info.plist's
/// NSExtensionPrincipalClass that hands `intervalDidEnd` to the timer whose
/// prefix the activity carries (`TimerActivityUtil.stopTimerActivity`), and
/// that timer checks the shared session before calling
/// `AppBlockerUtil.deactivateRestrictions()` (`StrategyTimerActivity.stop`).
/// Voyage has one timer, so the dispatch collapses into
/// `AirplaneModeSchedule.decision`, which the app's unit tests cover.
///
/// Nothing happens in `intervalDidStart`: the interval opens at midnight, so
/// it has always already started, and the app raised the shields itself.
class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let appBlocker = AppBlockerUtil()

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        log.info("intervalDidEnd for activity: \(activity.rawValue, privacy: .public)")

        let flight = AirplaneModeFlightStore.load()
        let now = Date()
        switch AirplaneModeSchedule.decision(forActivity: activity.rawValue, flight: flight, now: now) {
        case .ignore:
            log.info("not this flight's interval; shields left alone")
        case .lowerShields:
            appBlocker.deactivateRestrictions()
            AirplaneModeFlightStore.clear()
            log.info("flight should be over; shields lowered")
        case .rearm(let end):
            guard let flight else { return }
            DeviceActivityCenterUtil.startAirplaneModeActivity(
                for: flight.id,
                interval: AirplaneModeSchedule.rearmInterval(until: end, now: now)
            )
        }
    }
}
