import SwiftUI
import SwiftData

/// The wallet-style Voyage Miles card: tier, member number, member since,
/// status miles with the welcome bonus on its own line, the bar to the next
/// tier, what each tier opens, and a link to the Flight Manual.
struct MembershipCardView: View {
    @Query(sort: \LogbookEntry.date) private var entries: [LogbookEntry]
    @Environment(\.dismiss) private var dismiss
    @State private var membership = Membership.shared
    @State private var showsManual = false
    @State private var tilt: Double = 0
    @State private var fill: Double = 0
    @State private var shine = false

    private var progress: MilesProgress { MilesProgress(entries: entries) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    card
                        .rotation3DEffect(.degrees(tilt), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                        .padding(.top, 8)
                    milesBreakdown
                    tierLadder
                    Button {
                        Haptics.tap()
                        showsManual = true
                    } label: {
                        Label("Why this works", systemImage: "book.pages")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Theme.surfaceSubtle, in: Capsule())
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .accessibilityIdentifier("membership-why-this-works")
                }
                .padding(20)
            }
            .background(Theme.boardingBackdrop.ignoresSafeArea())
            .navigationTitle("Voyage Miles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsManual) { FlightManualView() }
        .onAppear {
            tilt = -14
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) { tilt = 0 }
            withAnimation(.easeOut(duration: 1.1).delay(0.3)) { fill = 1 }
            withAnimation(.easeInOut(duration: 2.2).delay(0.5)) { shine = true }
        }
    }

    // MARK: Card

    private var card: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: TierStyle.card(progress.tier),
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            // Guilloche-style arcs, the security pattern on real cards.
            Canvas { context, size in
                for i in 0..<14 {
                    let r = CGFloat(40 + i * 18)
                    let rect = CGRect(x: size.width * 0.78 - r, y: size.height * 1.05 - r,
                                      width: r * 2, height: r * 2)
                    context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.06)), lineWidth: 1)
                }
            }
            LinearGradient(colors: [.clear, .white.opacity(0.28), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 70)
                .rotationEffect(.degrees(22))
                .offset(x: shine ? 420 : -140)
                .blendMode(.plusLighter)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("VOYAGE MILES")
                        .font(.system(size: 13, weight: .black))
                        .tracking(3)
                    Spacer()
                    TierBadge(tier: progress.tier, large: true)
                }
                Spacer()
                Text(memberNumber)
                    .font(.system(size: 19, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .accessibilityIdentifier("membership-number")
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MEMBER SINCE").font(.system(size: 8, weight: .bold)).opacity(0.6)
                        Text(memberSince).font(.caption.weight(.semibold))
                    }
                    Spacer()
                    if membership.isFirstClass {
                        Label("VOYAGE FIRST", systemImage: "carseat.right.fill")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(Theme.seatFirstGoldLight)
                    }
                }
                .padding(.top, 10)
            }
            .foregroundStyle(.white)
            .padding(20)
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 14)
        .accessibilityElement(children: .combine)
    }

    private var memberNumber: String {
        guard let first = entries.first else { return "VY ••• ••••••" }
        let seed = BagTagLicensePlate.fnv1a("member|\(Int(first.date.timeIntervalSince1970))")
        let digits = String(format: "%09d", Int(seed % 1_000_000_000))
        return "VY \(digits.prefix(3)) \(digits.dropFirst(3))"
    }

    private var memberSince: String {
        guard let first = entries.first else { return "Your first flight" }
        return first.date.formatted(.dateTime.month(.abbreviated).year())
    }

    // MARK: Miles

    private var milesBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            row("Miles flown", MilesFormat.number(progress.flownMiles))
            row("Welcome bonus", progress.bonusMiles > 0 ? "+500" : "At first departure")
            Divider().overlay(Color.white.opacity(0.1))
            row("Status miles", MilesFormat.number(progress.statusMiles), bold: true)
            if progress.next != nil {
                MilesBar(progress: progress, fill: fill).frame(height: 10)
                Text(progress.headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(progress.isAlmostThere ? Theme.seatFirstGold : Theme.textPrimary)
            }
            Text(VoyageMiles.explainer)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            if progress.bonusMiles > 0 {
                Text(VoyageMiles.welcomeBonusReason)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(18)
        .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func row(_ title: String, _ value: String, bold: Bool = false) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .monospacedDigit()
                .fontWeight(bold ? .bold : .semibold)
                .foregroundStyle(Theme.textPrimary)
        }
        .font(.subheadline)
    }

    private var tierLadder: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("STATUS")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(Theme.textSecondary)
            ForEach(FlyerTier.allCases) { tier in
                HStack(spacing: 12) {
                    TierBadge(tier: tier)
                        .frame(width: 84, alignment: .leading)
                    Text(tier.perkDescription)
                        .font(.subheadline)
                        .foregroundStyle(tier <= progress.tier ? Theme.textPrimary : Theme.textSecondary)
                    Spacer()
                    if tier <= progress.tier {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.seatFirstGold)
                    } else {
                        Text(MilesFormat.number(tier.threshold))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            Text("Status is earned in the logbook and can't be bought.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(18)
        .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
