import SwiftUI

/// One task's checked-bag tag, drawn as the long, skinny thermal strip an
/// airline prints at the counter: IATA Resolution 740 stock is 2⅛ in wide and
/// roughly 18–21 in long, so the tag here keeps a long-strip proportion
/// (about 1:4.8 with its stub) rather than the card it used to be (Pat,
/// 2026-09-30: "like united bag tags long and skinny, one for each").
///
/// Top to bottom it follows the three areas the IATA EBT Implementation
/// Guide 1.2, Annex I (RP 1754) gives a 740 tag, in the order real tags print
/// them (the United UA926 SFO–FRA and Delta DL49 AMS–MSP tags on Wikimedia
/// Commons, both cited in `BagTag.swift`/`BagTagView.swift`):
///
///  1. a pre-printed carrier band in the carrier's colours;
///  2. the three-letter code as the biggest thing on the tag. Real tags put
///     the destination airport there under "TO"; Voyage puts the task's code
///     there, labelled "BAG" because a "TO" over a code that is not an
///     airport read as a destination (Pat, 2026-10-01), and the real
///     destination goes in a reversed routing block under it with its flight
///     and date (Routing Area);
///  3. the passenger's name, which on Voyage is the task itself, in the
///     printed caps real tags use (Information Area);
///  4. the "ladder" and "picket fence" ITF license plates, both orientations,
///     as real tags print them so a scan tunnel reads the bag at any angle
///     (Machine Readable Area), with the 10-digit plate in 4 + 6 grouping;
///  5. a perforation and the claim-check stub (`TaskBagTagStub`).
///
/// The carriers are Voyage's fictional ones (`Carrier`): no real airline's
/// name, colours, logo or issuer code. Stock: standard, priority (red band,
/// earned at Gold) and livery (full carrier colours, earned at Platinum).
struct TaskBagTagView: View {
    let tag: TaskBagTag
    let carrier: Carrier
    /// Routing from the booking. Nil draws the tag without the routing block.
    var content: BagTagContent?
    var showsStub = true
    var claimed = false
    var width: CGFloat = TaskBagTagView.standardWidth
    /// Called when the big code is tapped, to edit it.
    var onEditCode: (() -> Void)?

    /// 110 pt: three tags side by side fit an iPhone 17's 402 pt with gutters.
    static let standardWidth: CGFloat = 110
    /// Body height for a width, before the stub. 4.2 x keeps the strip long.
    static func bodyHeight(for width: CGFloat) -> CGFloat { width * 4.2 }
    static func stubHeight(for width: CGFloat) -> CGFloat { width * 0.62 }

    /// Voyage Air's navy (`Carrier.voyageAir.livery[0]`), not black: the tag
    /// prints in the app's dark blue (Pat, 2026-10-01).
    static let ink = Color(hex: "1D2F5C")
    static let priorityRed = Color(hex: "D2232A")

