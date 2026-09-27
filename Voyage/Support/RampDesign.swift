import SwiftUI
import UIKit

// MARK: - DESIGN-NOTES (Ramp layout for the Logbook)
//
// The Logbook keeps Ramp's LAYOUT (ramp.com): white cards on a page, a 12pt
// card radius, 6pt buttons, 32/24 card padding, 16pt row rhythm and the
// headline/body type scale below. Ramp publishes no design system, so those
// values were read from the CSS ramp.com ships, fetched 2026-09-24:
//   https://ramp.com/_next/static/immutable/chunks/1dieq6yj626af.css
//   https://ramp.com/_next/static/immutable/chunks/30s468-ox6dfz.css
//   Radii  rounded-md 6px (buttons), rounded-xl 12px (cards)     `Radius`
//   KbCard-s content padding 32px 24px                            `Space.cardV/H`
//   Row rhythm py-4 (16px)                                        `Space.row`
//   Type (mobile): headline-xl 40, headline-s 22, headline-xs 20,
//   body-l 17, body-m 15, body-s 14, body-xs 12                   `TypeScale`
//   Fonts: Lausanne and IBM Plex Mono are licensed and not bundled; SF Pro
//   and SF Mono stand in.
//
// COLOR is no longer Ramp's (or Airbnb's). The color review of 2026-09-24
// (design/color-pass) found the sheet carrying three palettes on top of
// Voyage's own blue: Ramp lime #E4F222 and a derived olive #5B6300 as the
// accent, Airbnb greys for text, and Meta blue #0866FF on the Passport tab.
// The HIG asks for one meaning per color ("Avoid using the same color to mean
// different things", developer.apple.com/design/human-interface-guidelines/color)
// and for system background colors in sheets so base/elevated works
// (.../dark-mode, "Prefer the system background colors"). Every color token
// below is now an alias of a `Theme` token; the names are kept so the view
// code reads the same. No lime remains.
enum Ramp {

    // MARK: Color (aliases of the shared Theme tokens)

    static let page = Theme.groupedBackground
    static let surface = Theme.groupedSurface
    static let ink = Theme.label
    static let hushed = Theme.secondaryLabel
    static let grayDark = Theme.secondaryLabel
    static let rule = Theme.separator
    static let divider = Theme.separator
    static let track = Theme.track
    /// Icon tile fill.
    static let tile = Theme.quietFill
    /// Accent for text, icons, strokes and data marks.
    static let accentInk = Theme.tint
    /// Progress fills.
    static let mark = Theme.tint
    static let positive = Theme.positive
    /// Disabled / not landed.
    static let muted = Theme.inactive

    // MARK: Shape and space

    enum Radius {
        static let button: CGFloat = 6
        static let card: CGFloat = 12
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
}
