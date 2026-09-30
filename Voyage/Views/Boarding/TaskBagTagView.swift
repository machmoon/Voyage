import SwiftUI

/// One task's bag tag, drawn in the layout US legacy carriers print on
/// thermal stock: a carrier band, the destination-style three-letter code as
/// the biggest thing on the tag, "BAG 2 OF 3", the plate in 4 + 6 grouping
/// with its ITF barcode, and a perforated claim stub. The carriers are
/// Voyage's fictional ones (`Carrier`, `BagTag.swift`): no real airline's
/// name, colours or issuer code.
///
/// Stock: standard (white), priority (a red PRIORITY band and a FIRST routing
/// block, like the tags carriers issue premium passengers) and carrier
/// livery. Priority and livery are Voyage First.
struct TaskBagTagView: View {
    let tag: TaskBagTag
    let carrier: Carrier
    var showsStub = true
    var claimed = false
    /// Called when the big code is tapped, to edit it.
    var onEditCode: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            band
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    codeView
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(tag.bagLine)
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        if tag.style == .priority {
                            Text("FIRST")
                                .font(.system(size: 12, weight: .black))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Self.priorityRed, in: RoundedRectangle(cornerRadius: 3))
                        }
                    }
                }
                Text(tag.title)
                    .font(.custom("Noteworthy-Bold", size: 15, relativeTo: .body))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                ITFBarcodeView(digits: tag.plate.digits)
                    .frame(height: 26)
                    .accessibilityHidden(true)
                Text(tag.plate.printed)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 10)
            if showsStub {
                perforation
                stub
            }
        }
        .foregroundStyle(Color(hex: "14161C"))
        .background(Color.white)
        .clipShape(BagTagPaper())
        .overlay {
            if claimed {
                Text("CLAIMED")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.positive)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.positive, lineWidth: 3))
                    .rotationEffect(.degrees(-14))
                    .opacity(0.85)
                    .transition(.scale(scale: 1.8).combined(with: .opacity))
            }
        }
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tag.accessibilityLabel + (claimed ? ", claimed" : ""))
    }

    static let priorityRed = Color(hex: "D2232A")

    private var codeView: some View {
        Text(tag.code)
            .font(.system(size: 46, weight: .black, design: .rounded))
            .kerning(1)
            .monospaced()
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .contentTransition(.numericText())
            .onTapGesture { onEditCode?() }
            .accessibilityIdentifier("task-tag-code-\(tag.index)")
    }

    @ViewBuilder
    private var band: some View {
        switch tag.style {
        case .standard:
            HStack {
                Text(carrier.name.uppercased())
                Spacer()
                Text("CHECKED")
            }
            .font(.system(size: 9, weight: .heavy))
            .kerning(1.5)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .overlay(alignment: .bottom) { Rectangle().frame(height: 1).opacity(0.8) }
        case .priority:
            HStack {
                Text("PRIORITY")
                    .font(.system(size: 13, weight: .black))
                    .kerning(3)
                Spacer()
                Image(systemName: "chevron.right.2")
                    .font(.system(size: 11, weight: .black))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Self.priorityRed)
        case .livery:
            HStack {
                Text(carrier.name.uppercased())
                    .font(.system(size: 11, weight: .black))
                    .kerning(2)
                Spacer()
                Image(systemName: "airplane")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(LinearGradient(colors: carrier.livery, startPoint: .leading, endPoint: .trailing))
        }
    }

    private var perforation: some View {
        Rectangle()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .frame(height: 1)
            .opacity(0.35)
            .padding(.horizontal, 6)
    }

    private var stub: some View {
        HStack {
            Text("CLAIM \(tag.code)")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
            Spacer()
            Text(tag.plate.printed)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
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

/// Tags stacked like a fan, newest on top, each printed in with a drop.
struct TaskTagFan: View {
    let tags: [TaskBagTag]
    let carrier: Carrier
    var onEditCode: (TaskBagTag) -> Void

    var body: some View {
        ZStack {
            ForEach(tags) { tag in
                let spread = Double(tag.index) - Double(tags.count - 1) / 2
                TaskBagTagView(tag: tag, carrier: carrier) { onEditCode(tag) }
                    .frame(width: 190)
                    .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
                    .rotationEffect(.degrees(spread * 7), anchor: .bottom)
                    .offset(x: spread * 62, y: abs(spread) * 10)
                    .zIndex(Double(tag.index))
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.8).combined(with: .opacity)))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: tags)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task-tag-fan")
    }
}
