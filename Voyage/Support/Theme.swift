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
    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let nightSkyTop = Color(hex: "060B1F")
    static let nightSkyBottom = Color(hex: "1B2447")

    /// Monospaced, wide-tracked airline label ("GATE", "SEAT", "FLIGHT").
    static func airlineLabel(_ text: String) -> Text {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .kerning(1.6)
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
