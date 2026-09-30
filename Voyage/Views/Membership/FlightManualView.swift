import SafariServices
import SwiftUI

/// "The Flight Manual": why Voyage works like an airline. One card per
/// mechanic, each with what the study found in one plain sentence and a
/// tappable citation. Every claim is what the cited paper reports, nothing
/// stronger (docs/shipaton/SPEC.md, P0-6 and "No invented numbers").
struct FlightManualView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var openURL: IdentifiedURL?
    @State private var appeared = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Why Voyage works like an airline.")
                        .font(.title2.bold())
                        .foregroundStyle(Theme.textPrimary)
                    Text("Every mechanic in Voyage is borrowed from something airlines, coffee shops or psychologists measured.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.bottom, 4)
                    ForEach(Array(FlightManual.findings.enumerated()), id: \.element.id) { index, finding in
                        FindingCard(finding: finding) { openURL = IdentifiedURL(url: finding.url) }
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 18)
                            .animation(.spring(response: 0.5, dampingFraction: 0.85)
                                .delay(0.04 * Double(index)), value: appeared)
                    }
                    Text(FlightManual.footer)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                }
                .padding(20)
            }
            .background(Theme.boardingBackdrop.ignoresSafeArea())
            .navigationTitle("The Flight Manual")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("flight-manual")
        .onAppear { appeared = true }
        .sheet(item: $openURL) { item in
            SafariView(url: item.url).ignoresSafeArea()
        }
    }
}

private struct FindingCard: View {
    let finding: FlightManual.Finding
    let openCitation: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: finding.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.seatFirstGold)
                    .frame(width: 30, height: 30)
                    .background(Theme.seatFirstGold.opacity(0.14), in: Circle())
                Text(finding.mechanic)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
            }
            Text(finding.copy)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Haptics.tap()
                openCitation()
            } label: {
                Label(finding.citation, systemImage: "doc.text.magnifyingglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the paper")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// The findings, as data so a test can check every card has a source.
enum FlightManual {
    struct Finding: Identifiable, Equatable {
        let mechanic: String
        let symbol: String
        let copy: String
        let citation: String
        let url: URL
        var id: String { mechanic }
    }

    static let footer = "These are findings from specific studies, not promises about your grades."

    // swiftlint:disable line_length
    static let findings: [Finding] = [
        Finding(mechanic: "The boarding pass", symbol: "ticket.fill",
                copy: "Tearing the pass is a ritual. In experiments, even a made-up ritual before a hard task lowered anxiety and improved performance.",
                citation: "Brooks et al., 2016, Organizational Behavior and Human Decision Processes",
                url: URL(string: "https://faculty.haas.berkeley.edu/jschroeder/Publications/Rituals%20OBHDP.pdf")!),
        Finding(mechanic: "The route", symbol: "point.topleft.down.to.point.bottomright.curvepath.fill",
                copy: "You pick the length before you start. Students given the choice set deadlines for themselves, and those deadlines helped.",
                citation: "Ariely & Wertenbroch, 2002, Psychological Science",
                url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/12009041/")!),
        Finding(mechanic: "One tag per task", symbol: "tag.fill",
                copy: "Naming exactly what you'll do, and when, is one of the most reliable tricks in motivation research. Across 94 tests, it had a medium-to-large effect.",
                citation: "Gollwitzer & Sheeran, 2006, Advances in Experimental Social Psychology",
                url: URL(string: "https://www.researchgate.net/publication/37367696_Implementation_Intentions_and_Goal_Achievement_A_Meta-Analysis_of_Effects_and_Processes")!),
        Finding(mechanic: "The welcome bonus", symbol: "gift.fill",
                copy: "A loyalty card with two stamps already on it gets finished more often than a shorter blank one, even when the work is identical. Your 500 miles are those two stamps.",
                citation: "Nunes & Drèze, 2006, Journal of Consumer Research",
                url: URL(string: "https://academic.oup.com/jcr/article-abstract/32/4/504/1787425")!),
        Finding(mechanic: "Miles to Silver", symbol: "flag.checkered",
                copy: "Coffee-card customers bought faster the closer they got to a free coffee. We show your finish line as a flight you can take.",
                citation: "Kivetz, Urminsky & Zheng, 2006, Journal of Marketing Research",
                url: URL(string: "https://home.uchicago.edu/ourminsky/Goal-Gradient_Illusionary_Goal_Progress.pdf")!),
        Finding(mechanic: "After a tier", symbol: "arrow.up.forward.circle.fill",
                copy: "People slow down right after a reward. So your next tier starts with your extra miles already on it.",
                citation: "Kivetz, Urminsky & Zheng, 2006, Journal of Marketing Research",
                url: URL(string: "https://home.uchicago.edu/ourminsky/Goal-Gradient_Illusionary_Goal_Progress.pdf")!),
        Finding(mechanic: "Your streak", symbol: "flame.fill",
                copy: "A streak you can see keeps you going, and being able to repair a broken one softens the blow.",
                citation: "Silverman & Barasch, 2023, Journal of Consumer Research",
                url: URL(string: "https://academic.oup.com/jcr/article-abstract/49/6/1095/6623414")!),
        Finding(mechanic: "What we won't do", symbol: "hand.raised.fill",
                copy: "Paying people to do something they already enjoy can make them enjoy it less. So miles are a record of your studying, not a wage, and nothing you need to study is behind them.",
                citation: "Deci, Koestner & Ryan, 1999, Psychological Bulletin",
                url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/10589297")!),
    ]
    // swiftlint:enable line_length
}

struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// SFSafariViewController, for citations: the paper opens in-app and the
/// traveler lands back on the card.
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
