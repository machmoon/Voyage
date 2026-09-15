import SwiftUI
import UIKit

extension Color {
    /// Creates a color from a 6-digit hex string like "FF7A45".
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: .alphanumerics.inverted)).scanHexInt64(&value)
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

extension Airport {
    /// Airport colors are data, not interface chrome. A single Voyage ink keeps
    /// stamps, receipts, and destination moments visually coherent.
    var accentColor: Color { Theme.accent }
}

enum Theme {
    // MARK: Brand and semantic color

    /// The one Voyage accent. Everything chromatic in the interface is this
    /// color or a tint of it; the only colors that are not are the neutral
    /// surfaces below, `destructive`, and the two fixed document palettes
    /// (passport, boarding pass) which stand for physical objects.
    ///
    /// Note for the owner: the design brief specifies `4E8CFF` and this ships
    /// `5E8FFF`. They differ only in the red channel (78 vs 94), which is not
    /// perceptible side by side. `5E8FFF` is kept because it is what every
    /// shipped screenshot and the submitted build already use, and because
    /// `FlightReplayView.swift:853` hard-codes the same RGB by hand for the
    /// video export path. Changing this constant alone would silently make the
    /// exported replay video a different blue from the app. Settle it by
    /// changing both together.
    static let accent = Color(hex: "5E8FFF")
    static let destructive = Color(hex: "E65F5C")

    /// The kicker above a moment that is not an action: "PASSPORT CONTROL",
    /// lounge headers, arrival captions. Was an amber (`E5B567`), which made it
    /// a second brand color on functional UI. It is the accent now.
    ///
    /// Kept under the old name so callers in the working tree still build.
    /// New code should use `Theme.accent` directly and this token should go.
    static let statusAmber = accent

    // MARK: Surfaces and type

    static let ink = Color(hex: "0B0E14")
    static let surfaceDark = Color(hex: "11151C")
    static let surfaceElevated = Color(hex: "191E27")
    static let surfaceSubtle = Color(hex: "242B36")
    static let textPrimary = Color(hex: "F5F7FA")
    static let textSecondary = Color(hex: "A8B0BE")

    /// Unified dark surfaces — one family across in-flight, arrival, divert, logbook.
    static let surfaceWarm = surfaceDark

    /// Lounge gold. Unused in the tree today, but `LayoverLoungeView` is being
    /// rewritten and hard-codes `E8B23A` twice, so this stays available rather
    /// than being deleted out from under that work. It is now an explicit gold
    /// rather than an alias of `statusAmber`, which is the accent: a token
    /// named "gold" must not quietly resolve to blue. The design note stands
    /// that the lounge should move to `accent` and `destructive`.
    static let loungeGold = Color(hex: "E5B567")

    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let nightSkyTop = Color(hex: "080C14")
    static let nightSkyBottom = Color(hex: "172239")
    static let boardingBackdrop = Color(hex: "101722")
    static let passportPaper = Color(hex: "F4EFE4")
    static let passportCover = Color(hex: "182131")
    /// A quieter tonal blue for repeated passport marks on light surfaces.
    ///
    /// This is the ink for every stamp in the collection. A single ink is the
    /// point: a passport is stamped by many different ports with the same class
    /// of die, and a grid where every city prints a different hue reads as a
    /// sticker sheet, not a document. Per-city color survives in exactly one
    /// place, the arrival moment itself (`ArrivalFlowView`), where the stamp is
    /// alone on the page and the city is the subject.
    static let passportInk = Color(hex: "4268A8")

    /// Blocked foil on the passport cover. Was a gold (`E4C98A`), which put a
    /// fifth hue in the palette; a foil in the brand color is both normal for
    /// real travel documents and the thing that makes this Voyage's passport
    /// rather than a generic one. Derived from `accent`, lightened so it reads
    /// as pressed metal against `passportCover` navy.
    static let passportFoil = Color(hex: "C6D8FF")

    static let cornerRadius: CGFloat = 18
    static let cardCornerRadius: CGFloat = 16

    // Seat map: cool paper page, accent-tinted seat states (one palette
    // with the rest of the app), airline-convention gold for First.
    static let seatMapBackground = Color(hex: "F2F4F8")
    static let seatMapInk = Color(hex: "14161C")
    static let seatMapFuselage = Color.white
    /// Wings and tailplane sit a step darker than the fuselage so the airframe
    /// reads as one object with the cabin on top of it.
    /// DBE1EA was two steps off the page (F2F4F8) and the wing past the
    /// screen edge read as margin, not metal (QA/qa-seatmap-*-wing.png).
    static let seatMapWing = Color(hex: "C5CDD9")
    /// Engine nacelles, a step darker again so the inlet reads ahead of the wing.
    static let seatMapNacelle = Color(hex: "AEB8C6")
    static let seatOpen = Color(hex: "DCE8FF")
    static let seatChosen = accent
    static let seatTakenFill = Color(hex: "D5D9E0")

