import SwiftUI

/// Strict-mode fail state: the flight was diverted (left the app too long)
/// or the connection was missed in the lounge. Deliberately plain.
struct DivertedView: View {
    enum Kind {
        case diverted
        case missedConnection
    }

    @Bindable var session: FlightSession
    let kind: Kind
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color(hex: "17181C").ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Image(systemName: kind == .diverted ? "airplane.arrival" : "clock.badge.xmark")
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.bottom, 24)

                Text(kind == .diverted ? "Flight diverted" : "Connection missed")
                    .font(.title.bold())
                    .foregroundStyle(.white)

                Text(kind == .diverted
                     ? "You were away from the cabin too long, so we had to put her down early."
                     : "The gate closed before you boarded. Your connection left without you.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                    .padding(.horizontal, 44)

                statsRow
                    .padding(.top, 32)

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Text("Back to the terminal")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
        }
        .onAppear { Haptics.failure() }
    }

    private var statsRow: some View {
        HStack(spacing: 28) {
            stat("Logged", "Incomplete")
            stat("Focus time", (session.logEntry?.focusSeconds ?? 0).shortDurationText)
            stat("Miles earned", "\(Int(session.completedMiles).formatted())")
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .kerning(1.4)
                .foregroundStyle(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}
