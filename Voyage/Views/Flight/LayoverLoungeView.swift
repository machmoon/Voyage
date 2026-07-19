import SwiftUI

/// The break between legs of a long-haul: a lounge with a countdown to
/// your connecting departure. Miss the final call and the flight is gone.
struct LayoverLoungeView: View {
    @Bindable var session: FlightSession

    private var connection: Airport { session.currentLeg.destination }
    private var nextLeg: FlightLeg { session.itinerary.legs[session.legIndex + 1] }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "2A1E10"), Color(hex: "141014")],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                loungeHeader
                    .padding(.top, 22)

                Spacer()

                countdownBlock

                Spacer()

                suggestions

                boardButton
                    .padding(.horizontal, 24)
                    .padding(.top, 26)
                    .padding(.bottom, 30)
            }
        }
    }

    private var loungeHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sofa.fill")
                Text("VOYAGE LOUNGE")
                    .kerning(3)
            }
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(Color(hex: "E8B23A"))

            Text("Welcome to \(connection.city)")
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text("Leg 1 complete — nicely done. Take a real break.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var countdownBlock: some View {
        VStack(spacing: 10) {
            if session.isFinalCall {
                Label("FINAL CALL", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .heavy))
                    .kerning(1.5)
                    .foregroundStyle(.red)
                Text(session.finalCallRemaining.clockText)
                    .font(.system(size: 64, weight: .bold, design: .monospaced))
                    .foregroundStyle(.red)
                Text("Gate closing — board now or lose the connection")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.red.opacity(0.85))
            } else {
                Text("CONNECTION DEPARTS IN")
                    .font(.caption2.weight(.semibold))
                    .kerning(1.4)
                    .foregroundStyle(.white.opacity(0.5))
                Text(session.layoverRemaining.clockText)
                    .font(.system(size: 64, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(countsDown: true))
                HStack(spacing: 6) {
                    Text(nextLeg.flightNumber)
                    Text("·")
                    Text("\(connection.code) → \(nextLeg.destination.code)")
                    Text("·")
                    Text(nextLeg.duration.shortDurationText)
                }
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
            }
        }
        .animation(.smooth, value: session.isFinalCall)
    }

    private var suggestions: some View {
        HStack(spacing: 14) {
            loungeChip("figure.walk", "Stretch")
            loungeChip("waterbottle.fill", "Hydrate")
            loungeChip("eye.fill", "Rest your eyes")
        }
    }

    private func loungeChip(_ icon: String, _ text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
            Text(text)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(.white.opacity(0.55))
        .frame(width: 92, height: 74)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var boardButton: some View {
        Button {
            Haptics.success()
            session.boardConnection()
        } label: {
            Label("Board connecting flight", systemImage: "airplane.departure")
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    session.isFinalCall ? Color.red : Color(hex: "E8B23A"),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
        }
    }
}