    /// First-class seats.
    ///
    /// This is a deliberate exception to the one-accent rule and it must stay
    /// gold. Cabin class is information, not decoration: telling premium from
    /// economy at a glance is the single most load-bearing convention on an
    /// airline seat map, and the rule exists to kill per-item flair on
    /// functional UI, not to erase a distinction the screen is for. The gold is
    /// also doing specific work: it is the stand-in for the reference carrier's
    /// own premium color, which cannot be copied (App Review 5.2.5).
    ///
    /// A previous pass moved this into the accent family. That was wrong twice
    /// over. It reached into `SeatSelectionView` through a token while that
    /// file was being actively rewritten, and it left First and Available as
    /// two near-identical pale blues, which is less legible than what it
    /// replaced. Do not do it again.
    static let seatFirstGold = Color(hex: "E9CD82")
    static let seatFirstGoldLight = Color(hex: "F3E2AC")
}

// MARK: - Type scale

/// Voyage's typography, as sizes that actually respond to Dynamic Type.
///
/// The problem this solves: the app sets type with `Font.system(size:weight:design:)`
/// in 179 places. That takes a fixed point size and does **not** scale with
/// Dynamic Type, so every custom surface (home header, in-flight countdown,
/// boarding pass, seat map, passport) stays frozen while the surfaces built
/// from system components (`Form`, `List`) grow. At AX3 the app reads as two
/// different apps. SwiftUI offers no `Font.system(size:relativeTo:)`: the
/// `relativeTo:` parameter exists only on `Font.custom(_:size:relativeTo:)`,
/// which needs a named font, so the system font has no built-in way to scale
/// from an arbitrary size.
///
/// Prior art followed: **mozilla-mobile/firefox-ios**,
/// `BrowserKit/Sources/Common/Utilities/DynamicFontHelper.swift`, which solves
/// exactly this with
/// `UIFontMetrics(forTextStyle:).scaledFont(for: UIFont.systemFont(ofSize:weight:))`
/// and an optional `sizeCap`, then hands the scaled `pointSize` back to a plain
/// `Font.system(size:)` in `DynamicFont.swift`. `Theme.scaledFont` is that
/// function.
///
/// One deliberate deviation. For the SwiftUI path Voyage uses `@ScaledMetric`
/// (see `voyageFont` below) rather than calling `UIFontMetrics` directly.
/// Firefox needs the `UIFont` because it also feeds UIKit; Voyage does not, and
/// `@ScaledMetric` is the framework's own plumbing, so SwiftUI invalidates the
/// view when the size category changes instead of returning a value captured at
/// render time. `@ScaledMetric` is used the same way in firefox-ios
/// (`Client/Frontend/Settings/AppearanceSettings/Zoom/ZoomSiteListView.swift`)
/// and is the wrapper Signal models its own on
/// (`signalapp/Signal-iOS`, `SignalUI/SwiftUIExtensions/AccessibleLayoutMetric.swift`).
///
/// The `TextStyle` naming for a design-system scale follows
/// `wordpress-mobile/WordPress-iOS`,
/// `Modules/Sources/DesignSystem/Foundation/TextStyle.swift`, which is the name
/// with the most precedent across large shipped codebases (WordPress, Signal,
/// stripe-ios) and matches Apple's own `Font.TextStyle`.
extension Theme {

    /// Which Dynamic Type ramp a given design size should ride.
    ///
    /// Pairing matters: a size scales along the curve of the style it is
    /// anchored to, so a 46pt stamp code anchored to `.caption` would barely
    /// move while a 9pt label anchored to `.largeTitle` would explode. Anchor
    /// to the style whose default size is nearest.
    static func textStyle(forSize size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11: return .caption2
        case ..<13: return .caption
        case ..<15: return .footnote
        case ..<16: return .subheadline
        case ..<17: return .callout
        case ..<20: return .body
        case ..<22: return .title3
        case ..<28: return .title2
        case ..<34: return .title
        default: return .largeTitle
        }
    }

    /// A system font at `size` that scales with Dynamic Type.
    ///
    /// Non-view contexts only: `ImageRenderer` share cards, `Canvas` drawing,
    /// anything without a SwiftUI environment. In a view, use `voyageFont`,
    /// which invalidates correctly.
    ///
    /// `cap` is Firefox's `sizeCap`: the ceiling past which the size stops
    /// growing, for type inside fixed geometry.
    static func scaledFont(size: CGFloat,
                           weight: Font.Weight = .regular,
                           design: Font.Design = .default,
                           relativeTo textStyle: Font.TextStyle? = nil,
                           cap: CGFloat? = nil) -> Font {
        let style = textStyle ?? Self.textStyle(forSize: size)
        let metrics = UIFontMetrics(forTextStyle: UIFont.TextStyle(style))
        let base = UIFont.systemFont(ofSize: size, weight: UIFont.Weight(weight))
        var scaled = metrics.scaledFont(for: base).pointSize
        if let cap { scaled = min(scaled, cap) }
        return .system(size: scaled, weight: weight, design: design)
    }
}

