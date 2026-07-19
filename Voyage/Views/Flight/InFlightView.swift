import SwiftUI

/// The study screen: an airplane window onto the animated scene,
/// the countdown, and a toggleable flight-info pill.
struct InFlightView: View {
    @Bindable var session: FlightSession

    @State private var showInfoPill = true
    @State private var showExitConfirm = false
    @State private var settings = SettingsStore.shared
    /// Defer the TimelineView/Canvas window one run-loop after the
    /// preflight → inFlight transition so heavy drawing doesn't race the stage swap.
    @State private var windowSceneArmed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isNight: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 19 || hour < 6
    }

    /// Subtle nose-up pitch while punching through the cloud deck.
    private var climbWindowPitch: Double {
        guard !reduceMotion, session.phase == .climb else { return 0 }
        let climbSpan = max(0.001, FlightSession.climbEndsAt - FlightSession.takeoffRollDuration)
        let intoClimb = max(0, session.legElapsed - FlightSession.takeoffRollDuration)
        let t = min(1, intoClimb / climbSpan)
        // Peak right after rotation, ease toward level by cruise.
        return -5.5 * (1.0 - t * 0.75)
    }

    /// Red-eye flights dim the whole cabin, and the crew dims the lights
    /// again for approach and landing.
    private var cabinColor: Color {
        let dimmedForLanding = session.phase >= .descent
        if isNight {
            return Color(hex: dimmedForLanding ? "060508" : "0B0910")
        }
        return Color(hex: dimmedForLanding ? "10131D" : "1A1E2A")
    }

    var body: some View {
        ZStack {
            cabinColor
                .ignoresSafeArea()
                .animation(.smooth(duration: 2.5), value: session.phase)

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 6)

                Spacer(minLength: 16)

                airplaneWindow
                    .padding(.horizontal, 44)

                Spacer(minLength: 20)

                countdown

                if showInfoPill {
                    flightInfoPill
                        .padding(.top, 22)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }

                if !session.intentions.isEmpty {
                    intentionsStrip
                        .padding(.top, 18)
                }

                Spacer(minLength: 26)
            }
        }
        .statusBarHidden()
        .confirmationDialog("Leave this flight?", isPresented: $showExitConfirm, titleVisibility: .visible) {
            Button("Divert flight (session lost)", role: .destructive) {
                session.abandonFlight()
            }
            Button("Keep flying", role: .cancel) {}
        } message: {
            Text("Diverting ends the session. Miles are only earned for completed legs.")
        }
        .task {
            // Yield one frame so RootView can finish the stage transition first.
            await Task.yield()
            windowSceneArmed = true
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            if session.itinerary.isConnection {
                Text("LEG \(session.legIndex + 1) OF \(session.itinerary.legs.count)")
                    .font(.system(size: 10, weight: .heavy))
                    .kerning(1.5)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.08), in: Capsule())
            }
            Spacer()
            HStack(spacing: 8) {
                cabinToggle(
                    icon: settings.ambienceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill"
                ) {
                    settings.ambienceEnabled.toggle()
                    if settings.ambienceEnabled {
                        CabinAudioEngine.shared.startAmbience(profile: session.ambienceProfile)
                    } else {
                        CabinAudioEngine.shared.stopAmbience()
                    }
                }
                cabinToggle(icon: "rectangle.portrait.and.arrow.right") {
                    showExitConfirm = true
                }
            }
        }
    }

    private func cabinToggle(icon: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.07), in: Circle())
        }
    }

    // MARK: Window

    private var airplaneWindow: some View {
        let shape = RoundedRectangle(cornerRadius: 110, style: .continuous)
        return Group {
            if windowSceneArmed {
                WindowSceneView(
                    phase: session.phase,
                    altitudeFraction: Double(session.altitudeFeet) / 36_000.0,
                    isNight: isNight,
                    condition: session.destinationCondition,
                    showSunset: session.hasSunsetScene,
                    showAurora: session.hasAuroraScene
                )
            } else {
                Color(hex: isNight ? "0B0910" : "1A1E2A")
            }
        }
        .aspectRatio(0.72, contentMode: .fit)
        .clipShape(shape)
        .overlay(
            // Inner pane reflection.
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.25), .clear, .white.opacity(0.08)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 2
            )
        )
        .padding(14)
        .background(
            // Cabin wall window frame.
            RoundedRectangle(cornerRadius: 122, style: .continuous)
                .fill(
                    LinearGradient(colors: [Color(hex: isNight ? "241F2E" : "3A4256"),
                                            Color(hex: isNight ? "141019" : "232838")],
                                   startPoint: .top, endPoint: .bottom)
                )
                .shadow(color: .black.opacity(0.55), radius: 24, y: 10)
        )
        .rotation3DEffect(
            .degrees(climbWindowPitch),
            axis: (x: 1, y: 0, z: 0),
            anchor: .center,
            perspective: 0.45
        )
        .animation(reduceMotion ? nil : .easeInOut(duration: 1.2), value: session.phase)
    }

    // MARK: Countdown

    private var countdown: some View {
        VStack(spacing: 6) {
            Text(session.legRemaining.clockText)
                .font(.system(size: 56, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .contentTransition(.numericText(countsDown: true))
                .animation(.linear(duration: 0.4), value: session.legRemaining.clockText)

            Text("to \(session.currentLeg.destination.city)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.6))

            Text(phaseCaption)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))

            if session.legIndex == 0, let via = session.itinerary.connection {
                Text("\(session.totalRemaining.shortDurationText) total · lounge break at \(via.code)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.top, 2)
            }
        }
        .onTapGesture {
            Haptics.tap()
            withAnimation(.snappy) { showInfoPill.toggle() }
        }
    }

    private var phaseCaption: String {
        switch session.phase {
        case .takeoffRoll: return "Cleared for takeoff"
        case .climb: return "Climbing through the cloud deck"
        case .cruise: return "Cruising · seatbelt sign off · deep work"
        case .descent: return "Descending · finish your final items"
        case .landing: return "Landing"
        }
    }

    // MARK: Flight-info pill

    private var flightInfoPill: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text(session.currentLeg.origin.code)
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.18))
                            .frame(height: 2)
                            .frame(maxHeight: .infinity)
                        Capsule()
                            .fill(.white.opacity(0.8))
                            .frame(width: max(2, geo.size.width * session.legProgress), height: 2)
                            .frame(maxHeight: .infinity)
                        Image(systemName: "airplane")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(x: max(0, geo.size.width * session.legProgress - 7))
                    }
                }
                .frame(height: 16)
                Text(session.currentLeg.destination.code)
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
            }
            .foregroundStyle(.white.opacity(0.85))

            HStack(spacing: 22) {
                pillStat("Altitude", "\(session.altitudeFeet.formatted()) ft")
                pillStat("Ground speed", "\(session.groundSpeedMph) mph")
                pillStat("Flight", session.currentLeg.flightNumber)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 36)
    }

    private func pillStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .kerning(1)
                .foregroundStyle(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    // MARK: Intentions

    private var intentionsStrip: some View {
        HStack(spacing: 8) {
            ForEach(session.intentions, id: \.self) { intention in
                HStack(spacing: 5) {
                    Image(systemName: "suitcase.fill")
                        .font(.system(size: 8))
                    Text(intention)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.06), in: Capsule())
            }
        }
        .padding(.horizontal, 24)
    }
}
