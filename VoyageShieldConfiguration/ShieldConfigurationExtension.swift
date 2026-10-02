import ManagedSettings
import ManagedSettingsUI
import UIKit

/// The screen a blocked app or website shows during a flight: "You're in
/// flight", where it is going and how long until it lands, in Voyage's ink
/// and accent, read from the App Group record the app writes at takeoff.
///
/// This is how Foqos does it (awaseem/foqos
/// `FoqosShieldConfig/ShieldConfigurationExtension.swift` at 4f6864c, MIT): a
/// `ShieldConfigurationDataSource` that overrides the four
/// `configuration(shielding:)` variants and returns one
/// `ShieldConfiguration(backgroundBlurStyle:backgroundColor:icon:title:subtitle:primaryButtonLabel:primaryButtonBackgroundColor:)`.
/// Foqos rotates through playful messages and draws an emoji icon; Voyage
/// says one plain thing and uses an SF Symbol.
///
/// The primary button needs no ShieldActionExtension: without one, the
/// system's default action for the primary button closes the shielded app.
class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        inFlightShield()
    }

    override func configuration(shielding application: Application,
                                in category: ActivityCategory) -> ShieldConfiguration {
        inFlightShield()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        inFlightShield()
    }

    override func configuration(shielding webDomain: WebDomain,
                                in category: ActivityCategory) -> ShieldConfiguration {
        inFlightShield()
    }

    private func inFlightShield() -> ShieldConfiguration {
        let copy = AirplaneModeShieldCopy(flight: AirplaneModeFlightStore.load(), now: Date())
        return ShieldConfiguration(
            backgroundBlurStyle: .dark,
            // Theme.ink, #0B0E14 (Voyage/Support/Theme.swift).
            backgroundColor: UIColor(red: 11 / 255, green: 14 / 255, blue: 20 / 255, alpha: 1),
            icon: UIImage(systemName: "airplane")?
                .withTintColor(.white, renderingMode: .alwaysOriginal),
            title: ShieldConfiguration.Label(text: copy.title, color: .white),
            subtitle: ShieldConfiguration.Label(text: copy.subtitle,
                                                color: UIColor.white.withAlphaComponent(0.78)),
            primaryButtonLabel: ShieldConfiguration.Label(text: copy.button, color: .black),
            primaryButtonBackgroundColor: .white,
            secondaryButtonLabel: nil
        )
    }
}
