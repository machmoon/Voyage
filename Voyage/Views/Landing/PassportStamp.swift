import SwiftUI

// MARK: - Deterministic noise

/// A tiny seeded generator so paper grain and ink mottle render identically
/// every launch (stable QA screenshots, no per-frame shimmer).
private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

// MARK: - Paper

/// Faint printed tooth: thousands of low-alpha specks over the page so the
/// cream stops reading as a flat vector fill and starts reading as stock.
private struct PaperGrain: View {
    var seed: UInt64 = 42
    var tint: Color = Color(hex: "6B5D3E")

    var body: some View {
        Canvas { context, size in
            var rng = SeededRNG(seed: seed)
            let count = Int(size.width * size.height / 90)
            for _ in 0..<count {
                let x = Double(rng.next() % 10_000) / 10_000 * size.width
                let y = Double(rng.next() % 10_000) / 10_000 * size.height
                let r = 0.3 + Double(rng.next() % 100) / 100 * 0.7
                let a = 0.015 + Double(rng.next() % 100) / 100 * 0.05
                let dark = rng.next() % 2 == 0
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                    with: .color((dark ? Color.black : tint).opacity(a))
                )
            }
        }
        .allowsHitTesting(false)
    }
}

/// Security guilloché: faint interference rules behind the stamp, the way a
/// visa page is pre-printed. Kept near-invisible so it reads as texture.
private struct GuillocheField: View {
    var ink: Color

    var body: some View {
        Canvas { context, size in
            let rows = 26
            for i in 0...rows {
                let baseY = size.height * Double(i) / Double(rows)
                var path = Path()
                var x: Double = 0
                while x <= size.width {
                    let y = baseY + sin(x / 26 + Double(i) * 0.6) * 3.4
                    if x == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                    x += 4
                }
                context.stroke(path, with: .color(ink.opacity(0.05)), lineWidth: 0.5)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Ink mottle

/// Worn rubber-stamp ink: scattered soft holes punched out of the mark so the
/// coverage is uneven, plus a couple of heavier bleeds at the edges. Applied
/// with `.destinationOut` over a compositing group.
private struct InkMottle: View {
    var seed: UInt64

    var body: some View {
        Canvas { context, size in
            var rng = SeededRNG(seed: seed)
            // Fine dropout across the whole mark.
            for _ in 0..<140 {
                let x = Double(rng.next() % 10_000) / 10_000 * size.width
                let y = Double(rng.next() % 10_000) / 10_000 * size.height
                let r = 0.4 + Double(rng.next() % 100) / 100 * 2.2
                let a = 0.12 + Double(rng.next() % 100) / 100 * 0.5
                context.fill(
                    Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                    with: .color(.white.opacity(a))
                )
            }
            // A few larger worn patches so one corner presses lighter.
            for _ in 0..<7 {
                let x = Double(rng.next() % 10_000) / 10_000 * size.width
                let y = Double(rng.next() % 10_000) / 10_000 * size.height
                let r = 6 + Double(rng.next() % 100) / 100 * 16
                context.fill(
                    Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                    with: .color(.white.opacity(0.12))
                )
            }
        }
        .allowsHitTesting(false)
    }
}

private struct Inked: ViewModifier {
    var seed: UInt64
    func body(content: Content) -> some View {
        content
            .compositingGroup()
            // Ink bleed: a soft darker echo spread under the mark.
            .background(
                content
                    .blur(radius: 1.4)
                    .opacity(0.35)
            )
            .compositingGroup()
            .overlay(InkMottle(seed: seed).blendMode(.destinationOut))
            .compositingGroup()
            .blur(radius: 0.35)
    }
}

private extension View {
    func inked(seed: UInt64) -> some View { modifier(Inked(seed: seed)) }
}

// MARK: - Entry stamp

/// The inked cachet pressed into the page. Not a clean vector badge: a slightly
/// irregular double keyline, corner ticks, the destination set in the app's own
/// monospaced code face, and mottled worn ink in the tonal passport blue.
struct EntryStamp: View {
    let code: String
    let city: String
    let dateText: String
    let milesText: String
    var ink: Color = Theme.passportInk
    var seed: UInt64 = 907

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 7) {
                rule
                Text("ADMITTED")
                    .font(.system(size: 11, weight: .heavy))
                    .kerning(2.5)
                    .fixedSize()
                Image(systemName: "airplane")
                    .font(.system(size: 9, weight: .black))
                rule
            }

            Text(code)
                .font(.system(size: 46, weight: .black, design: .monospaced))
                .kerning(2)
                .padding(.top, 1)

            Text(city.uppercased())
                .font(.system(size: 10, weight: .bold))
                .kerning(3.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(dateText)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .kerning(1.5)
                .padding(.top, 3)

            Text(milesText)
                .font(.system(size: 8.5, weight: .heavy))
                .kerning(2)
                .padding(.top, 1)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
        .overlay(cornerTicks)
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(ink, lineWidth: 2.6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(ink.opacity(0.9), lineWidth: 1)
                .padding(-4)
        )
        .inked(seed: seed)
        .opacity(0.92)
    }

    private var rule: some View {
        Rectangle().fill(ink).frame(width: 22, height: 1).opacity(0.9)
    }

    private var cornerTicks: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let len: CGFloat = 9, inset: CGFloat = 7
            Path { p in
                // four L-shaped register ticks
                for corner in 0..<4 {
                    let right = corner % 2 == 1
                    let bottom = corner >= 2
                    let x = right ? w - inset : inset
                    let y = bottom ? h - inset : inset
                    let dx: CGFloat = right ? -len : len
                    let dy: CGFloat = bottom ? -len : len
                    p.move(to: CGPoint(x: x, y: y))
                    p.addLine(to: CGPoint(x: x + dx, y: y))
                    p.move(to: CGPoint(x: x, y: y))
                    p.addLine(to: CGPoint(x: x, y: y + dy))
                }
            }
            .stroke(ink, lineWidth: 1.4)
        }
    }
}

// MARK: - Passport page

/// A single open passport page: warm stock with grain, a pre-printed keyline
/// frame and guilloché wash, official page furniture, a bound spine shadow on
/// the gutter edge, and a machine-readable zone across the foot. The stamp is
/// composed on top by the caller.
struct PassportPage<Overlay: View>: View {
    var size: CGSize = CGSize(width: 300, height: 384)
    var mrzTop: String
    var mrzBottom: String
    @ViewBuilder var overlay: () -> Overlay

