import SwiftUI

/// The widget extension cannot see the app's `Theme` (it compiles only
/// `VoyageWidgets/` and `Voyage/Shared/`), so the few values it uses are
/// copied here by name. Keep them in step with `Voyage/Support/Theme.swift`:
/// a widget in a different blue from the app reads as someone else's.
enum WidgetTheme {
    /// `Theme.accent`. The Live Activity used to inline 4E8CFF, the design
    /// brief's value; the app ships 5E8FFF (see the note on `Theme.accent`).
    static let accent = rgb(0x5E, 0x8F, 0xFF)
    /// `Theme.destructive`, for the one warning the card can give: come back
    /// before the grace period runs out.
    static let destructive = rgb(0xE6, 0x5F, 0x5C)
    /// `Theme.nightSkyTop` / `Theme.nightSkyBottom`, the globe's sky.
    static let skyTop = rgb(0x08, 0x0C, 0x14)
    static let skyBottom = rgb(0x17, 0x22, 0x39)
    /// `Theme.surfaceDark`: the solid card behind the lock-screen activity,
    /// and the knock-out behind the plane on the route line.
    static let card = rgb(0x11, 0x15, 0x1C)
    /// `Theme.textPrimary` / `Theme.textSecondary`.
    static let textPrimary = rgb(0xF5, 0xF7, 0xFA)
    static let textSecondary = rgb(0xA8, 0xB0, 0xBE)
    /// `Theme.surfaceSubtle`: the unfilled part of a route line.
    static let track = rgb(0x24, 0x2B, 0x36)

    /// Horizon's night sky top (`widget-concepts.html` `--hz-n1`), the solid
    /// the system shows behind the Live Activity before the view draws.
    static let horizonNight = rgb(0x0A, 0x12, 0x30)

    static var sky: LinearGradient {
        LinearGradient(colors: [skyTop, skyBottom], startPoint: .top, endPoint: .bottom)
    }

    /// Airport codes: the boarding pass face, heavy and monospaced.
    static func code(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .monospaced)
    }

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255)
    }
}
