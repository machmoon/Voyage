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
// MARK: - DESIGN-NOTES (Airbnb color pass over the Ramp base, 2026-09-24)
//
// The Ramp structure above stays (warm #f4f2f0 page, white cards, one lime
// accent, 12pt cards, 6pt buttons). What changed is the COLOR ROLES, which now
// follow Airbnb's shipped DLS tokens. Research notes, with local copies of
// every file: scratchpad/airbnb/airbnb-design-research.md. The source is the
// `:root` block of Airbnb's guest stylesheet
//   https://a0.muscache.com/airbnb/static/packages/web/common/frontend/core-guest-spa/entrypoints/client.37c1c188d0.css
// (cited below as "client.css"), light tokens and their `-dark` twins.
//
//   Airbnb token (light / dark)                  -> Voyage token
//   --palette-text-primary     #222222 / #F7F7F7 -> `ink`   (was #0c0a08 / #fff)
//   --palette-text-secondary   #6C6C6C / #A6A6A6 -> `hushed` (was ink @ 60%)
//   --palette-border-secondary #DDDDDD / #2C2C2C -> `rule`  (card hairline)
//   --palette-bg-divider       #EBEBEB / #2C2C2C -> `divider`, `track`
//   --palette-bg-secondary     #F7F7F7 / (bg-quaternary-dark) #222222 -> `tint`
//   --palette-bg-primary-dark  #111111           -> `page` (dark)
//   --palette-bg-surface-elevated-dark #191919   -> `surface` (dark)
//   --palette-text-success     #038026           -> `positive` (light)
//   The warm page stays Ramp's #f4f2f0: Airbnb's own new warm surface,
//   --palette-bg-surface-beige #F4F2EC, is within 2 units of it.
//
// THE ROLE SPLIT. Airbnb gives each brand hue two jobs: rausch-600 #FF385C
// fills, rausch-700 #DA1249 is `--palette-text-brand` / `icon-core` /
// `border-brand` on white (3.52:1 vs 5.04:1), and on dark the roles swap
// (`--palette-text-brand-dark: #FF385C`). Applied to Ramp's lime:
//   `solar`     #E4F222  FILL ONLY (CTA, ticket stub, Insights chart area).
//                        1.23:1 on white, so never text or a thin line.
//                        #222222 on it is 12.9:1.
//   `accentInk` #5B6300  text, icons, 1.5pt strokes, progress fills on light.
//                        [derived, not an Airbnb value: "lime800" in the notes]
//                        Measured (WCAG 2.x relative luminance):
//                        6.50:1 on #FFFFFF, 6.07:1 on #F7F7F7, 5.82:1 on #F4F2F0.
//               dark    #E4F222 itself, the text-brand-dark swap:
//                        14.25:1 on #191919, 15.31:1 on #111111.
// Brand is not error: Airbnb keeps rausch apart from --palette-arches #C13515,
// and Rausch pink is never used here (it is Airbnb's logo color).
//
// DISABLED = GREY, NOT FADED. Airbnb's hidden passport stamp flattens its ink
// to grey with a CSS filter instead of lowering opacity (passport-spa
// client.00ff6058aa.css, "filter: brightness(0) ... invert(72%)"). `muted`
// (#C1C1C1 = grey-500 light / #515151 = grey-800 dark, client.css ramp) is
// that grey for the stopped-early ticket.
enum Ramp {

    // MARK: Color

    /// Fill-only lime (`--solar`). See the role split above.
    static let solar = Color(hex: "E4F222")
    static let solarLight = Color(hex: "F5FF78")
    static let blaze = Color(hex: "E96516")
    static let grayDark = Color(hex: "6E6A68")
    /// Ink on a solar fill never inverts: Airbnb's #222222 on the lime.
    static let onSolar = Color(hex: "222222")

    static let page = dynamic(light: 0xF4F2F0, dark: 0x111111)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x191919)
    static let ink = dynamic(light: 0x222222, dark: 0xF7F7F7)
    static let hushed = dynamic(light: 0x6C6C6C, dark: 0xA6A6A6)
    static let rule = dynamic(light: 0xDDDDDD, dark: 0x2C2C2C)
    static let divider = dynamic(light: 0xEBEBEB, dark: 0x2C2C2C)
    /// Progress track: --palette-bg-divider.
    static let track = dynamic(light: 0xEBEBEB, dark: 0x2C2C2C)
    /// Tile fill: --palette-bg-secondary / bg-quaternary-dark.
    static let tint = dynamic(light: 0xF7F7F7, dark: 0x222222)
    /// Lime for text, icons, strokes and data marks. [derived] #5B6300 on
    /// light, the lime itself on dark. Contrast is in the notes above.
    static let accentInk = dynamic(light: 0x5B6300, dark: 0xE4F222)
    /// Data marks (progress fills) are the accent ink, so a bar clears 3:1
    /// against its track in both modes.
    static let mark = accentInk
    /// --palette-text-success #038026 (5.10:1 on white); ramp.com's #5AB570
    /// on dark, where #038026 would sink (6.93:1 on #191919).
    static let positive = dynamic(light: 0x038026, dark: 0x5AB570)
    /// Disabled grey, the hidden-stamp recolor: grey-500 / grey-800.
    static let muted = dynamic(light: 0xC1C1C1, dark: 0x515151)

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
