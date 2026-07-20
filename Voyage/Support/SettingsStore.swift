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

    var announcementsEnabled: Bool {
        didSet { defaults.set(announcementsEnabled, forKey: "announcementsEnabled") }
    }

    /// Chosen PA voice identifier; nil means "automatic (best installed)".
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

    var homeAirport: Airport {
        Airport.byCode(originOverrideCode ?? resolvedOriginCode)
    }

    private init() {
        ambienceEnabled = defaults.object(forKey: "ambienceEnabled") as? Bool ?? true
        announcementsEnabled = defaults.object(forKey: "announcementsEnabled") as? Bool ?? true
        paVoiceIdentifier = defaults.string(forKey: "paVoiceIdentifier")
        originOverrideCode = defaults.string(forKey: "originOverrideCode")
        resolvedOriginCode = defaults.string(forKey: "resolvedOriginCode") ?? "BOS"
    }
}
