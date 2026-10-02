import SwiftUI

/// The first card on Home's departure row: a 25-minute focus flight with no
/// destination. Same glass, size and type rhythm as the route cards beside it
/// (`HomeView.destinationCard`), tinted blue so it reads as a different kind of
/// flight rather than one more city. One tap departs; there is nothing to pick.
struct OpenSkiesCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Open skies")
                        .font(.system(size: 18, weight: .heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 11, weight: .bold))
                        .opacity(0.8)
                }
                Text("No destination")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.system(size: 8, weight: .bold))
                    Text("\(OpenSkiesFlight.duration.shortDurationText) focus")
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .opacity(0.75)
            }
            .padding(12)
            .frame(width: 132, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(LinearGradient(colors: [Color(hex: "6F93E8"), Color(hex: "4D67B4")],
                                                 startPoint: .top, endPoint: .bottom))
                            .opacity(0.72)
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(hex: "AFC8FF").opacity(0.6), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        // Not "destination-…": the UI tours pick the first card with that
        // prefix to book a route, and this card books none.
        .accessibilityIdentifier("open-skies")
        .accessibilityLabel("Open skies. No destination, \(OpenSkiesFlight.duration.shortDurationText) focus flight")
        .accessibilityHint("Departs now")
    }
}
