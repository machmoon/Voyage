import SwiftUI

// MARK: - Barcode

/// A real Interleaved 2 of 5 symbol for `digits`, drawn bar by bar from
/// `InterleavedTwoOfFive.encode`. Any laser or phone scanner that reads ITF
/// reads this. `vertical` stacks the bars top to bottom, the "ladder"
/// orientation real tags print beside the "picket fence" one so a scan tunnel
/// catches the bag at any angle (both appear on the United UA926 tag on
/// Wikimedia Commons).
struct ITFBarcodeView: View {
    let digits: String
    var vertical = false

    /// Ten narrow modules of blank paper each side: ITF needs a quiet zone,
    /// and the EBT guide (Annex I, "Machine Readable Area") says displays
    /// "must respect the need for quiet zones around the barcode".
    static let quietZoneModules = 10

    var body: some View {
        Canvas { context, size in
            guard let elements = try? InterleavedTwoOfFive.encode(digits) else { return }
            let total = InterleavedTwoOfFive.moduleCount(elements) + Self.quietZoneModules * 2
            let length = vertical ? size.height : size.width
            // Snap the module to whole device pixels where it fits, so narrow
            // and wide stay an exact 1:3 instead of anti-aliasing into grey.
            let module = max(0.5, length / CGFloat(total))
            var cursor = (length - module * CGFloat(total)) / 2 + module * CGFloat(Self.quietZoneModules)
            for element in elements {
                let run = module * CGFloat(element.modules)
                if element.isBar {
                    let rect = vertical
                        ? CGRect(x: 0, y: cursor, width: size.width, height: run)
                        : CGRect(x: cursor, y: 0, width: run, height: size.height)
                    context.fill(Path(rect), with: .color(.primary))
                }
                cursor += run
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Tag body

/// The printed part of the tag, everything above the claim-check stub.
///
/// Layout follows the three areas IATA defines for a Resolution 740 tag
/// (EBT Implementation Guide 1.2, Annex I): a Routing Area with the final
/// destination on top and transfer points below it, each beside its flight
/// number and date; an Information Area with the ten-digit plate and the
/// passenger; and a Machine Readable Area holding the ITF license plate.
/// Proportions are from real tags on Wikimedia Commons: the reversed
/// (white-on-black) destination block and small city line under it from the
/// United UA926 SFO-FRA tag, the rotated "TO" and a "VIA" row with its own
/// flight from the Delta DL49 AMS-MSP tag.
///
/// Voyage keeps no passenger name (the boarding pass prints none either,
/// `BoardingPassView.swift:326`), so the passenger slot carries the seat.
/// The "contents" block is Voyage's own: real tags have nothing there, but a
/// traveler can write on any tag, so the study tasks go in by hand.
struct BagTagBody<Contents: View>: View {
    let content: BagTagContent
    let bagCount: Int
    @ViewBuilder let contents: () -> Contents

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 10)
            routing
            informationLine
                .padding(.top, 12)
            machineReadable
                .padding(.top, 8)
            rule.padding(.vertical, 12)
            contentsArea
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    private var rule: some View {
        Rectangle().fill(.primary.opacity(0.85)).frame(height: 1)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(content.issuingCarrierName)
                    .font(.system(size: 13, weight: .heavy))
                    .kerning(2)
                Spacer()
                Text("FROM \(content.originCode)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
            }
            Text(content.plate.printed)
                .font(.system(size: 22, weight: .heavy, design: .monospaced))
                .kerning(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bag tag from \(content.issuingCarrierName.capitalized), tag number \(content.plate.spoken)")
    }

    private var routing: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(content.routing, id: \.self) { line in
                if line.isFinal {
                    finalDestination(line)
                } else {
                    rule
                    viaLine(line)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(routingSummary)
    }

    /// Resolution 740 asks for Arial Rounded MT Bold "or similar" in the
    /// routing area (EBT guide, Annex I); SF Rounded heavy is the similar face
    /// every iPhone has.
    private func finalDestination(_ line: BagTagContent.RoutingLine) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Text("TO")
                .font(.system(size: 10, weight: .bold))
                .kerning(1)
                .fixedSize()
                .rotationEffect(.degrees(-90))
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 3) {
                Text(line.airportCode)
                    .font(.system(size: 62, weight: .heavy, design: .rounded))
                    .kerning(2)
                    .foregroundStyle(Color(.systemBackground))
                    .padding(.horizontal, 10)
                    .padding(.vertical, -4)
                    .background(.primary, in: RoundedRectangle(cornerRadius: 3))
                Text(content.destinationCity)
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                flightAndDate(line.flightNumber)
                    .padding(.bottom, 8)
            }
        }
    }

    private func viaLine(_ line: BagTagContent.RoutingLine) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Text("VIA")
                .font(.system(size: 10, weight: .bold))
                .kerning(1)
                .fixedSize()
                .rotationEffect(.degrees(-90))
                .frame(width: 12)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(line.airportCode)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .kerning(1)
                flightAndDate(line.flightNumber)
            }
        }
        .padding(.vertical, 4)
    }

    private func flightAndDate(_ flightNumber: String) -> some View {
        HStack(spacing: 10) {
            Text(flightNumber)
            Text(content.dateText)
        }
        .font(.system(size: 15, weight: .bold, design: .monospaced))
    }

    /// Information Area: the numeric plate, then the passenger slot. The EBT
    /// guide's example line is "4220123456 PETER/JOHNMR PNRADR".
    private var informationLine: some View {
        HStack(spacing: 10) {
            Text(content.plate.digits)
            Text("SEAT \(content.seat)")
            Spacer(minLength: 0)
            Text(bagCount == 1 ? "1 PC" : "\(bagCount) PCS")
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Seat \(content.seat)")
    }

    private var machineReadable: some View {
        ITFBarcodeView(digits: content.plate.digits)
            .frame(height: 62)
    }

    /// The traveler's own writing, beside a ladder copy of the barcode.
    private var contentsArea: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CONTENTS")
                    .font(.system(size: 9, weight: .bold))
                    .kerning(1.2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                contents()
            }
            ITFBarcodeView(digits: content.plate.digits, vertical: true)
                .frame(width: 30)
                .frame(minHeight: 120)
        }
    }

    private var routingSummary: String {
        let vias = content.routing.filter { !$0.isFinal }.reversed()
        var text = "To \(content.destinationCity.capitalized), \(content.destinationCode)"
        if !vias.isEmpty {
            text += ", via " + vias.map(\.airportCode).joined(separator: " and ")
        }
        let flights = content.routing.reversed().map(\.flightNumber)
        text += ". " + (flights.count == 1 ? "Flight " : "Flights ")
            + flights.joined(separator: " and ") + ", " + content.dateText
        return text
    }
}

