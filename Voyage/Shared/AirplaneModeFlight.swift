import Foundation

/// The flight Airplane Mode is blocking apps for, as the two Screen Time
/// extensions see it. The app writes it to the App Group at takeoff, rewrites
/// it at each connection, and removes it when the flight ends. The
/// DeviceActivity monitor reads it to decide whether its safety-net interval
/// may lower the shields; the shield configuration reads it to say where the
/// flight is going and how long until it lands.
///
/// Foundation only: it is compiled into the app, both Screen Time
/// extensions and the widget (which takes all of `Voyage/Shared`), and none
/// of them should link Screen Time frameworks because of it.
///
/// This is how Foqos shares an active session with its extensions: a small
/// Codable snapshot in the App Group's defaults suite, keyed by profile id
/// (awaseem/foqos `Foqos/Models/Shared.swift`, `SessionSnapshot` and
/// `getActiveSharedSession`, at 4f6864c). Voyage has one flight at a time, so
/// it keeps one record instead of a dictionary.
struct AirplaneModeFlight: Codable, Equatable {
    /// Names this flight's DeviceActivity, so a safety net left over from an
    /// earlier flight can tell it does not own the shields any more.
    var id: UUID
    /// Where the current leg lands. Nil for an Open skies flight, which has
    /// no destination until it is cleared to land.
    var destinationCode: String?
    var destinationCity: String?
    /// When the current leg lands.
    var landsAt: Date
    /// The scheduled end of the whole itinerary plus `AirplaneModeSchedule.margin`.
    /// The safety net lowers the shields at this moment if the app has not.
    var safetyNetEndsAt: Date
}

enum AirplaneModeFlightStore {
    private static let key = "voyage.airplaneMode.flight"

    static func load(from defaults: UserDefaults = VoyageAppGroup.defaults) -> AirplaneModeFlight? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AirplaneModeFlight.self, from: data)
    }

    static func save(_ flight: AirplaneModeFlight, to defaults: UserDefaults = VoyageAppGroup.defaults) {
        guard let data = try? JSONEncoder().encode(flight) else { return }
        defaults.set(data, forKey: key)
    }

    static func clear(from defaults: UserDefaults = VoyageAppGroup.defaults) {
        defaults.removeObject(forKey: key)
    }
}

/// When the safety net ends, and what it does when it does. Pure date math so
/// the app's tests can check it; the extension and `ScreenTimeAppBlocker` turn
/// it into `DeviceActivitySchedule`s.
enum AirplaneModeSchedule {
    /// Added to the itinerary's scheduled end. Long enough that a flight that
    /// is still legitimately running is never cut short by its own safety
    /// net, and at least DeviceActivity's 15-minute minimum interval, so the
    /// schedule is accepted even for a flight that took off just after midnight.
    static let margin: TimeInterval = 15 * 60

    /// Prefix of every DeviceActivityName Voyage starts. Foqos names its
    /// timers `"<TimerType.id>:<profileId>"` and parses them back the same way
    /// (`Foqos/Models/Timers/TimerActivity.swift`, `profileId(from:)`).
    static let activityPrefix = "AirplaneModeActivity"

    static func activityName(for flightID: UUID) -> String {
        "\(activityPrefix):\(flightID.uuidString)"
    }

    /// The flight id inside one of our activity names; nil for any other name.
    static func flightID(fromActivity name: String) -> UUID? {
        let parts = name.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, parts[0] == activityPrefix else { return nil }
        return UUID(uuidString: String(parts[1]))
    }

    /// The latest the itinerary can still be running if nothing goes wrong:
    /// every leg at its flown length, plus every layover at its full length
    /// and the final-call window after it (boarding is allowed until then; a
    /// missed connection ends the flight there).
    static func scheduledEnd(departure: Date,
                             legDurations: [TimeInterval],
                             layover: TimeInterval,
                             finalCallWindow: TimeInterval) -> Date {
        let flying = legDurations.reduce(0, +)
        let connections = TimeInterval(max(0, legDurations.count - 1))
        return departure.addingTimeInterval(flying + connections * (layover + finalCallWindow))
    }

    static func safetyNetEnd(departure: Date,
                             legDurations: [TimeInterval],
                             layover: TimeInterval,
                             finalCallWindow: TimeInterval) -> Date {
        scheduledEnd(departure: departure, legDurations: legDurations,
                     layover: layover, finalCallWindow: finalCallWindow)
            .addingTimeInterval(margin)
    }

