import SwiftUI
import UIKit

// MARK: - DESIGN-NOTES
//
// The Logbook and Passport pages are drawn in the design language of Meta's
// apps (Facebook's "Comet" UI, which Threads and Instagram web share). Meta
// publishes no complete design system, so every value below is copied from a
// source that could actually be read, and each one says where it came from.
//
// 1. Shipped CSS, read from the live pages on 2026-09-24 (not guessed):
//    - https://www.facebook.com/help/ inlines the Comet token sheet as
//      `:root, .__fb-light-mode { ... }` and `.__fb-dark-mode { ... }`
//      (476 custom properties each). Colors, radii, button heights, list-cell
//      heights and the tab underline below come from there verbatim:
//      --web-wash, --card-background, --card-background-flat, --primary-text,
//      --secondary-text, --primary-icon, --secondary-icon, --disabled-icon,
//      --divider, --accent, --blue-link, --primary-button-background,
//      --primary-button-text, --secondary-button-background,
//      --secondary-button-text, --primary-deemphasized-button-background,
//      --primary-deemphasized-button-text, --wash, --list-cell-chevron,
//      --progress-ring-blue-background, --highlight-bg, --positive,
//      --card-corner-radius (8px), --button-corner-radius (6px),
//      --button-height-medium (36px), --button-height-large (40px),
//      --list-cell-min-height (52px), --tab-underline-height (3px),
//      --text-badge-corner-radius (4px), --image-corner-radius (4px).
//    - https://www.threads.net/ and https://www.instagram.com/ inline the same
//      sheet. Threads ships identical --web-wash (#F0F2F5 / #18191A),
//      --card-background (#FFFFFF / #242526), --divider, --primary-text and
//      --secondary-text, which is why these read as "Meta" rather than as one
//      product. (Instagram's own --ig-* ramp differs and is not used here.)
//    - The type ramp is a tally of the atomic stylesheets that page loads
//      (static.xx.fbcdn.net/rsrc.php/v5/yE/... and .../yt/...):
//      font-size .9375rem (15px, line-height 1.2667) is the most used size,
//      then .8125rem (13px, 1.3077), 1.0625rem (17px, 1.2941), 1.5rem (24px,
//      1.1667) and 2.125rem (34px). Weights in use: 400, 500, 600, 700.
//    - The same sheet also carries a logged-out "2025" set on
//      https://www.facebook.com/login/ (#0064E0 buttons, 16px cards, 22px
//      pill buttons, #111112 text). That is the login screen only; the app
//      surfaces a traveler sees after signing in use the Comet set above, so
//      that is the one followed here.
//
// 2. Readable open-source code from Meta:
//    - github.com/facebook/stylex packages/docs/src/theming/vars.stylex.ts and
//      packages/shared-ui/src/tokens.stylex.ts were read. They theme the
//      StyleX docs site (purple primary, Tailwind-like scale), not Meta's
//      products, so nothing was taken from them. Their `light-dark()` pairing
//      of every token is the pattern the asset catalog's light/dark Color Sets
//      now serve (see `Theme`).
//    - github.com/facebook/react-strict-dom and github.com/facebook/docusaurus
//      ship no product palette either (only their own docs sites' custom.css).
//
// 3. Inspected, not readable as source: page structure. The Passport page is
//    laid out like a Facebook profile (cover, overlapping round photo with a
//    card-colored ring and a camera badge, bold name, a stats line, detail
//    rows with leading icons, then full-bleed sections on the wash), and the
//    Logbook like a Facebook feed/menu (full-bleed white sections separated
//    by 8pt of wash, 36pt gray icon circles, blue underline tabs). There is
//    no public source for those screens; the arrangement is from looking at
//    the shipped apps, and every color and size inside it is from (1).
//
// 4. Fonts: the CSS asks for `Optimistic` / `Optimistic AI VF`, Meta's
//    licensed product face. It is not bundled. Text uses the iOS system font,
//    which is also what Comet's own `--font-family-apple` token falls back to
//    (`system-ui, -apple-system, BlinkMacSystemFont, '.SFNSText-Regular'`).
//
// 5. No Meta, Facebook, Instagram or Threads logos, wordmarks or glyphs are
//    used. Icons are SF Symbols.

/// Comet tokens as SwiftUI values. Each color resolves per trait collection,
/// so the pages follow the system light/dark setting with no extra code.
enum MetaStyle {

    // MARK: Color
    //
    // Color pass (2026-09-24, design/color-pass): the Comet colors listed in
    // (1) above are no longer used. Meta blue #0866FF was a second blue on
    // top of Voyage's own, and Comet's wash/card greys (#F0F2F5 / #18191A,
    // #242526) were a third page color in one sheet next to the Flights tab.
    // Each token keeps its Comet name, so the layout code is unchanged, and
    // resolves to the shared `Theme` token for the same role. Layout values
    // in (1) (radii, heights, the 3pt tab underline) still stand.

