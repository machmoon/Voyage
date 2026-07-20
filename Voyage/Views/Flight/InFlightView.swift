import SwiftUI

/// The study screen. Two views of the same flight: the airplane window,
/// or a live flight-tracker map of the route. Opens with a cabin-lights
/// departure curtain instead of a hard cut from the boarding flow.
struct InFlightView: View {
    @Bindable var session: FlightSession

    enum StudyView: String, CaseIterable {
        case window = "Window"
        case map = "Map"
    }

    @State private var studyView: StudyView = .window
    @State private var showInfoPill = true
    @State private var showExitConfirm = false
    @State private var settings = SettingsStore.shared
    /// Cabin-lights curtain shown while the stage transition settles —
    /// doubles as the polish moment and as cover for arming the Canvas.
    @State private var curtainVisible = true
    @State private var windowSceneArmed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isNight: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 19 || hour < 6
    }

    /// Subtle nose-up pitch while punching through the cloud deck.
    private var climbWindowPitch: Double {
        guard !reduceMotion, session.phase == .climb, studyView == .window else { return 0 }
        let climbSpan = max(0.001, FlightSession.climbEndsAt - FlightSession.takeoffRollDuration)
        let intoClimb = max(0, session.legElapsed - FlightSession.takeoffRollDuration)
        let t = min(1, intoClimb / climbSpan)
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

                Spacer(minLength: 14)

                studyContent

                Spacer(minLength: 18)

                countdown

                if showInfoPill {
                    flightInfoPill
                        .padding(.top, 20)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }

                if !session.intentions.isEmpty {
                    intentionsStrip
                        .padding(.top, 16)
                }

                Spacer(minLength: 24)
            }

            departureCurtain
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
            // Let RootView finish the stage swap behind the curtain,
            // then arm the Canvas and raise the lights. QA short flights
            // compress the moment so the 3s takeoff roll isn't missed.
            let quick = reduceMotion || FlightSession.shortFlightsEnabled
            await Task.yield()
            windowSceneArmed = true
            try? await Task.sleep(for: .milliseconds(quick ? 250 : 1400))
            withAnimation(.smooth(duration: quick ? 0.3 : 1.3)) {
                curtainVisible = false
            }
        }
    }

    // MARK: Departure curtain

    @ViewBuilder
    private var departureCurtain: some View {
        if curtainVisible {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 10) {
                    Image(systemName: "airplane")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Text("\(session.currentLeg.origin.code) → \(session.currentLeg.destination.code)")
                        .font(.system(size: 15, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("Cabin lights dimmed for departure")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .transition(.opacity)
            .zIndex(10)
            .accessibilityHidden(true)
        }
    }

    // MARK: Top bar

    private var cabinSoundOn: Bool {
        settings.ambienceEnabled || settings.announcementsEnabled
    }

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
            viewSwitcher
            Spacer()
            HStack(spacing: 8) {
                // One switch for all cabin sound: ambience bed and PA together.
                cabinToggle(
                    icon: cabinSoundOn ? "speaker.wave.2.fill" : "speaker.slash.fill"
                ) {
                    let on = !cabinSoundOn
                    settings.ambienceEnabled = on
                    settings.announcementsEnabled = on
                    if on {
                        CabinAudioEngine.shared.startAmbience(profile: session.ambienceProfile)
                    } else {
                        Announcer.shared.stop()
                        CabinAudioEngine.shared.stopAmbience()
                    }
                }
                cabinToggle(icon: "rectangle.portrait.and.arrow.right") {
                    showExitConfirm = true
                }
            }
        }
    }

    private var viewSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(StudyView.allCases, id: \.self) { view in
                let isOn = studyView == view
                Button {
                    Haptics.tap()
                    withAnimation(.smooth(duration: 0.35)) { studyView = view }
                } label: {
                    Label(view.rawValue,
                          systemImage: view == .window ? "airplane" : "map")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isOn ? .black : .white.opacity(0.6))
                        .frame(width: 40, height: 26)
                        .background(isOn ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(.clear),
                                    in: Capsule())
                }
                .accessibilityLabel("\(view.rawValue) view")
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(3)
        .background(.white.opacity(0.08), in: Capsule())
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

    // MARK: Study content

    @ViewBuilder
    private var studyContent: some View {
        switch studyView {
        case .window:
            airplaneWindow
                .padding(.horizontal, 44)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        case .map:
            mapCard
                .padding(.horizontal, 20)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    private var airplaneWindow: some View {
        let shape = RoundedRectangle(cornerRadius: 110, style: .continuous)
        return Group {
            if windowSceneArmed {
                WindowSceneView(
                    phase: session.phase,
                    altitudeFraction: Double(session.altitudeFeet) / 36_000.0,
                    isNight: isNight,
                    condition: session.windowCondition,
                    showSunset: session.hasSunsetScene,
                    showAurora: session.hasAuroraScene,
                    showWing: session.hasWingView
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

    private var mapCard: some View {
        FlightMapView(session: session)
            .aspectRatio(0.78, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 20, y: 8)
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

            // The countdown is tappable — say so.
            Image(systemName: showInfoPill ? "chevron.compact.up" : "chevron.compact.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.top, 2)
                .accessibilityHidden(true)

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
        ScrollView(.horizontal, showsIndicators: false) {
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
}
