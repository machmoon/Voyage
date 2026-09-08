import SwiftUI
import SwiftData

/// The recorder readout. Every card is one finding that cleared the
/// confidence gate in `FlightDataRecorder`; the screen adds no analysis of
/// its own and never editorialises on a number.
struct FlightDataRecorderView: View {
    @Query(sort: \LogbookEntry.date, order: .reverse) private var entries: [LogbookEntry]

    /// Injected in previews and tests; nil in the app, where the query supplies it.
    private let overrideReport: FlightDataReport?

    init(report: FlightDataReport? = nil) {
        overrideReport = report
    }

    private var report: FlightDataReport {
        overrideReport ?? FlightDataRecorder.report(entries: entries)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if report.isReporting {
                    if report.findings.isEmpty {
                        nothingSeparatesCard
                    } else {
                        ForEach(report.findings) { finding in
                            FindingCard(finding: finding)
                        }
                    }
                } else {
                    recordingCard
                }

                methodNote
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(
            LinearGradient(colors: [Theme.nightSkyTop, Theme.boardingBackdrop],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .navigationTitle("Recorder")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FLIGHT DATA RECORDER")
                .font(.system(size: 20, weight: .black))
                .kerning(2.6)
                .foregroundStyle(.white)
            Text(headerSubtitle)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 2)
    }

    private var headerSubtitle: String {
        let flights = report.flightsAnalyzed
        let noun = flights == 1 ? "flight" : "flights"
        return "Reading \(flights) recorded \(noun) from your logbook. Nothing leaves this device."
    }

    // MARK: States before there is anything to say

    private var recordingCard: some View {
        InstrumentCard {
            VStack(alignment: .leading, spacing: 14) {
                FieldLabel("Recording")
                    .foregroundStyle(Theme.accent)
                Text("The recorder needs \(FlightDataRecorder.minimumFlights) flights before it will report.")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("You have \(report.flightsAnalyzed). \(report.flightsUntilReporting) to go. Until then any pattern it could draw would be as likely to come from luck as from you.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))

                ProgressRail(fraction: Double(report.flightsAnalyzed) / Double(FlightDataRecorder.minimumFlights))
            }
        }
    }

    private var nothingSeparatesCard: some View {
        InstrumentCard {
            VStack(alignment: .leading, spacing: 12) {
                FieldLabel("No findings")
                    .foregroundStyle(Theme.accent)
                Text("Nothing in these \(report.flightsAnalyzed) flights separates yet.")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Your hours, lengths, days and bags all land inside each other's margin of error. That is a result, not a gap. Keep flying and the recorder will report the moment a difference is real.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))
            }
        }
    }

    // MARK: Method

    private var methodNote: some View {
        VStack(alignment: .leading, spacing: 7) {
            FieldLabel("Method")
                .foregroundStyle(.white.opacity(0.45))
            Text("The recorder compares two groups at a time and reports a difference only when the 95 percent confidence intervals around them do not overlap, with at least \(FlightDataRecorder.minimumGroup) flights on each side. Everything that fails that test stays off this screen, including the things you might want to hear.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }
}

// MARK: - Finding card

private struct FindingCard: View {
    let finding: Finding

    var body: some View {
        InstrumentCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 8) {
                    FieldLabel(finding.kind.label)
                        .foregroundStyle(Theme.accent)
                    if finding.mode == .informative {
                        Text("INFORMATIONAL")
                            .font(.system(size: 8, weight: .heavy))
                            .kerning(1)
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1))
                    }
                    Spacer(minLength: 0)
                }

                Text(finding.headline)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text(finding.detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 9) {
                    ForEach(finding.evidence) { row in
                        EvidenceRow(evidence: row)
                    }
                }
                .padding(.top, 2)

                HStack {
                    Text(scaleCaption)
                    Spacer()
                    Text("\(finding.support) flights")
                }
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.38))
            }
        }
    }

    private var scaleCaption: String {
        finding.mode == .informative ? "SHARE  0% TO 100%" : "ARRIVAL RATE  0% TO 100%"
    }
}

/// One group: its label, its point estimate, and the confidence interval
/// drawn as a band rather than hidden behind the percentage. The band is
/// the honest part. A rate of 80% from four flights is a wide smear; the
/// same rate from forty is a tick.
private struct EvidenceRow: View {
    let evidence: FindingEvidence

    private var tint: Color { evidence.isSubject ? Theme.accent : .white.opacity(0.45) }

    var body: some View {
        HStack(spacing: 10) {
            Text(evidence.label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .kerning(0.4)
                .foregroundStyle(evidence.isSubject ? .white : .white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 104, alignment: .leading)

            GeometryReader { geo in
                let width = geo.size.width
                let lower = evidence.interval.lower
                let upper = evidence.interval.upper
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.10))
                        .frame(height: 6)
                    Capsule()
                        .fill(tint.opacity(0.30))
                        .frame(width: max(2, width * (upper - lower)), height: 6)
                        .offset(x: width * lower)
                    Capsule()
                        .fill(tint)
                        .frame(width: 2.5, height: 12)
                        .offset(x: min(width - 2.5, width * evidence.interval.rate))
                }
                .frame(height: 12)
                .frame(maxHeight: .infinity)
            }
            .frame(height: 12)

            Text(evidence.countText)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(evidence.isSubject ? .white : .white.opacity(0.6))
                .frame(width: 46, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(evidence.label)
        .accessibilityValue("\(evidence.countText), \(evidence.percentText)")
    }
}

// MARK: - Shared chrome

/// The glass panel every recorder card sits on. Same `.ultraThinMaterial`
/// treatment the boarding and lounge surfaces use, so the screen reads as
/// part of the app rather than a settings pane.
private struct InstrumentCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(.ultraThinMaterial.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            )
    }
}

private struct ProgressRail: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.14))
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 5)
    }
}