    static let webWash = Theme.groupedBackground
    static let cardBackground = Theme.groupedSurface
    static let primaryText = Theme.label
    static let secondaryText = Theme.secondaryLabel
    static let primaryIcon = Theme.label
    static let secondaryIcon = Theme.secondaryLabel
    static let divider = Theme.separator
    static let accent = Theme.tint
    static let primaryButtonBackground = Theme.accentFill
    static let primaryButtonText = Color.white
    static let secondaryButtonBackground = Theme.quietFill
    static let secondaryButtonText = Theme.label
    static let deemphasizedButtonBackground = Theme.tint.opacity(0.12)
    static let deemphasizedButtonText = Theme.tint
    /// Photo placeholder disc: opaque, one step off the card.
    static let wash = Color(uiColor: .systemGray4)
    static let progressTrack = Theme.track
    /// The empty cover: the accent at 12% over the card.
    static let highlightBackground = Theme.tint.opacity(0.12)
    static let positive = Theme.positive

    // MARK: Shape and size (px in the CSS, points here)

    static let cardCornerRadius: CGFloat = 8          // --card-corner-radius
    static let buttonCornerRadius: CGFloat = 6        // --button-corner-radius
    static let badgeCornerRadius: CGFloat = 4         // --text-badge-corner-radius
    static let buttonHeightMedium: CGFloat = 36       // --button-height-medium
    static let buttonHeightLarge: CGFloat = 40        // --button-height-large
    static let listCellMinHeight: CGFloat = 52        // --list-cell-min-height
    static let tabUnderlineHeight: CGFloat = 3        // --tab-underline-height
    /// The gap of wash between full-bleed sections in the feed.
    static let sectionGap: CGFloat = 8
    static let gutter: CGFloat = 16
}

// MARK: - Type ramp

extension View {
    /// 15pt: body text and list-cell titles (.9375rem).
    func metaBody(_ weight: Font.Weight = .regular) -> some View {
        voyageFont(15, weight: weight, relativeTo: .subheadline)
    }
    /// 13pt: timestamps, captions and cell subtitles (.8125rem).
    func metaMeta(_ weight: Font.Weight = .regular) -> some View {
        voyageFont(13, weight: weight, relativeTo: .footnote)
    }
    /// 17pt: section headers (1.0625rem).
    func metaHeadline() -> some View {
        voyageFont(17, weight: .bold, relativeTo: .headline)
    }
    /// 24pt: a profile name (1.5rem).
    func metaTitle() -> some View {
        voyageFont(24, weight: .bold, relativeTo: .title2)
    }
}

// MARK: - Surfaces

extension View {
    /// A full-bleed feed section: card background edge to edge, content inset
    /// by the 16pt gutter, sitting on the wash.
    func metaSection(vertical: CGFloat = 12) -> some View {
        self
            .padding(.horizontal, MetaStyle.gutter)
            .padding(.vertical, vertical)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MetaStyle.cardBackground)
    }
}

/// Section title row: bold 17pt title, optional trailing text in the link blue
/// the way Comet puts "See all" beside a section.
struct MetaSectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .metaHeadline()
                .foregroundStyle(MetaStyle.primaryText)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .metaBody()
                    .monospacedDigit()
                    .foregroundStyle(MetaStyle.secondaryText)
            }
        }
    }
}

/// The 36pt gray circle every Comet menu row and header icon sits in
/// (--secondary-button-background behind a --primary-icon glyph).
struct MetaIconCircle: View {
    let systemName: String
    var diameter: CGFloat = 36
    var tint: Color = MetaStyle.primaryIcon
    var fill: Color = MetaStyle.secondaryButtonBackground

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: diameter * 0.44, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: diameter, height: diameter)
            .background(fill, in: Circle())
    }
}