    var body: some View {
        VStack(spacing: 0) {
            tagBody
                .frame(height: Self.bodyHeight(for: width))
            if showsStub {
                TaskBagTagStub(tag: tag, width: width)
            }
        }
        .frame(width: width)
        .background(Color.white)
        .overlay(alignment: .leading) {
            if tag.style == .livery {
                LinearGradient(colors: carrier.livery, startPoint: .top, endPoint: .bottom)
                    .frame(width: 5)
            }
        }
        .clipShape(TallTagPaper())
        .overlay {
            if claimed {
                Text("CLAIMED")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.positive)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.positive, lineWidth: 2.5))
                    .rotationEffect(.degrees(-62))
                    .opacity(0.9)
                    .transition(.scale(scale: 1.8).combined(with: .opacity))
            }
        }
        .foregroundStyle(Self.ink)
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tag.accessibilityLabel + (claimed ? ", claimed" : ""))
    }

    private var tagBody: some View {
        VStack(spacing: 0) {
            band
            VStack(alignment: .leading, spacing: 7) {
                codeBlock
                if let content { routingBlock(content) }
                nameBlock
                Spacer(minLength: 4)
                ladder
                HStack(spacing: 0) {
                    Text(tag.bagLine)
                    Spacer(minLength: 2)
                    if let content { Text(content.seat) }
                }
                .font(.system(size: 7.5, weight: .heavy, design: .monospaced))
                ITFBarcodeView(digits: tag.plate.digits)
                    .frame(height: 30)
                Text(tag.plate.printed)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, tag.style == .livery ? 10 : 8)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
    }

    // MARK: Band

    @ViewBuilder
    private var band: some View {
        Group {
            switch tag.style {
            case .standard:
                bandRow(carrier.name.uppercased(), symbol: "airplane")
                    .background(carrier.livery[0])
            case .priority:
                VStack(spacing: 1) {
                    bandRow("PRIORITY", symbol: "chevron.right.2")
                    Text(carrier.name.uppercased())
                        .font(.system(size: 6.5, weight: .heavy))
                        .kerning(1)
                        .opacity(0.85)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 3)
                }
                .background(Self.priorityRed)
            case .livery:
                bandRow(carrier.name.uppercased(), symbol: "airplane")
                    .background(LinearGradient(colors: carrier.livery, startPoint: .leading, endPoint: .trailing))
            }
        }
        .foregroundStyle(.white)
    }

    private func bandRow(_ text: String, symbol: String) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 8.5, weight: .black))
                .kerning(1.2)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 2)
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .black))
        }
        .padding(.horizontal, 8)
        .padding(.top, 9)
        .padding(.bottom, 6)
    }

    // MARK: Routing area

    private var codeBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("BAG")
                .font(.system(size: 7, weight: .heavy, design: .monospaced))
                .opacity(0.7)
            Text(tag.code)
                .font(.system(size: 44, weight: .black, design: .rounded))
                .kerning(-0.5)
                .monospaced()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity, alignment: .leading)
                .onTapGesture { onEditCode?() }
                // Without an edit action the code must not swallow taps: at
                // baggage claim the whole tag is the claim button.
                .allowsHitTesting(onEditCode != nil)
                .accessibilityIdentifier("task-tag-code-\(tag.index)")
            if tag.style == .priority {
                Text("FIRST")
                    .font(.system(size: 9, weight: .black))
                    .kerning(1.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Self.priorityRed, in: RoundedRectangle(cornerRadius: 2))
            }
        }
    }

    /// The reversed (white on navy) routing block real tags print for the
    /// final destination, then each transfer point with its inbound flight.
    private func routingBlock(_ content: BagTagContent) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(content.routing, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(line.airportCode)
                        .font(.system(size: line.isFinal ? 15 : 11, weight: .black, design: .monospaced))
                    Text(line.isFinal ? line.flightNumber : "VIA \(line.flightNumber)")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            Text(content.dateText)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.ink, in: RoundedRectangle(cornerRadius: 2))
    }

    // MARK: Information area

    /// Where a real tag prints LIU/PATRICK, Voyage prints the task.
    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("NAME")
                .font(.system(size: 6.5, weight: .heavy, design: .monospaced))
                .opacity(0.55)
            Text(tag.title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .lineLimit(4)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Machine readable area

    /// The ladder: the same plate with its bars stacked, and the number
    /// printed up the side, read by tilting the head as on a real tag.
    private var ladder: some View {
        HStack(spacing: 6) {
            ITFBarcodeView(digits: tag.plate.digits, vertical: true)
                .frame(width: width * 0.42)
            Text(tag.plate.printed)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .fixedSize()
                .rotationEffect(.degrees(90))
                .frame(width: 14)
            Spacer(minLength: 0)
        }
        .frame(height: width * 0.95)
        .accessibilityHidden(true)
    }
}

/// The claim-check stub at the foot of a tag: the part the agent peels off
/// and hands across the counter, and the one you tear at baggage claim.
struct TaskBagTagStub: View {
    let tag: TaskBagTag
    var width: CGFloat = TaskBagTagView.standardWidth
    var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            DashedTagRule()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
                .frame(height: 1)
                .opacity(0.45)
                .padding(.bottom, 3)
            HStack(spacing: 3) {
                Image(systemName: "scissors")
                    .font(.system(size: 7, weight: .bold))
                Text("CLAIM \(tag.code)")
                    .font(.system(size: 8.5, weight: .heavy, design: .monospaced))
                Spacer(minLength: 0)
            }
            ITFBarcodeView(digits: tag.plate.digits)
                .frame(height: 16)
            HStack {
                Text(tag.plate.printed)
                Spacer(minLength: 0)
                if let hint { Text(hint).opacity(0.6) }
            }
            .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
        .frame(width: width, height: TaskBagTagView.stubHeight(for: width), alignment: .top)
        .background(Color.white)
        .foregroundStyle(TaskBagTagView.ink)
        .environment(\.colorScheme, .light)
    }
}

/// Long tag stock: top corners clipped, as the die cut leaves them.
struct TallTagPaper: Shape {
    func path(in rect: CGRect) -> Path {
        let c: CGFloat = 9
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + c, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - c, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + c))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 3))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - 3, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + 3, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - 3), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + c))
        path.closeSubpath()
        return path
    }
}

struct DashedTagRule: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

extension Carrier {
    /// Tag livery colours for the fictional carriers. Chosen to be none of
    /// the real US legacy carriers' marks (SPEC.md (e)).
    var livery: [Color] {
        switch self {
        case .harborline: return [Color(hex: "0F6E6E"), Color(hex: "13A3A3")]
        case .ridgeway: return [Color(hex: "5B3A8C"), Color(hex: "8C5BD6")]
        case .voyageAir: return [Color(hex: "1D2F5C"), Color(hex: "5E8FFF")]
        case .baywater: return [Color(hex: "0E4D92"), Color(hex: "2E86C1")]
        case .northline: return [Color(hex: "2F4F3A"), Color(hex: "4E8A5F")]
        case .lantern: return [Color(hex: "B3541E"), Color(hex: "E3893B")]
        }
    }
}
