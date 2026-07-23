import SwiftUI

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

    static let accent = Color(hex: "5E8FFF")
    static let statusAmber = Color(hex: "E5B567")
    static let destructive = Color(hex: "E65F5C")

    // MARK: Surfaces and type

    static let ink = Color(hex: "0B0E14")
    static let surfaceDark = Color(hex: "11151C")
    static let surfaceElevated = Color(hex: "191E27")
    static let surfaceSubtle = Color(hex: "242B36")
    static let textPrimary = Color(hex: "F5F7FA")
    static let textSecondary = Color(hex: "A8B0BE")

    /// Unified dark surfaces — one family across in-flight, arrival, divert, logbook.
    static let surfaceWarm = surfaceDark
    static let loungeGold = statusAmber

    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let nightSkyTop = Color(hex: "080C14")
    static let nightSkyBottom = Color(hex: "172239")
    static let boardingBackdrop = Color(hex: "101722")
    static let passportPaper = Color(hex: "F4EFE4")
    static let passportCover = Color(hex: "182131")
    /// A quieter tonal blue for repeated passport marks on light surfaces.
    static let passportInk = Color(hex: "4268A8")

    static let cornerRadius: CGFloat = 18
    static let cardCornerRadius: CGFloat = 16

    // Seat map: cool paper page, accent-tinted seat states (one palette
    // with the rest of the app), airline-convention gold for First.
    static let seatMapBackground = Color(hex: "F2F4F8")
    static let seatMapInk = Color(hex: "14161C")
    static let seatMapFuselage = Color.white
    /// Wings and tailplane sit a step darker than the fuselage so the airframe
    /// reads as one object with the cabin on top of it.
    static let seatMapWing = Color(hex: "DBE1EA")
    static let seatOpen = Color(hex: "DCE8FF")
    static let seatChosen = accent
    static let seatTakenFill = Color(hex: "D5D9E0")
    static let seatFirstGold = Color(hex: "E9CD82")
    static let seatFirstGoldLight = Color(hex: "F3E2AC")
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
            .minimumScaleFactor(0.65)
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