    /// A DeviceActivity interval, as the time-of-day components
    /// `DeviceActivitySchedule` takes.
    struct Interval: Equatable {
        var start: DateComponents
        var end: DateComponents
        /// True when `end` was capped at the end of today because the safety
        /// net runs past midnight. The extension re-arms for the rest when the
        /// capped interval ends.
        var cappedAtMidnight: Bool
    }

    /// Foqos's `getTimeIntervalStartAndEnd` (`Foqos/Utils/DeviceActivityCenterUtil.swift`
    /// at 4f6864c), adapted from a duration to an absolute end: the interval
    /// opens at midnight, so it has already started and is never shorter than
    /// the 15-minute minimum, and it ends at the end time's hour, minute and
    /// second, capped at 23:59:59 today. Two deviations: the cap is computed
    /// with `Calendar.date(bySettingHour:)` rather than `startOfDay + 86399 s`,
    /// which is an hour off on a daylight-saving day; and the cap is reported,
    /// because Foqos's timer simply ends early at midnight while Voyage's
    /// extension re-arms for the remainder (`decision(…)`).
    static func interval(until end: Date, now: Date, calendar: Calendar = .current) -> Interval {
        let start = DateComponents(hour: 0, minute: 0, second: 0)
        let lastSecond = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now)
            ?? calendar.startOfDay(for: now).addingTimeInterval(24 * 60 * 60 - 1)
        let target = max(end, now.addingTimeInterval(1))
        let capped = target > lastSecond
        let endDate = min(target, lastSecond)
        let endComponents = calendar.dateComponents([.hour, .minute, .second], from: endDate)
        return Interval(start: start, end: endComponents, cappedAtMidnight: capped)
    }

    /// What the monitor does when one of its intervals ends.
    enum Decision: Equatable {
        /// Not ours, or a later flight owns the shields: leave them alone.
        case ignore
        /// The flight should be over: clear the shields and the record.
        case lowerShields
        /// The interval was capped at midnight and the flight is still due to
        /// be running: start the rest of it.
        case rearm(until: Date)
    }

    /// Foqos's `StrategyTimerActivity.stop(for:)` checks that the active
    /// session still belongs to the profile before it ends restrictions; this
    /// is that check, plus two things Voyage needs. With no record at all the
    /// shields come down (Foqos returns instead): nothing is in flight, so
    /// lowering them is never wrong and a stray shield is the failure this
    /// safety net exists for. And an interval that ends before the flight's
    /// deadline, which only the midnight cap produces, re-arms instead.
    static func decision(forActivity name: String,
                         flight: AirplaneModeFlight?,
                         now: Date,
                         tolerance: TimeInterval = 60) -> Decision {
        guard let flightID = flightID(fromActivity: name) else { return .ignore }
        guard let flight else { return .lowerShields }
        guard flight.id == flightID else { return .ignore }
        if now < flight.safetyNetEndsAt.addingTimeInterval(-tolerance) {
            return .rearm(until: flight.safetyNetEndsAt)
        }
        return .lowerShields
    }

    /// The interval for a re-arm. The capped interval ends at 23:59:59, so
    /// `now` may still be the old day; a minute later is the new one, which is
    /// the day whose midnight-anchored interval should carry the remainder.
    static func rearmInterval(until end: Date, now: Date, calendar: Calendar = .current) -> Interval {
        interval(until: end, now: now.addingTimeInterval(60), calendar: calendar)
    }
}

/// The words on the shield, kept apart from the extension so they can be
/// tested. With no record (the flight ended between the shield being asked
/// for and drawn) it still says something true.
struct AirplaneModeShieldCopy: Equatable {
    var title: String
    var subtitle: String
    var button: String

    init(flight: AirplaneModeFlight?, now: Date) {
        title = "You're in flight"
        button = "Back to my flight"
        guard let flight else {
            subtitle = "Airplane Mode is on until you land."
            return
        }
        let minutes = Int((flight.landsAt.timeIntervalSince(now) / 60).rounded(.up))
        let landing: String
        switch minutes {
        case ..<1: landing = "Landing now."
        case 1: landing = "Landing in 1 minute."
        default: landing = "Landing in \(minutes) minutes."
        }
        if let city = flight.destinationCity, let code = flight.destinationCode {
            subtitle = "On your way to \(city) (\(code)). \(landing)"
        } else {
            subtitle = "Open skies. \(landing)"
        }
    }
}
