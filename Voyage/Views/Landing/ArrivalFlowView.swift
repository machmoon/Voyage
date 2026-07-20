import SwiftUI

/// The peak-end payoff after touchdown: a typographic welcome, baggage
/// claim for your checked intentions, and a passport stamp into the logbook.
struct ArrivalFlowView: View {
    @Bindable var session: FlightSession
    let onDone: () -> Void

    private enum Step {
        case welcome, baggage, stamp
    }

    @State private var step: Step = .welcome

    private var city: Airport { session.itinerary.destination }

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                WelcomeView(session: session) {
                    advance(session.intentions.isEmpty ? .stamp : .baggage)
                }
                .transition(.opacity)
            case .baggage:
                BaggageClaimView(session: session) {
                    advance(.stamp)
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .opacity))
            case .stamp:
                StampView(session: session, onDone: onDone)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .opacity))
            }
        }
    }

    private func advance(_ next: Step) {
        withAnimation(.smooth(duration: 0.5)) { step = next }
    }
}

// MARK: - Welcome

/// Full-screen typographic arrival moment in the city's accent color.
private struct WelcomeView: View {
    @Bindable var session: FlightSession
    let onContinue: () -> Void

    @State private var revealed = false

    private var city: Airport { session.itinerary.destination }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [city.accentColor, city.accentColor.opacity(0.55), Color(hex: "101018")],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Text("Welcome to")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .opacity(revealed ? 1 : 0)
                    .offset(y: revealed ? 0 : 16)

                Text(city.city)
                    .font(.system(size: 58, weight: .black))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .opacity(revealed ? 1 : 0)
                    .offset(y: revealed ? 0 : 26)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 6)

                Text(city.code)
                    .font(.system(size: 15, weight: .heavy, design: .monospaced))
                    .kerning(6)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 8)
                    .opacity(revealed ? 1 : 0)

                statsCard
                    .padding(.top, 44)
                    .opacity(revealed ? 1 : 0)
                    .offset(y: revealed ? 0 : 30)

                Spacer()

                Button(action: onContinue) {
                    Text(session.intentions.isEmpty ? "Continue to passport control" : "Head to baggage claim")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                        )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
                .opacity(revealed ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.smooth(duration: 1.0).delay(0.25)) { revealed = true }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                Haptics.success()
            }
        }
    }

    private var statsCard: some View {
        HStack(spacing: 0) {
            arrivalStat("Miles earned", "+\(Int(session.completedMiles).formatted())")
            divider
            arrivalStat("Focus time", session.itinerary.totalFocusDuration.shortDurationText)
            divider
            arrivalStat("Flight", session.itinerary.primaryFlightNumber)
        }
        .padding(.vertical, 16)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 32)
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.2))
            .frame(width: 1, height: 30)
    }

    private func arrivalStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .kerning(1.2)
                .foregroundStyle(.white.opacity(0.6))
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Baggage claim

/// Your checked intentions come around the belt — mark off what you finished.
private struct BaggageClaimView: View {
    @Bindable var session: FlightSession
    let onContinue: () -> Void

    @State private var claimed: Set<Int> = []

    var body: some View {
        ZStack {
            Color(hex: "14161C").ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.accent)
                    Text("Baggage claim")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Text("Carousel 3 · which bags made the trip?")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.top, 40)

                VStack(spacing: 12) {
                    ForEach(Array(session.intentions.enumerated()), id: \.offset) { index, intention in
                        bagCard(index: index, intention: intention)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 36)

                Spacer()

                Button(action: finish) {
                    Text("Continue to passport control")
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
    }

    private func bagCard(index: Int, intention: String) -> some View {
        let isClaimed = claimed.contains(index)
        return Button {
            Haptics.tap()
            withAnimation(.snappy(duration: 0.3)) {
                if isClaimed { claimed.remove(index) } else { claimed.insert(index) }
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "suitcase.rolling.fill")
                    .font(.title3)
                    .foregroundStyle(isClaimed ? Theme.accent : .white.opacity(0.35))
                Text(intention)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(isClaimed ? 0.95 : 0.7))
                    .strikethrough(isClaimed, color: .white.opacity(0.5))
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: isClaimed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isClaimed ? Theme.accent : .white.opacity(0.25))
            }
            .padding(16)
            .background(.white.opacity(isClaimed ? 0.1 : 0.05),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func finish() {
        if let entry = session.logEntry {
            entry.intentionsCompleted = session.intentions.indices.map { claimed.contains($0) }
        }
        onContinue()
    }
}

// MARK: - Passport stamp

/// The final thunk: a passport-style stamp slams into the logbook.
private struct StampView: View {
    @Bindable var session: FlightSession
    let onDone: () -> Void

    @State private var stamped = false

    private var city: Airport { session.itinerary.destination }

    var body: some View {
        ZStack {
            Color(hex: "1C1A16").ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text("PASSPORT CONTROL")
                        .font(.system(size: 12, weight: .heavy))
                        .kerning(3)
                        .foregroundStyle(Color(hex: "C8A951"))
                    Text("One more for the logbook")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(.top, 40)

                Spacer()

                passportPage

                Spacer()

                Button {
                    onDone()
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
                .opacity(stamped ? 1 : 0.3)
                .disabled(!stamped)
            }
        }
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                withAnimation(.spring(duration: 0.28, bounce: 0.45)) {
                    stamped = true
                }
                Haptics.stamp()
                CabinAudioEngine.shared.playThunk()
            }
        }
    }

    private var passportPage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(hex: "F4EBD6"))
                .frame(width: 300, height: 360)
                .shadow(color: .black.opacity(0.4), radius: 18, y: 10)
                .overlay(
                    VStack(spacing: 4) {
                        Text("VOYAGE PASSPORT")
                            .font(.system(size: 10, weight: .heavy))
                            .kerning(2.5)
                            .foregroundStyle(Color(hex: "8A7B57"))
                        Text("Entries & departures")
                            .font(.system(size: 9))
                            .foregroundStyle(Color(hex: "AA9C74"))
                    }
                    .padding(.top, 20),
                    alignment: .top
                )

            stamp
                .rotationEffect(.degrees(-9))
                .scaleEffect(stamped ? 1 : 2.4)
                .opacity(stamped ? 1 : 0)
        }
    }

    private var stamp: some View {
        VStack(spacing: 5) {
            Text("ADMITTED")
                .font(.system(size: 11, weight: .heavy))
                .kerning(2.5)
            Text(city.code)
                .font(.system(size: 40, weight: .black, design: .monospaced))
            Text(Date.now.formatted(date: .abbreviated, time: .omitted).uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
            Text("+\(Int(session.completedMiles).formatted()) MILES · VOYAGE AIR")
                .font(.system(size: 8, weight: .heavy))
                .kerning(1)
        }
        .foregroundStyle(city.accentColor)
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(city.accentColor, lineWidth: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(city.accentColor.opacity(0.5), lineWidth: 1.5)
                .padding(-5)
        )
        .opacity(0.85)
    }
}
