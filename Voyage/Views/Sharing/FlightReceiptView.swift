import SwiftUI

/// Strava-style share card: route, stats overlay, stamp — rendered via
/// `ImageRenderer` for the iOS share sheet (Instagram, Messages, etc.).
struct FlightReceiptView: View {
    let originCode: String
    let destinationCode: String
    let destinationCity: String
    let flightNumber: String
    let focusDurationText: String
    let miles: Int
    let seat: String
    let accentColor: Color
    let caption: String?
    let intentionsCompleted: Int
    let intentionsTotal: Int
    let viaCode: String?

    init(session: FlightSession, caption: String?) {
        originCode = session.itinerary.origin.code
        destinationCode = session.itinerary.destination.code
        destinationCity = session.itinerary.destination.city
        flightNumber = session.itinerary.primaryFlightNumber
        focusDurationText = session.itinerary.totalFocusDuration.shortDurationText
        miles = Int(session.completedMiles)
        seat = session.seat
        accentColor = session.itinerary.destination.accentColor
        self.caption = caption?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        intentionsTotal = session.intentions.count
        intentionsCompleted = session.logEntry?.intentionsCompleted.filter(\.self).count ?? 0
        viaCode = session.itinerary.connection?.code
    }

    init(entry: LogbookEntry) {
        originCode = entry.originCode
        destinationCode = entry.destinationCode
        destinationCity = entry.destination.city
        flightNumber = entry.flightNumber
        focusDurationText = entry.focusSeconds.shortDurationText
        miles = Int(entry.miles)
        seat = entry.seat
        accentColor = entry.destination.accentColor
        caption = entry.shareCaption
        intentionsTotal = entry.intentions.count
        intentionsCompleted = zip(entry.intentions, entry.intentionsCompleted).filter(\.1).count
        viaCode = entry.connectionCode
    }

    /// Fixed 3:4 aspect for story-style sharing (Strava sticker stats pattern).
    static let renderSize = CGSize(width: 390, height: 520)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.surfaceSubtle, Theme.ink],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Theme.accent.opacity(0.2), .clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 330
            )

            VStack(spacing: 0) {
                header
                Spacer(minLength: 12)
                routeRow
                Spacer(minLength: 16)
                statsGrid
                if let caption {
                    captionBlock(caption)
                        .padding(.top, 16)
                } else if intentionsTotal > 0 {
                    captionBlock(bagsSummary)
                        .padding(.top, 16)
                }
                Spacer(minLength: 16)
                stampBadge
                footer
            }
            .padding(24)
        }
        .frame(width: Self.renderSize.width, height: Self.renderSize.height)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("VOYAGE AIR")
                    .font(.system(size: 10, weight: .heavy))
                    .kerning(2)
                    .foregroundStyle(.white.opacity(0.55))
                Text("Flight receipt")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
            Text(flightNumber)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.accent)
        }
    }

    private var routeRow: some View {
        VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 16) {
                airportBlock(originCode, label: "FROM")
                Image(systemName: "airplane")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                airportBlock(destinationCode, label: "TO")
            }
            if let viaCode {
                Text("1 stop · via \(viaCode)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private func airportBlock(_ code: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .kerning(1.2)
                .foregroundStyle(.white.opacity(0.45))
            Text(code)
                .font(.system(size: 36, weight: .black, design: .monospaced))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
    }

    private var statsGrid: some View {
        HStack(spacing: 0) {
            statCell("Focus", focusDurationText)
            divider
            statCell("Miles", "+\(miles.formatted())")
            divider
            statCell("Seat", seat)
        }
        .padding(.vertical, 14)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.15))
            .frame(width: 1, height: 28)
    }

    private func statCell(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .kerning(1)
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func captionBlock(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.85))
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var bagsSummary: String {
        "\(intentionsCompleted)/\(intentionsTotal) bags claimed at arrival"
    }

    private var stampBadge: some View {
        VStack(spacing: 4) {
            Text("ADMITTED")
                .font(.system(size: 9, weight: .heavy))
                .kerning(2)
            Text(destinationCode)
                .font(.system(size: 28, weight: .black, design: .monospaced))
            Text(destinationCity.uppercased())
                .font(.system(size: 9, weight: .bold))
                .kerning(1)
        }
        .foregroundStyle(accentColor)
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(accentColor, lineWidth: 2.5)
        )
        .opacity(0.9)
    }

    private var footer: some View {
        Text(Date.now.formatted(date: .abbreviated, time: .omitted).uppercased())
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.35))
            .padding(.top, 8)
    }
}

// MARK: - Rendering

/// A rendered receipt: the shareable PNG, plus the same bitmap as a `UIImage`
/// for `SharePreview`. Both come from one rasterisation, because encoding a PNG
/// and immediately decoding it back into a `UIImage` was pure waste.
struct RenderedReceipt {
    let pngData: Data
    let image: UIImage
}

enum FlightReceiptRenderer {
    @MainActor
    static func pngData(session: FlightSession, caption: String?) -> Data? {
        render(FlightReceiptView(session: session, caption: caption))?.pngData
    }

    @MainActor
    static func pngData(entry: LogbookEntry) -> Data? {
        render(FlightReceiptView(entry: entry))?.pngData
    }

    /// Rasterises a logbook receipt.
    ///
    /// This is expensive: measured at ~149 ms on the iPhone 17 simulator in a
    /// Debug build, because it lays out a whole SwiftUI card and encodes it at
    /// 3x. Never call it from a view body. `LogbookReceiptStore` exists so the
    /// logbook list can pay it once per flight rather than once per frame.
    @MainActor
    static func receipt(entry: LogbookEntry) -> RenderedReceipt? {
        render(FlightReceiptView(entry: entry))
    }

    @MainActor
    private static func render(_ view: FlightReceiptView) -> RenderedReceipt? {
        #if DEBUG
        renderCount += 1
        #endif
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        guard let image = renderer.uiImage, let data = image.pngData() else { return nil }
        return RenderedReceipt(pngData: data, image: image)
    }

    #if DEBUG
    /// Counts real rasterisations so tests can pin how often the logbook pays
    /// for one, instead of timing it on a shared machine.
    @MainActor private(set) static var renderCount = 0
    @MainActor static func resetRenderCount() { renderCount = 0 }
    #endif
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