/// `.voyageFont(23, weight: .black)` in place of
/// `.font(.system(size: 23, weight: .black))`.
///
/// The conversion is mechanical: keep the number, keep the weight, keep the
/// design, drop `.font(.system(` and the closing paren. The text style is
/// inferred from the size unless you pass one, so a bulk conversion needs no
/// per-call judgment, and anything that needs a specific ramp can say so.
extension View {
    func voyageFont(_ size: CGFloat,
                    weight: Font.Weight = .regular,
                    design: Font.Design = .default,
                    relativeTo textStyle: Font.TextStyle? = nil,
                    cap: CGFloat? = nil) -> some View {
        modifier(VoyageScaledFont(size: size,
                                  weight: weight,
                                  design: design,
                                  textStyle: textStyle ?? Theme.textStyle(forSize: size),
                                  cap: cap))
    }
}

private struct VoyageScaledFont: ViewModifier {
    @ScaledMetric private var scaledSize: CGFloat

    private let weight: Font.Weight
    private let design: Font.Design
    private let cap: CGFloat?

    init(size: CGFloat,
         weight: Font.Weight,
         design: Font.Design,
         textStyle: Font.TextStyle,
         cap: CGFloat?) {
        _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
        self.weight = weight
        self.design = design
        self.cap = cap
    }

    func body(content: Content) -> some View {
        content.font(.system(size: cap.map { min(scaledSize, $0) } ?? scaledSize,
                             weight: weight,
                             design: design))
    }
}

// MARK: Bridges

private extension UIFont.TextStyle {
    init(_ style: Font.TextStyle) {
        switch style {
        case .largeTitle: self = .largeTitle
        case .title: self = .title1
        case .title2: self = .title2
        case .title3: self = .title3
        case .headline: self = .headline
        case .subheadline: self = .subheadline
        case .body: self = .body
        case .callout: self = .callout
        case .footnote: self = .footnote
        case .caption: self = .caption1
        case .caption2: self = .caption2
        @unknown default: self = .body
        }
    }
}

private extension UIFont.Weight {
    init(_ weight: Font.Weight) {
        switch weight {
        case .ultraLight: self = .ultraLight
        case .thin: self = .thin
        case .light: self = .light
        case .regular: self = .regular
        case .medium: self = .medium
        case .semibold: self = .semibold
        case .bold: self = .bold
        case .heavy: self = .heavy
        case .black: self = .black
        default: self = .regular
        }
    }
}

// MARK: - Shared button styles

struct VoyagePrimaryButtonStyle: ButtonStyle {
    var foreground: Color = .black
    var background: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(background.opacity(configuration.isPressed ? 0.88 : 1),
                        in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

struct VoyageAccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.88 : 1),
                        in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// Small uppercase caption used all over the boarding-pass UI.
struct FieldLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .kerning(1.4)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            // "PASSENGER" in a third of a pass at accessibility sizes needs
            // more than 0.65 (QA/e2e-ax-06-boarding-pass.png: "PASSEN…").
            .allowsTightening(true)
            .minimumScaleFactor(0.5)
    }
}

extension TimeInterval {
    /// "2h 00m" / "45m" style formatting.
    var shortDurationText: String {
        let minutes = Int((self / 60).rounded())
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        return "\(m)m"
    }

    /// The in-flight countdown face. Above ten minutes it reads in whole
    /// minutes ("1h 23m") — a ticking seconds column on a two-hour study
    /// session just invites clock-watching. Inside the last ten minutes it
    /// switches to "09:59", where the seconds actually mean something.
    var focusCountdownText: String {
        guard self >= 600 else { return clockText }
        let minutes = Int((self / 60).rounded(.up))
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        return "\(m)m"
    }

    /// "1:23:45" or "23:45" countdown formatting.
    var clockText: String {
        let total = max(0, Int(self.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}
