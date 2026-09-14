import SwiftUI
import SwiftData

/// The recorder readout. Every card is one finding that cleared the
/// confidence gate in `FlightDataRecorder`; the screen adds no analysis of
/// its own and never editorialises on a number.
struct FlightDataRecorderView: View {
    @Query(sort: \LogbookEntry.date, order: .reverse) private var entries: [LogbookEntry]

    /// Injected in previews and snapshots; nil in the app, where the query supplies it.
    private let overrideReport: FlightDataReport?

    init(report: FlightDataReport? = nil) {
        overrideReport = report
    }

    private var report: FlightDataReport {
        overrideReport ?? FlightDataRecorder.report(entries: entries)
    }

    /// The night-sky ground the readout sits on. Shared with the offscreen
    /// renderer so a capture is the same picture the app draws.
    static var backdrop: some View {
        LinearGradient(colors: [Theme.nightSkyTop, Theme.boardingBackdrop],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }

    var body: some View {
        ScrollView {
            RecorderReadout(report: report)
        }
        .background(Self.backdrop)
        .navigationTitle("Recorder")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
    }
}

/// The readout itself, with no scroll host around it.
///
/// Split out so it can be rendered offscreen by `ImageRenderer`, which does
/// not lay out `ScrollView` content. Keeping the split here rather than in
/// the test means a capture is the real view, not a re-creation of it.
struct RecorderReadout: View {
    let report: FlightDataReport

    var body: some View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            // The navigation title already says "Recorder"; a second,
            // louder title would only repeat it.
            Text(headerSubtitle)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 2)
    }

    private var headerSubtitle: String {
        let flights = report.flightsAnalyzed
        guard flights > 0 else { return "Your logbook is empty. Stays on this phone." }
        return "From \(pluralized(flights, "flight")) in your logbook. Stays on this phone."
    }

    // MARK: States before there is anything to say

    private var recordingCard: some View {
        InstrumentCard {
            VStack(alignment: .leading, spacing: 14) {
                FieldLabel("Recording")
                    .foregroundStyle(Theme.accent)
                Text("The recorder needs \(pluralized(FlightDataRecorder.minimumFlights, "flight")) before it will report.")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(recordingBody)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)

                ProgressRail(fraction: Double(report.flightsAnalyzed) / Double(FlightDataRecorder.minimumFlights))
            }
        }
    }

    /// An empty logbook reads as a count of zero in a sentence built for a
    /// count, so it gets its own wording rather than "You have 0."
    private var recordingBody: String {
        let reason = "Until then any pattern it could draw would be as likely to come from luck as from you."
        guard report.flightsAnalyzed > 0 else {
            return "No flights recorded yet. \(reason)"
        }
        return "You have \(pluralized(report.flightsAnalyzed, "flight")), so \(report.flightsUntilReporting) to go. \(reason)"
    }

    private var nothingSeparatesCard: some View {
        InstrumentCard {
            VStack(alignment: .leading, spacing: 12) {
                FieldLabel("No findings")
                    .foregroundStyle(Theme.accent)
                Text("Nothing in these \(report.flightsAnalyzed) flights separates yet.")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Your hours, lengths, days and bags all land inside each other's margin of error. That is a result, not a gap. Keep flying and the recorder will report the moment a difference is real.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
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

struct FindingCard: View {
    let finding: Finding

    var body: some View {
        InstrumentCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(finding.headline)
                    .font(.headline)
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
            }
        }
    }

}

/// One group: its label, its point estimate, and the confidence interval
/// drawn as a band rather than hidden behind the percentage. The band is
/// the honest part. A rate of 80% from four flights is a wide smear; the
/// same rate from forty is a tick.
private struct EvidenceRow: View {
    let evidence: FindingEvidence

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The label and count columns grow with the text they hold, so the row
    /// stays aligned at every Dynamic Type size instead of clipping.
    @ScaledMetric(relativeTo: .caption2) private var labelWidth: CGFloat = 104
    @ScaledMetric(relativeTo: .caption) private var countWidth: CGFloat = 46
    @ScaledMetric(relativeTo: .caption) private var barHeight: CGFloat = 12

    private var tint: Color { evidence.isSubject ? Theme.accent : .white.opacity(0.45) }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // At accessibility sizes two fixed columns leave the bar no
                // room, so the bar takes its own full-width line underneath.
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        label
                        Spacer(minLength: 8)
                        count
                    }
                    bar
                }
            } else {
                HStack(spacing: 10) {
                    label.frame(width: labelWidth, alignment: .leading)
                    bar
                    count.frame(width: countWidth, alignment: .trailing)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(evidence.label)
        .accessibilityValue("\(evidence.countText), \(evidence.percentText)")
    }

    private var label: some View {
        Text(evidence.label)
            .font(.caption.weight(.medium))
            .foregroundStyle(evidence.isSubject ? .white : .white.opacity(0.6))
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
            .minimumScaleFactor(0.7)
    }

    private var count: some View {
        Text(evidence.countText)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(evidence.isSubject ? .white : .white.opacity(0.6))
            .lineLimit(1)
    }

    /// The honest part. The band is the 95% confidence interval; the tick is
    /// the point estimate. A rate from four flights is a wide smear, the same
    /// rate from forty is a mark, and the difference is visible without
    /// reading a single number.
    private var bar: some View {
        GeometryReader { geo in
            // Fill equals the rate, so "0 of 6" is empty and "38 of 38" is
            // full. A band-and-tick drawing read as a slider and its length
            // did not match the fraction printed beside it.
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.10))
                Capsule()
                    .fill(tint)
                    .frame(width: max(evidence.interval.rate > 0 ? 4 : 0, width * evidence.interval.rate))
            }
            .frame(height: barHeight / 2)
            .frame(maxHeight: .infinity)
        }
        .frame(height: barHeight)
    }
}

// MARK: - Shared chrome

/// The glass panel every recorder card sits on. Same `.ultraThinMaterial`
/// treatment the boarding and lounge surfaces use, so the screen reads as
/// part of the app rather than a settings pane.
///
/// The material sits on a faint white fill rather than straight on the
/// gradient. Over a near-black backdrop `.ultraThinMaterial` has almost
/// nothing to blur and the panel edge disappears; the fill gives the card a
/// body of its own and keeps it visible when the gradient is at its darkest.
private struct InstrumentCard<Content: View>: View {
    @ViewBuilder var content: Content

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 18, style: .continuous) }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(shape.fill(Color.white.opacity(0.055)))
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
