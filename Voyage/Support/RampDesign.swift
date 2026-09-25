import SwiftUI
import UIKit

// MARK: - DESIGN-NOTES (Ramp restyle of Logbook + Passport)
//
// The Logbook and Passport pages are restyled in the visual language of Ramp
// (ramp.com). Ramp does NOT publish an open-source design system: its public
// GitHub org (github.com/ramp-public) holds an MCP server, a CLI, a Python SDK,
// agent skills and a Homebrew tap, and no UI code. So every value below was
// read from the CSS that ramp.com actually ships, fetched on 2026-09-24:
//
//   Page:   https://ramp.com/business-cards , https://ramp.com/pricing
//   CSS:    https://ramp.com/_next/static/immutable/chunks/1dieq6yj626af.css
//           https://ramp.com/_next/static/immutable/chunks/30s468-ox6dfz.css
//           (plus 2h0hnbx10wbnm.css, 2tpc7bh7onmci.css; tokens live in the first two)
//
// READ FROM SOURCE (CSS custom property -> value -> use here)
//   --grayLight       #f4f2f0   warm off-white page (light)            `page`
//   --white           #fff      card surface (light)                   `surface`
//   --text-primary    #0c0a08   ink; also used as a fill via
//                               bg-(--text-primary) -> dark page        `ink`, `page` (dark)
//   --black           #1a1919   dark card surface                      `surface` (dark)
//   --text-hushed     #0c0a0899 (ink at 60%) secondary text           `hushed`
//   --text-hushedReverse #fff9  (white at 60%) secondary on dark      `hushed` (dark)
//   --border-primary  #d2cecb   1px card and row rules (= --grayMedium) `rule`
//   --white-200       white 20%, the dark-surface border
//                     (--nav-button-border: 1.5px solid var(--white-200)) `rule` (dark)
//   --grayDark        #6e6a68   tertiary / disabled                    `grayDark`
//   --solar           #e4f222   THE accent (bg-solar CTA buttons)      `solar`
//   --solarLight      #f5ff78   hover/pressed state of bg-solar        `solarLight`
//   --blaze           #e96516   error ring (aria-invalid)              `blaze`
//   text-[#5AB570]    check_circle glyph in the pricing comparison
//                     table (ramp.com/pricing)                         `positive`
//   Radii  rounded-md .375rem = 6px (every button), rounded-xl .75rem = 12px
//          (email field, cards), KbCard-s 12px, KbCard-l 16px, and
//          `.kbcard-solar { --kbcard-radius-multiplier: 0 }`: a lime card has
//          SQUARE corners. `Radius.button`, `.card`, `.solarCard`.
//   KbCard-s content padding 32px 24px                                 `Space.cardV/H`
//   Row rhythm  py-4 (16px) + border-b border-primary on table rows    `Space.row`
//   Type scale (mobile breakpoint, px size / line height, tracking ~0):
//          headline-xl 40/42 (-0.01px), headline-l 34/38, headline-m 28/32,
//          headline-s 22/26, headline-xs 20/24, body-xl 18/22, body-l 17/23,
//          body-m 15/21, body-s 14/20, body-xs 12/18.                  `TypeScale`
//   Weights: font-normal (400) dominates (413 uses on the two pages);
//          headlines are set in REGULAR weight, not bold. Lausanne ships
//          300 / 350 / 400 / 700 only.
//   Primary CTA  "bg-solar hover:bg-solarLight text-primary rounded-md h-[42px]"
//   Secondary CTA "bg-black hover:bg-black-800 text-primaryReverse rounded-md"
//   Lifted card shadow  0 1px 0 0 var(--border-primary), 0 6px 16px -12px rgba(33,33,33,.4)
//
// FONTS (licensed, not bundled)
//   --font-sans: "Lausanne" (TWK Lausanne, a licensed grotesk served from
//   assets.ramp.com) -> SF Pro (`.default` design), the closest system
//   neo-grotesk. --font-mono: "IBM Plex Mono" -> SF Mono (`.monospaced`).
//   Note: the brief described Ramp as "serif-meets-grotesk". The shipped CSS
//   declares no serif face at all (only Lausanne, IBM Plex Sans/Sans JP/Mono,
//   Material Icons), so no serif is used here; New York was dropped with it.
//
// INFERRED (not a Ramp value; the reason is stated)
//   - Dark mode. ramp.com has no prefers-color-scheme theme; it has dark
//     SECTIONS (bg-black / bg-(--text-primary) with text-primaryReverse,
//     text-hushedReverse and white-200 borders). Dark mode here is built from
//     exactly those section tokens.
//   - Progress-bar fill. Lime on white is ~1.2:1, below the 3:1 non-text
//     minimum, so on light surfaces bars and stamps are ink; on dark surfaces
//     they are solar.
//   - Stamp ink in dark mode is solar for the same reason.
//   - Passport stamp dies keep their shapes (content, not chrome).
//   No Ramp logo, wordmark or card art is used.
enum Ramp {

    // MARK: Color

    static let solar = Color(hex: "E4F222")
    static let solarLight = Color(hex: "F5FF78")
    static let blaze = Color(hex: "E96516")
    static let positive = Color(hex: "5AB570")
    static let grayDark = Color(hex: "6E6A68")
    /// Ink on a solar fill never inverts: `text-primary` on `bg-solar`.
    static let onSolar = Color(hex: "0C0A08")

    static let page = dynamic(light: 0xF4F2F0, dark: 0x0C0A08)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x1A1919)
    static let ink = dynamic(light: 0x0C0A08, dark: 0xFFFFFF)
    static let hushed = dynamic(light: 0x0C0A08, lightAlpha: 0.6, dark: 0xFFFFFF, darkAlpha: 0.6)
    static let rule = dynamic(light: 0xD2CECB, dark: 0xFFFFFF, darkAlpha: 0.2)
    /// Progress track: --grayMedium on light, --white-100 on dark.
    static let track = dynamic(light: 0xD2CECB, dark: 0xFFFFFF, darkAlpha: 0.1)
    /// A faint fill for tiles: --black-50 (5%) on light, --white-50 on dark.
    static let tint = dynamic(light: 0x0C0A08, lightAlpha: 0.05, dark: 0xFFFFFF, darkAlpha: 0.05)
    /// Data marks (bars, stamps): ink on light, solar on dark. Inferred, see notes.
    static let mark = dynamic(light: 0x0C0A08, dark: 0xE4F222)

    // MARK: Shape and space

    enum Radius {
        static let button: CGFloat = 6
        static let card: CGFloat = 12
        static let solarCard: CGFloat = 0
    }

    enum Space {
        static let cardV: CGFloat = 32
        static let cardH: CGFloat = 24
        static let row: CGFloat = 16
    }

    // MARK: Type (mobile sizes of Ramp's named scale)

    enum TypeScale {
        static let headlineXL: CGFloat = 40
        static let headlineS: CGFloat = 22
        static let headlineXS: CGFloat = 20
        static let bodyL: CGFloat = 17
        static let bodyM: CGFloat = 15
        static let bodyS: CGFloat = 14
        static let bodyXS: CGFloat = 12
    }

    private static func dynamic(light: UInt32, lightAlpha: CGFloat = 1,
                                dark: UInt32, darkAlpha: CGFloat = 1) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? uiColor(dark, darkAlpha)
                : uiColor(light, lightAlpha)
        })
    }

    private static func uiColor(_ hex: UInt32, _ alpha: CGFloat) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha)
    }
}
