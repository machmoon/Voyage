#if VOYAGE_SCREEN_TIME_YES
import DeviceActivity
import Foundation
import os

/// Starts and stops the safety net's DeviceActivity interval. Compiled into
/// the app (which arms it at takeoff) and the monitor extension (which
/// re-arms it after a midnight cap).
///
/// This is how Foqos does it (awaseem/foqos
/// `Foqos/Utils/DeviceActivityCenterUtil.swift` at 4f6864c, MIT):
/// `startStrategyTimerActivity` stops any activity of the same name, then
/// starts a non-repeating `DeviceActivitySchedule` from midnight to the end
/// time; `removeAllStrategyTimerActivities` stops every activity whose name
/// carries the timer's prefix. Voyage's end time is an absolute date, so the
/// interval comes from `AirplaneModeSchedule.interval(until:now:)`.
enum DeviceActivityCenterUtil {
    private static let log = Logger(subsystem: "com.patrickliu.voyage", category: "airplaneMode")

    static func startAirplaneModeActivity(for flightID: UUID, interval: AirplaneModeSchedule.Interval) {
        let center = DeviceActivityCenter()
        let name = DeviceActivityName(rawValue: AirplaneModeSchedule.activityName(for: flightID))
        let schedule = DeviceActivitySchedule(
            intervalStart: interval.start,
            intervalEnd: interval.end,
            repeats: false
        )
        do {
            center.stopMonitoring([name])
            try center.startMonitoring(name, during: schedule)
            log.info("safety net armed until \(interval.end.hour ?? -1, privacy: .public):\(interval.end.minute ?? -1, privacy: .public) capped=\(interval.cappedAtMidnight, privacy: .public)")
        } catch {
            log.error("safety net failed to start: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func removeAllAirplaneModeActivities() {
        let center = DeviceActivityCenter()
        let ours = center.activities.filter {
            $0.rawValue.hasPrefix(AirplaneModeSchedule.activityPrefix)
        }
        guard !ours.isEmpty else { return }
        center.stopMonitoring(ours)
    }
}
#endif