    private let paper = Theme.passportPaper
    private let furniture = Color(hex: "8A7B57")
    private let ink = Theme.passportInk

    var body: some View {
        ZStack {
            // Stock, warmed slightly toward the gutter.
            LinearGradient(
                colors: [paper, Color(hex: "EFE7D3")],
                startPoint: .topTrailing, endPoint: .bottomLeading
            )

            GuillocheField(ink: ink)
                .padding(20)

            PaperGrain(tint: furniture)

            // Pre-printed frame.
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(furniture.opacity(0.4), lineWidth: 1)
                .padding(13)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(furniture.opacity(0.22), lineWidth: 0.5)
                .padding(17)

            VStack(spacing: 0) {
                header
                Spacer()
                machineReadableZone
            }
            .padding(.top, 20)
            .padding(.bottom, 14)

            overlay()

            // Bound spine shadow on the gutter edge.
            LinearGradient(
                colors: [.black.opacity(0.16), .clear],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: 26)
            .frame(maxWidth: .infinity, alignment: .leading)
            .blendMode(.multiply)
            .allowsHitTesting(false)

            // Soft page vignette.
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.black.opacity(0.08), lineWidth: 10)
                .blur(radius: 8)
                .blendMode(.multiply)
                .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.45), radius: 22, x: -4, y: 14)
    }

    private var header: some View {
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                Rectangle().fill(furniture.opacity(0.5)).frame(width: 14, height: 1)
                Text("VOYAGE PASSPORT")
                    .font(.system(size: 10, weight: .heavy))
                    .kerning(2.5)
                Rectangle().fill(furniture.opacity(0.5)).frame(width: 14, height: 1)
            }
            .foregroundStyle(furniture)
            Text("Entries and departures")
                .font(.system(size: 9, weight: .medium))
                .kerning(0.4)
                .foregroundStyle(furniture.opacity(0.75))
        }
    }

    private var machineReadableZone: some View {
        VStack(spacing: 2) {
            Text(mrzTop)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            Text(mrzBottom)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        }
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .kerning(0.5)
        .foregroundStyle(furniture.opacity(0.55))
        .padding(.horizontal, 22)
    }
}
