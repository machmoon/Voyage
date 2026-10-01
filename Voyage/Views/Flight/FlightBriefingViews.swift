import SwiftUI

/// The captain's note at the top of cruise, written on this iPhone.
///
/// Drawn as the cabin service card's sibling (`CabinServiceCard`): a card in
/// the layout, never a sheet or alert, up for 90 seconds and then gone. It is
/// text, not audio. The PA is recorded studio clips (`Announcer`), and a
/// generated sentence would need a synthetic voice that sounds nothing like
/// the recorded crew, so the recorded lines play exactly as before and this
/// sits under the clock.
struct CaptainNoteCard: View {
    let line: String
    let onDismiss: () -> Void

    @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "airplane")
                    .font(.system(size: iconSize, weight: .regular))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text("FROM THE CAPTAIN")
                    .font(.system(.caption2, design: .default, weight: .bold))
                    .kerning(1.4)
                    .foregroundStyle(.white.opacity(0.45))
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(.caption, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(6)
                }
                .accessibilityLabel("Dismiss")
            }

            Text(line)
                .font(.system(.headline, design: .default, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)

            OnDeviceCaption()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal, 28)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("captain-note-card")
    }
}

/// The small print under anything the model wrote.
struct OnDeviceCaption: View {
    var body: some View {
        Label("Written on this iPhone by Apple Intelligence", systemImage: "lock.fill")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.white.opacity(0.4))
            .labelStyle(.titleAndIcon)
    }
}

/// Takes the place of the purpose line under the clock once a plan exists: the
/// step you should be on now and how long it has left.
struct FlightPlanStrip: View {
    let plan: FlightPlan
    let bags: [String]
    /// Minutes into cruise; negative before the top of climb.
    let cruiseMinute: Double
    let onOpen: () -> Void

    private var step: FlightPlan.Step? { plan.step(atCruiseMinute: cruiseMinute) }

    private var leftText: String? {
        guard let step, cruiseMinute >= 0 else { return nil }
        let left = max(0, Double(step.endMinute) - cruiseMinute)
        return "\(TimeInterval(left * 60).shortDurationText) left"
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                Text(cruiseMinute < 0 ? "FIRST UP" : "NOW")
                    .font(.system(size: 9, weight: .heavy))
                    .kerning(1.2)
                    .foregroundStyle(Theme.accent)
                Text(step?.action ?? "")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Spacer(minLength: 6)
                if let leftText {
                    Text(leftText)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.white.opacity(0.06), in: Capsule())
            .padding(.horizontal, 24)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Shows the whole flight plan")
        .accessibilityIdentifier("flight-plan-strip")
    }

    private var accessibilityText: String {
        let lead = cruiseMinute < 0 ? "Flight plan. First up" : "Flight plan. Now"
        return [lead + ": " + (step?.action ?? ""), leftText].compactMap { $0 }.joined(separator: ". ")
    }
}

/// Every step with its minutes, grouped under nothing: a list in flight order.
struct FlightPlanSheet: View {
    let plan: FlightPlan
    let bags: [String]
    let cruiseMinute: Double
    let destinationCity: String

    @Environment(\.dismiss) private var dismiss

    private var current: FlightPlan.Step? {
        cruiseMinute < 0 ? nil : plan.step(atCruiseMinute: cruiseMinute)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Your purpose, split into steps that fit the \(TimeInterval(plan.totalMinutes * 60).shortDurationText) of cruise to \(destinationCity). Minutes count from the top of climb.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 0) {
                        ForEach(plan.steps) { step in
                            row(step)
                            if step.index != plan.steps.last?.index {
                                Divider().overlay(.white.opacity(0.08))
                            }
                        }
                    }
                    .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    OnDeviceCaption()
                    Text("Your purpose stays on this iPhone. Turn this off in Settings under Apple Intelligence.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
            .background(Theme.surfaceDark.ignoresSafeArea())
            .navigationTitle("Flight plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("flight-plan-sheet")
    }

    private func row(_ step: FlightPlan.Step) -> some View {
        let isCurrent = step.index == current?.index
        return HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(String(format: "%02d", step.index + 1))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(isCurrent ? Theme.accent : .white.opacity(0.4))
                .frame(width: 22, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(step.action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if bags.indices.contains(step.bag), bags[step.bag] != step.action {
                    Text(bags[step.bag])
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text("\(step.minutes)m")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(isCurrent ? Theme.accent.opacity(0.12) : .clear)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(step.index + 1): \(step.action), \(step.minutes) minutes\(isCurrent ? ", now" : "")")
    }
}
