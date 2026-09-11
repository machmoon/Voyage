import Foundation
import Observation

/// The two worlds you can look out at through the cabin window.
enum WindowWorldMode: String, CaseIterable, Identifiable {
    /// Streamed Apple satellite imagery flown along the real route.
    case real
    /// The drawn weather scene — sun, cloud, rain, storm, snow, fog — which
    /// needs no network and never shows a half-loaded tile.
    case illustrated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .real: return "Real world"
        case .illustrated: return "Illustrated"
        }
    }

    var caption: String {
        switch self {
        case .real: return "Satellite imagery along your actual route."
        case .illustrated: return "Drawn skies that match the forecast. Works offline."
        }
    }
}

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
    ///
    /// Writing this is what makes the origin location-derived, so the setter is
    /// also what flips `originIsFromLocation`. Nothing else assigns it.
    var resolvedOriginCode: String {
        didSet {
            defaults.set(resolvedOriginCode, forKey: "resolvedOriginCode")
            defaults.set(true, forKey: "hasResolvedOriginFromLocation")
            hasResolvedOriginFromLocation = true
        }
    }

    /// Whether `resolvedOriginCode` was ever actually produced by CoreLocation,
    /// as opposed to being the working default the app starts with.
    ///
    /// This is provenance, not a second source of truth: `homeAirport` is still
    /// the only place the origin comes from. It exists because the app used to
    /// present its unresolved default as though it had been sensed, which is
    /// the same class of problem as a screen claiming Airplane Mode is on.
    private(set) var hasResolvedOriginFromLocation: Bool

    /// True when the traveler picked the origin in Settings instead of it being
    /// sensed. Not a location fix, so it must not be drawn as one.
    var originIsChosen: Bool { originOverrideCode != nil }

    /// True when the origin on screen is neither sensed nor chosen: it is the
    /// working default, and the app has no idea what is nearest.
    var originIsUnknown: Bool { originOverrideCode == nil && !hasResolvedOriginFromLocation }

    /// Only a real location fix earns the location glyph.
    var originIsFromLocation: Bool { originOverrideCode == nil && hasResolvedOriginFromLocation }

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

    /// Which world you look out at. `real` streams Apple satellite imagery
    /// along the route; `illustrated` draws the hand-made weather scene, which
    /// works offline and shows the sky you'd actually expect.
    var windowWorldMode: WindowWorldMode {
        didSet {
            defaults.set(windowWorldMode.rawValue, forKey: "windowWorldMode")
            realWorldTwinEnabled = windowWorldMode == .real
        }
    }

    /// Whether the in-flight window should mount Apple's streamed 3D scenery.
    var streamsRealWorldScenery: Bool { windowWorldMode == .real }

    /// Whether the first-run preflight onboarding has been seen. Gated by
    /// `RootView` so it shows exactly once.
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
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
        // BOS stays as the value the app runs on before a fix arrives, because
        // the globe, the destination rail and every route duration need an
        // origin to exist at all. What changes is that the app now knows this
        // is a default rather than a location, and Home says so instead of
        // drawing a location arrow next to it.
        let storedOrigin = defaults.string(forKey: "resolvedOriginCode")
        resolvedOriginCode = storedOrigin ?? "BOS"
        // Property observers do not fire during `init`, so the assignment above
        // does not mark this default as resolved. A store written before this
        // flag existed still has `resolvedOriginCode`, and the only thing that
        // ever wrote that key was a CoreLocation fix, so treat its presence as
        // the fix it was and do not re-prompt an existing traveler.
        let originWasSensed =
            defaults.bool(forKey: "hasResolvedOriginFromLocation") || storedOrigin != nil
        hasResolvedOriginFromLocation = originWasSensed
        defaults.set(originWasSensed, forKey: "hasResolvedOriginFromLocation")
        flightFocusRemindersEnabled = defaults.object(forKey: "flightFocusRemindersEnabled") as? Bool ?? true
        cabinServiceEnabled = defaults.object(forKey: "cabinServiceEnabled") as? Bool ?? true
        flightTrailsEnabled = defaults.object(forKey: "flightTrailsEnabled") as? Bool ?? true
        hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        realWorldTwinEnabled = defaults.object(forKey: "realWorldTwinEnabled") as? Bool
            ?? defaults.object(forKey: "realSceneryEnabled") as? Bool
            ?? false
        windowWorldMode = defaults.string(forKey: "windowWorldMode")
            .flatMap(WindowWorldMode.init(rawValue:)) ?? .illustrated
        if defaults.object(forKey: "realWorldTwinEnabled") == nil,
           defaults.object(forKey: "realSceneryEnabled") == nil {
            realWorldTwinEnabled = windowWorldMode == .real
        }

        // Deterministic QA hook for authored airport worlds. Production never
        // supplies this argument; UI tests use it instead of location services.
        let arguments = ProcessInfo.processInfo.arguments

        // UI tests drive straight into the home/flight flow and never expect the
        // first-run onboarding. An explicit allow-list of test flags bypasses it
        // — deliberately not a blanket `-Voyage` prefix match, so a future flag
        // (or a stray arg on a real launch) can't silently skip onboarding.
        let onboardingSkipFlags: Set<String> = [
            "-VoyageSkipOnboarding",
            "-VoyageShortFlights",
            "-VoyageRealWorldTwinEnabled",
            "-VoyageHomeAirport"
        ]
        if arguments.contains(where: onboardingSkipFlags.contains) {
            hasCompletedOnboarding = true
        }

        // Evaluate reset last so it always wins over the skip flags above.
        if arguments.contains("-VoyageResetOnboarding") {
            hasCompletedOnboarding = false
            defaults.set(false, forKey: "hasCompletedOnboarding")
        }

        if arguments.contains("-VoyageRealWorldTwinEnabled") {
            // Set the mode, not just the mirror. Every consumer of this gates on
            // `streamsRealWorldScenery`, which is `windowWorldMode == .real`
            // (see above) and never reads `realWorldTwinEnabled`, so setting the
            // flag alone left the hook dead: the flag flipped, the mode stayed
            // `.illustrated`, and a test that asked for the real-world twin got
            // the drawn scene. `windowWorldMode` is the single source of truth
            // and its `didSet` mirrors back to the flag; both are assigned here
            // because property observers do not fire during `init`, which is the
            // same reason the load-time reconcile above assigns them in pairs.
            windowWorldMode = .real
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