// MARK: - Claim check

/// The peel-off claim check at the foot of the tag: the part the traveler
/// keeps and shows at the carousel. It repeats the plate and its barcode, the
/// destination and the first flight, which is the "Minimum Electronic Baggage
/// Claim Receipt Data" of Resolution 752 as the EBT guide lists it (§7.4 step
/// 5), less the passenger name Voyage does not hold.
struct BagTagClaimStub: View {
    let content: BagTagContent
    let peelable: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("CLAIM CHECK")
                    .font(.system(size: 8, weight: .bold))
                    .kerning(1.2)
                    .foregroundStyle(.secondary)
                Text(content.destinationCode)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                // The flight into the final destination, as the tag's top
                // routing line prints it.
                Text(content.routing.first?.flightNumber ?? "")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            VStack(alignment: .leading, spacing: 3) {
                ITFBarcodeView(digits: content.plate.digits)
                    .frame(height: 30)
                Text(content.plate.printed)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
            }
            if peelable {
                Image(systemName: "hand.draw.fill")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }
}

// MARK: - Bag-drop printer

/// The kiosk the tag feeds out of. Same construction as the gate printer on
/// the boarding pass (`BoardingPassView.printerHousing`), kept separate so the
/// two steps can differ in size and label, and drawn from Theme tokens only.
struct BagDropPrinterHousing: View {
    let working: Bool
    let feedComplete: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [Theme.surfaceElevated, Theme.surfaceDark],
                                     startPoint: .top, endPoint: .bottom))
                .frame(height: 50)
                .overlay(alignment: .top) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 7, height: 7)
                            .shadow(color: Theme.accent.opacity(working ? 0.9 : 0.3),
                                    radius: working ? 5 : 1)
                            .opacity(working || feedComplete ? 1 : 0.5)
                        Text(feedComplete ? "TAG READY" : "BAG DROP · PRINTING")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .kerning(1.2)
                            .foregroundStyle(Theme.textSecondary.opacity(0.6))
                        Spacer()
                        HStack(spacing: 3) {
                            ForEach(0..<3, id: \.self) { _ in
                                Capsule().fill(Theme.textPrimary.opacity(0.09)).frame(width: 14, height: 3)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                }
                .shadow(color: .black.opacity(0.25), radius: 10, y: 5)

            Capsule()
                .fill(Theme.ink.opacity(0.8))
                .frame(height: 6)
                .overlay(
                    Capsule()
                        .fill(Theme.accent.opacity(working ? 0.85 : 0))
                        .frame(height: 3)
                        .blur(radius: 2)
                        .padding(.horizontal, 40)
                )
                .padding(.horizontal, 6)
                .offset(y: 4)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Paper shapes

/// Tag silhouette: a strip with its top corners clipped, as tag stock is die
/// cut, and a flat foot where the claim check joins.
struct BagTagPaper: Shape {
    func path(in rect: CGRect) -> Path {
        let c: CGFloat = 12
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + c, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - c, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + c))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + c))
        path.closeSubpath()
        return path
    }
}
