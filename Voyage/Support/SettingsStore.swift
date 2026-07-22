import Foundation
import Observation

/// App settings backed by UserDefaults.
@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard

    var ambienceEnabled: Bool {
        didSet { defaults.set(ambienceEnabled, forKey: "ambienceEnabled") }
    }

    /// Short direct-manipulation and flight-event sounds, independent of the
    /// continuous cabin bed and spoken check-ins.
    var soundEffectsEnabled: Bool {
        didSet { defaults.set(soundEffectsEnabled, forKey: "soundEffectsEnabled") }
    }

    var announcementsEnabled: Bool {
        didSet { defaults.set(announcementsEnabled, forKey: "announcementsEnabled") }
    }

    /// Chosen check-in voice identifier; nil means "automatic (best installed)".
    var paVoiceIdentifier: String? {
        didSet { defaults.set(paVoiceIdentifier, forKey: "paVoiceIdentifier") }
    }

    /// Manually chosen home airport code; nil means "use nearest from location".
    var originOverrideCode: String? {
        didSet { defaults.set(originOverrideCode, forKey: "originOverrideCode") }
    }

    /// Last origin resolved from CoreLocation, so the app works offline next launch.
    var resolvedOriginCode: String {
        didSet { defaults.set(resolvedOriginCode, forKey: "resolvedOriginCode") }
    }

    /// Post a local notification at depart if Focus / DND isn't enabled.
    var flightFocusRemindersEnabled: Bool {
        didSet { defaults.set(flightFocusRemindersEnabled, forKey: "flightFocusRemindersEnabled") }
    }

    /// The in-cruise beverage cart (hydration reminders).
    var cabinServiceEnabled: Bool {
        didSet { defaults.set(cabinServiceEnabled, forKey: "cabinServiceEnabled") }
    }

    /// Draw completed focus flights as translucent paths on the home globe.
    var flightTrailsEnabled: Bool {
        didSet { defaults.set(flightTrailsEnabled, forKey: "flightTrailsEnabled") }
    }

    /// Streams the route-aware real-world window from runway to runway.
    /// The renderer still falls back automatically when credentials, network,
    /// or device conditions make an online provider unavailable.
    var realWorldTwinEnabled: Bool {
        didSet { defaults.set(realWorldTwinEnabled, forKey: "realWorldTwinEnabled") }
    }

    /// Source compatibility for the retired near-airport-only setting. Keeping
    /// this as an alias also migrates any still-running view before it is
    /// replaced by the continuous real-world renderer.
    var realSceneryEnabled: Bool {
        get { realWorldTwinEnabled }
        set { realWorldTwinEnabled = newValue }
    }

    var homeAirport: Airport {
        Airport.byCode(originOverrideCode ?? resolvedOriginCode)
    }

    private init() {
        ambienceEnabled = defaults.object(forKey: "ambienceEnabled") as? Bool ?? true
        soundEffectsEnabled = defaults.object(forKey: "soundEffectsEnabled") as? Bool ?? true

        // Announcements were forced off in version 1 because the only voice
        // available was whatever compact system voice iOS had installed, and
        // it sounded synthetic. Voyage now ships its own studio cabin voice, so
        // the reason for the opt-out is gone and check-ins are on by default.
        if defaults.integer(forKey: "spokenCheckInsPreferenceVersion") < 2 {
            announcementsEnabled = true
            defaults.set(true, forKey: "announcementsEnabled")
            defaults.set(2, forKey: "spokenCheckInsPreferenceVersion")
        } else {
            announcementsEnabled = defaults.bool(forKey: "announcementsEnabled")
        }
        paVoiceIdentifier = defaults.string(forKey: "paVoiceIdentifier")
        originOverrideCode = defaults.string(forKey: "originOverrideCode")
        resolvedOriginCode = defaults.string(forKey: "resolvedOriginCode") ?? "BOS"
        flightFocusRemindersEnabled = defaults.object(forKey: "flightFocusRemindersEnabled") as? Bool ?? true
        cabinServiceEnabled = defaults.object(forKey: "cabinServiceEnabled") as? Bool ?? true
        flightTrailsEnabled = defaults.object(forKey: "flightTrailsEnabled") as? Bool ?? true
        realWorldTwinEnabled = defaults.object(forKey: "realWorldTwinEnabled") as? Bool
            ?? defaults.object(forKey: "realSceneryEnabled") as? Bool
            ?? true

        // Deterministic QA hook for authored airport worlds. Production never
        // supplies this argument; UI tests use it instead of location services.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-VoyageRealWorldTwinEnabled") {
            realWorldTwinEnabled = true
        }
        if let flag = arguments.firstIndex(of: "-VoyageHomeAirport"), arguments.indices.contains(flag + 1) {
            let code = arguments[flag + 1]
            if Airport.all.contains(where: { $0.code == code }) {
                originOverrideCode = code
                resolvedOriginCode = code
            }
        }
    }
}
