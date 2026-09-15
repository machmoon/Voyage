import SwiftUI
import UIKit

/// The coach under the recorder's findings: a plan for the next flight, the
/// study methods to pack into it, and the logbook ready to paste into a chat
/// app the traveler already uses.
///
/// There is no on-device model here on purpose. Apple's Foundation Models note
/// was tried on the demo logbook (September 15, 2026): it restated the
/// recorder's cards, advised "Leave the app on your next flight", and cited
/// counts the logbook does not hold. The recorder only shows what clears a
/// 95% test, so a generated paragraph beside it would be the least reliable
/// thing on the screen. The export hands the same data to a larger model the
/// traveler chooses, and they see the text first.
struct StudyCoachSection: View {
    let entries: [LogbookEntry]
    let report: FlightDataReport

    @State private var logText = ""
    @State private var copied = false
    @State private var showsAllMethods = false

    private struct LogbookKey: Equatable {
        let count: Int
        let lastDate: Date?
    }

    private var key: LogbookKey {
        LogbookKey(count: entries.count, lastDate: entries.map(\.date).max())
    }

    private var plan: StudyCoach.Plan {
        StudyCoach.plan(flights: entries.map(RecordedFlight.init(entry:)), report: report)
    }

    private var methods: [StudyCoach.Method] {
        let all = StudyCoach.methods(report: report)
        return showsAllMethods ? all : Array(all.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Study coach")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.top, 8)

            planCard
            methodsCard
            // The export reads the logbook; with nothing in it it would only
            // restate zeros, so it waits for the first flight.
            if !entries.isEmpty {
                askAnAICard
            }
        }
        .task(id: key) {
            logText = LogbookExport.markdown(entries: entries, now: .now)
        }
    }

    // MARK: Plan

    private var planCard: some View {
        InstrumentCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(plan.headline)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(plan.detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("coach-plan")
    }

    // MARK: Methods

    private var methodsCard: some View {
        InstrumentCard {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(methods) { method in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(method.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(method.body)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.68))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }

                Button {
                    withAnimation(.smooth(duration: 0.3)) { showsAllMethods.toggle() }
                } label: {
                    Text(showsAllMethods ? "Show fewer" : "More methods")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                .accessibilityIdentifier("coach-more-methods")
            }
        }
    }

    // MARK: Ask an AI

    private var askAnAICard: some View {
        InstrumentCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Ask an AI about your flights")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Copy your logbook with a coaching prompt, then paste it into ChatGPT, Claude or Gemini. You see the text before it leaves this phone.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button {
                        UIPasteboard.general.string = logText
                        Haptics.success()
                        copied = true
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .coachButtonLabel(prominent: true)
                    }
                    .accessibilityIdentifier("coach-copy-logbook")

                    ShareLink(item: logText, subject: Text("Voyage logbook"),
                              preview: SharePreview("Voyage logbook")) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .coachButtonLabel(prominent: false)
                    }
                    .accessibilityIdentifier("coach-share-logbook")
                }
                .disabled(logText.isEmpty)
            }
        }
    }
}

private extension View {
    func coachButtonLabel(prominent: Bool) -> some View {
        self
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(minHeight: 40)
            .background(prominent ? Theme.accent : Color.white.opacity(0.12), in: Capsule())
    }
}
