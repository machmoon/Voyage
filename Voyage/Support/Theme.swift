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
    var accentColor: Color { Color(hex: accentHex) }
}

enum Theme {
    /// The single app accent — a calm aviation blue. Functional UI (CTAs,
    /// selection, route lines, progress) uses this everywhere; per-city
    /// colors are reserved for logbook stamps, where they read as collectibles.
    static let accent = Color(hex: "4E8CFF")

    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let nightSkyTop = Color(hex: "060B1F")
    static let nightSkyBottom = Color(hex: "1B2447")
    /// Solid backdrop behind the boarding pass — solid (not a gradient) so
    /// perforation punch-outs can match it exactly.
    static let boardingBackdrop = Color(hex: "10152E")

    // Light seat map (reference design): cream page, ink wings,
    // green seat states.
    static let seatMapBackground = Color(hex: "F4F1E8")
    static let seatMapInk = Color(hex: "121512")
    static let seatMapFuselage = Color.white
    static let seatAvailableGreen = Color(hex: "BCE3A5")
    static let seatFirstGold = Color(hex: "E9CD82")
    static let seatFirstGoldLight = Color(hex: "F3E2AC")
    static let seatSelectedGreen = Color(hex: "2E6B3F")
    static let seatBookedGray = Color(hex: "AAB0B3")

    // Cabin seat map (airline map, not Settings)
    static let cabinCanvas = Color(hex: "101218")
    static let cabinFuselage = Color(hex: "1A1D26")
    static let cabinAisle = Color(hex: "252933")
    static let cabinMetal = Color(hex: "3A4050")
    static let seatAvailable = Color(hex: "4A5163")
    static let seatAvailableTop = Color(hex: "5A6278")
    static let seatTaken = Color(hex: "2A2E38")
    static let seatTakenTop = Color(hex: "323744")
    static let cabinLabel = Color.white.opacity(0.55)
    static let cabinSecondary = Color.white.opacity(0.72)
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
