import SwiftUI

/// The wellness cue, drawn as a cabin event rather than a reminder.
///
/// It is a card in the layout, not a sheet, alert or full-screen cover. That
/// is the whole design: a modal would stop the study session to protect the
/// study session. This appears under the countdown, sits there for 90 seconds,
/// and leaves. Ignoring it costs nothing and is not recorded as a failure.
struct CabinServiceCard: View {

    let pass: CabinServicePlanner.Pass
    let onAcknowledge: () -> Void
    let onDismiss: () -> Void

    @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: pass.systemImage)
                    .font(.system(size: iconSize, weight: .regular))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text(pass.eyebrow)
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

            Text(pass.headline)
                .font(.system(.headline, design: .default, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))

            Text(pass.detail)
                .font(.system(.subheadline))
                .foregroundStyle(.white.opacity(0.6))

            Button(action: onAcknowledge) {
                Text(pass.action)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(Theme.accent, in: Capsule())
            }
            .padding(.top, 2)
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
        // `.contain` and no container label: VoiceOver reads the eyebrow,
        // headline, detail and button in order, and each stays queryable.
        // A label on the container would collapse the children out of the
        // accessibility tree, which also makes them invisible to UI tests.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cabin-service-card")
    }
}