/// Thin determinate bar in the blue progress pair
/// (--progress-ring-blue-background track, --accent fill).
struct MetaProgressBar: View {
    let fraction: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(MetaStyle.progressTrack)
                Capsule().fill(MetaStyle.accent)
                    .frame(width: max(height, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Buttons

/// Comet's three button fills: primary (solid blue), secondary (gray) and
/// deemphasized (pale blue with blue text). 6pt corners, 36pt tall.
struct MetaButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, deemphasized }
    var kind: Kind = .primary
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .metaBody(.semibold)
            .foregroundStyle(foreground)
            .padding(.horizontal, 16)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: MetaStyle.buttonHeightMedium)
            .background(background, in: RoundedRectangle(cornerRadius: MetaStyle.buttonCornerRadius,
                                                        style: .continuous))
            // Comet darkens a pressed button with a 5% black overlay
            // (--secondary-button-pressed / --primary-deemphasized-button-pressed).
            .overlay(
                RoundedRectangle(cornerRadius: MetaStyle.buttonCornerRadius, style: .continuous)
                    .fill(Color.black.opacity(configuration.isPressed ? 0.05 : 0))
            )
    }

    private var foreground: Color {
        switch kind {
        case .primary: return MetaStyle.primaryButtonText
        case .secondary: return MetaStyle.secondaryButtonText
        case .deemphasized: return MetaStyle.deemphasizedButtonText
        }
    }

    private var background: Color {
        switch kind {
        case .primary: return MetaStyle.primaryButtonBackground
        case .secondary: return MetaStyle.secondaryButtonBackground
        case .deemphasized: return MetaStyle.deemphasizedButtonBackground
        }
    }
}

// MARK: - Tabs

/// Comet's profile tabs: text only, secondary gray at rest, accent blue with a
/// 3pt accent underline when selected (--tab-underline-height).
///
/// This is a real `UISegmentedControl`, restyled through the image-based
/// segment API, rather than a row of SwiftUI buttons. VoyageUITests reach the
/// tabs as `app.segmentedControls.buttons["Passport"]`, and VoiceOver keeps
/// announcing them as a tab control with a selected state.
struct MetaTabControl<Tab: Hashable>: UIViewRepresentable {
    let tabs: [(tab: Tab, title: String)]
    @Binding var selection: Tab

    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl(items: tabs.map(\.title))
        control.apportionsSegmentWidthsByContent = true
        control.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        style(control)
        control.setContentHuggingPriority(.required, for: .horizontal)
        return control
    }

    func updateUIView(_ control: UISegmentedControl, context: Context) {
        context.coordinator.parent = self
        if let index = tabs.firstIndex(where: { $0.tab == selection }),
           control.selectedSegmentIndex != index {
            control.selectedSegmentIndex = index
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor final class Coordinator: NSObject {
        var parent: MetaTabControl
        init(parent: MetaTabControl) { self.parent = parent }

        @objc func changed(_ control: UISegmentedControl) {
            let index = control.selectedSegmentIndex
            guard parent.tabs.indices.contains(index) else { return }
            Haptics.tap()
            parent.selection = parent.tabs[index].tab
        }
    }

    private func style(_ control: UISegmentedControl) {
        let height: CGFloat = 44
        let clear = Self.image(height: height, underline: nil)
        let selected = Self.image(height: height, underline: UIColor(Theme.tint))
        control.setBackgroundImage(clear, for: .normal, barMetrics: .default)
        control.setBackgroundImage(clear, for: .highlighted, barMetrics: .default)
        control.setBackgroundImage(selected, for: .selected, barMetrics: .default)
        control.setBackgroundImage(selected, for: [.selected, .highlighted], barMetrics: .default)
        control.setDividerImage(Self.image(height: height, underline: nil, width: 20),
                                forLeftSegmentState: .normal, rightSegmentState: .normal, barMetrics: .default)
        control.setDividerImage(Self.image(height: height, underline: nil, width: 20),
                                forLeftSegmentState: .selected, rightSegmentState: .normal, barMetrics: .default)
        control.setDividerImage(Self.image(height: height, underline: nil, width: 20),
                                forLeftSegmentState: .normal, rightSegmentState: .selected, barMetrics: .default)

        let font = UIFontMetrics(forTextStyle: .subheadline)
            .scaledFont(for: .systemFont(ofSize: 15, weight: .semibold))
        control.setTitleTextAttributes([
            .font: font,
            .foregroundColor: UIColor.secondaryLabel,
        ], for: .normal)
        control.setTitleTextAttributes([
            .font: font,
            .foregroundColor: UIColor(Theme.tint),
        ], for: .selected)
        control.setContentPositionAdjustment(UIOffset(horizontal: 0, vertical: -1),
                                             forSegmentType: .any, barMetrics: .default)
    }

    /// A stretchable, transparent segment background, with the 3pt underline
    /// along its bottom edge when `underline` is set.
    private static func image(height: CGFloat, underline: UIColor?, width: CGFloat = 8) -> UIImage {
        let size = CGSize(width: width, height: height)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            if let underline {
                underline.setFill()
                ctx.fill(CGRect(x: 0, y: height - MetaStyle.tabUnderlineHeight,
                                width: width, height: MetaStyle.tabUnderlineHeight))
            }
        }
        return image.resizableImage(withCapInsets: UIEdgeInsets(top: 0, left: 3, bottom: MetaStyle.tabUnderlineHeight + 1, right: 3),
                                    resizingMode: .stretch)
    }
}
