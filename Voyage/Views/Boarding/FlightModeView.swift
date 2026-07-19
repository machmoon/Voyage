import SwiftUI

/// Post-rip ritual beat: "switch your device to flight mode".
/// iOS offers no API to enable a Focus programmatically, so this walks the
/// user through it and lets them confirm — the doors close either way.
struct FlightModeView: View {
    @Bindable var session: FlightSession
    let onDepart: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.nightSkyTop, Theme.nightSkyBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Image(systemName: "airplane.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, options: .repeating)
                    .padding(.bottom, 28)

                Text("Cabin crew,\narm doors.")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Please switch your device to flight mode.\nTurn on a Focus so nothing interrupts this flight.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
                    .padding(.horizontal, 36)

                focusHint
                    .padding(.top, 28)

                Spacer()

                Button {
                    Haptics.gearThunk()
                    onDepart()
                } label: {
                    Label("Ready for departure", systemImage: "airplane.departure")
                        .font(.headline)
                        .foregroundStyle(Theme.nightSkyTop)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 18)
        }
        .onAppear {
            withAnimation(.smooth(duration: 0.8)) { appeared = true }
        }
    }

    private var focusHint: some View {
        HStack(spacing: 12) {
            Image(systemName: "moon.fill")
                .font(.title3)
                .foregroundStyle(.indigo)
            VStack(alignment: .leading, spacing: 2) {
                Text("Enable a Focus")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Swipe down from the top-right, long-press Focus, choose Do Not Disturb.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 24)
    }
}
