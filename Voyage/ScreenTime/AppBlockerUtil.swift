#if VOYAGE_SCREEN_TIME_YES
import FamilyControls
import Foundation
import ManagedSettings

/// The shields themselves: one named `ManagedSettingsStore` that the app
/// raises at takeoff and that either the app or the DeviceActivity monitor
/// clears. Compiled into both, so the two always address the same store.
///
/// This is how Foqos does it (awaseem/foqos `Foqos/Utils/AppBlockerUtil.swift`
/// at 4f6864c, MIT): a class owning a store named for the app, an
/// `activateRestrictions` that sets `shield.applications`,
/// `shield.applicationCategories` (`.specific(categories)`) and, for Safari,
/// `shield.webDomains`, each `nil` when empty, and a `deactivateRestrictions`
/// that nils every shield and then calls `clearAllSettings()`. The names are
/// Foqos's. Left out, because a flight has no use for them: allow mode,
/// strict mode (deny app removal), blocking app installation, the web
/// content filter, and breaks.
///
/// One deviation: Foqos shields `webDomainCategories` with the selected
/// categories only when its per-profile "Safari blocking" option is on.
/// Voyage has no such option, and a category a traveler picked should be
/// blocked in Safari too, so the selected categories always cover their web
/// domains as well.
final class AppBlockerUtil {
    let store = ManagedSettingsStore(
        named: ManagedSettingsStore.Name("voyageAirplaneMode")
    )

    func activateRestrictions(for selection: FamilyActivitySelection) {
        let applications = selection.applicationTokens
        let categories = selection.categoryTokens
        let webDomains = selection.webDomainTokens

        store.shield.applications = applications.isEmpty ? nil : applications
        store.shield.applicationCategories = categories.isEmpty ? nil : .specific(categories)
        store.shield.webDomains = webDomains.isEmpty ? nil : webDomains
        store.shield.webDomainCategories = categories.isEmpty ? nil : .specific(categories)
    }

    func deactivateRestrictions() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        store.shield.webDomainCategories = nil
        store.clearAllSettings()
    }

    /// Whether any shield is up in Voyage's store, read from the store itself
    /// rather than from a flag that could disagree with it after a crash.
    var restrictionsActive: Bool {
        store.shield.applications?.isEmpty == false
            || store.shield.applicationCategories != nil
            || store.shield.webDomains?.isEmpty == false
            || store.shield.webDomainCategories != nil
    }
}

/// The traveler's `FamilyActivitySelection`, kept in the App Group the way
/// Foqos keeps `selectedActivity` inside its profile snapshot
/// (`Foqos/Models/Shared.swift`). The selection holds Apple's opaque tokens,
/// not app names or bundle ids, and never leaves the device.
enum AirplaneModeSelectionStore {
    private static let key = "voyage.airplaneMode.selection"

    static func load(from defaults: UserDefaults = VoyageAppGroup.defaults) -> FamilyActivitySelection {
        guard let data = defaults.data(forKey: key),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return FamilyActivitySelection()
        }
        return selection
    }

    static func save(_ selection: FamilyActivitySelection, to defaults: UserDefaults = VoyageAppGroup.defaults) {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: key)
    }

    /// Foqos's `FamilyActivityUtil.countSelectedActivities`
    /// (`Foqos/Utils/FamilyActivityUtil.swift`): categories, apps and web
    /// domains, each counted once, as the picker shows them.
    static func count(_ selection: FamilyActivitySelection) -> Int {
        selection.categories.count + selection.applications.count + selection.webDomains.count
    }
}
#endif
