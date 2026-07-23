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
    @State private var showInfoPill = false
    @State private var showExitConfirm = false
    @State private var settings = SettingsStore.shared
    @State private var windowSceneArmed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Study-map warm-up
    //
    // SwiftUI's `Map` reports no rendered-frame callback, so the map card is
    // warmed ahead of first use rather than gated on a signal that never comes.
    @State private var inFlightSince: Date?
    @State private var mapMountedAt: Date?
    @State private var mapLeftAt: Date?
    @State private var hasOpenedMap = false
    @State private var mapIsMounted = false
    @State private var showsMapCover = true

    private var shortFlights: Bool { FlightSession.shortFlightsEnabled }

    /// Re-evaluates the pure warm-up policy against the wall clock.
    private func refreshMapWarmup() {
        let now = Date()
        let shouldMount = StudyMapWarmup.shouldMountMap(
            isShowingMap: studyView == .map,
            hasOpenedMap: hasOpenedMap,
            secondsSinceInFlightBegan: inFlightSince.map { now.timeIntervalSince($0) },
            secondsSinceLeftMap: mapLeftAt.map { now.timeIntervalSince($0) },
            warmingIsUseful: StudyMapWarmup.warmingIsUseful(
                streamedSceneryAllowed: WorldSceneryConfiguration.streamedSceneryAllowedByProcess,
                isOnline: WorldSceneryAvailability.shared.isOnline
            ),
            shortFlights: shortFlights
        )

        if shouldMount != mapIsMounted {
            mapIsMounted = shouldMount
            mapMountedAt = shouldMount ? now : nil
        }

        showsMapCover = StudyMapWarmup.showsFirstPaintCover(
            secondsMounted: mapMountedAt.map { now.timeIntervalSince($0) }
        )
    }

    private var sceneAirport: Airport {
        session.phase >= .descent ? session.currentLeg.destination : session.currentLeg.origin
    }

    private var isNight: Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = sceneAirport.timeZone
        let hour = calendar.component(.hour, from: Date())
        return hour >= 19 || hour < 6
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
                Spacer(minLength: 14)

                studyContent

                Spacer(minLength: 18)

                countdown

                if session.beverageCartUntil != nil {
                    beverageCartCard
                        .padding(.top, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

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
            .animation(.snappy(duration: 0.4), value: session.beverageCartUntil)

            // Keep controls above the window shade gesture layer — the shade
            // GeometryReader can extend past the clipped pane and steal taps.
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                Spacer(minLength: 0)
            }
            .zIndex(2)
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
            // Departure curtain already played during boarding. Fade the window
            // scene in and let it play — no interactive shade to fight with.
            let quick = reduceMotion || FlightSession.shortFlightsEnabled
            try? await Task.sleep(for: .milliseconds(quick ? 80 : 160))
            if reduceMotion {
                windowSceneArmed = true
            } else {
                withAnimation(.smooth(duration: quick ? 0.4 : 1.1)) {
                    windowSceneArmed = true
                }
            }
        }
        .task {
            // Drives the map warm-up policy. Cheap: a boolean re-evaluation a
            // few times a second, and it stops with the view.
            inFlightSince = Date()
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.3)) { refreshMapWarmup() }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    // MARK: Top bar

    private var cabinSoundOn: Bool {
        settings.ambienceEnabled || settings.soundEffectsEnabled
    }

    private var topBar: some View {
        HStack(spacing: 2) {
            if session.itinerary.isConnection {
                Text("LEG \(session.legIndex + 1)/\(session.itinerary.legs.count)")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .kerning(0.8)
                    .foregroundStyle(.white.opacity(0.58))
                    .padding(.horizontal, 9)
                    .frame(height: 36)

                toolbarDivider
            }

            ForEach(StudyView.allCases, id: \.self) { view in
                studyViewButton(view)
            }

            toolbarDivider

            // A quick cabin-sound control. Spoken check-ins stay opt-in and
            // are never silently enabled by this button.
            Button {
                Haptics.tap()
                let on = !cabinSoundOn
                settings.ambienceEnabled = on
                settings.soundEffectsEnabled = on
                if !on {
                    CabinAudioEngine.shared.stopAmbience()
                } else {
                    CabinAudioEngine.shared.startAmbience(profile: session.ambienceProfile)
                }
            } label: {
                Image(systemName: cabinSoundOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(cabinSoundOn ? .white.opacity(0.8) : .white.opacity(0.48))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(cabinSoundOn ? "Mute cabin sounds" : "Unmute cabin sounds")

            Button {
                Haptics.tap()
                showExitConfirm = true
            } label: {
                Label("Exit", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.horizontal, 9)
                    .frame(height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Leave flight")
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
        .frame(maxWidth: .infinity)
    }

    private func studyViewButton(_ view: StudyView) -> some View {
        let isOn = studyView == view
        return Button {
            Haptics.tap()
            selectStudyView(view)
        } label: {
            Label(view.rawValue, systemImage: view == .window ? "airplane" : "map")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(isOn ? .black : .white.opacity(0.62))
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(isOn ? AnyShapeStyle(.white.opacity(0.94)) : AnyShapeStyle(.clear),
                            in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(view.rawValue) view")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// Switching study views. The map is placed in the hierarchy *before* the
    /// crossfade starts, so the fade always lands on a real card — warm tiles
    /// if it was pre-warmed, the calm cover if it is genuinely cold — and never
    /// on an empty slot or a bare MapKit placeholder.
    private func selectStudyView(_ view: StudyView) {
        guard view != studyView else { return }

        if view == .map {
            hasOpenedMap = true
            mapLeftAt = nil
            if !mapIsMounted {
                mapIsMounted = true
                mapMountedAt = Date()
                showsMapCover = true
            }
        } else if studyView == .map {
            mapLeftAt = Date()
        }

        withAnimation(.smooth(duration: 0.35)) { studyView = view }
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.12))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 3)
            .accessibilityHidden(true)
    }

    // MARK: Study content

    /// Both study views share one stable slot. The map keeps its identity
    /// across warm-hidden and visible states — remounting it on every switch is
    /// exactly what made it cold-start into a placeholder.
    private var studyContent: some View {
        ZStack {
            // Reserves the taller of the two cards for the whole flight, so
            // mounting the hidden map can never shift the countdown beneath it.
            Color.clear
                .aspectRatio(0.78, contentMode: .fit)
                .padding(.horizontal, 20)
                .accessibilityHidden(true)

            airplaneWindow
                .padding(.horizontal, 44)
                .opacity(studyView == .window ? 1 : 0)
                .scaleEffect(studyView == .window ? 1 : 0.98)
                .allowsHitTesting(studyView == .window)
                .accessibilityHidden(studyView != .window)

            if mapIsMounted {
                mapCard
                    .padding(.horizontal, 20)
                    .opacity(studyView == .map ? 1 : 0)
                    .scaleEffect(studyView == .map ? 1 : 0.98)
                    .allowsHitTesting(studyView == .map)
                    .accessibilityHidden(studyView != .map)
            }
        }
    }

    private var airplaneWindow: some View {
        let shape = RoundedRectangle(cornerRadius: 110, style: .continuous)
        return ZStack {
            // The scene just plays. It never takes touches, so pulling or
            // tapping the pane can't glitch it — the study screen stays calm.
            if windowSceneArmed, let trajectory = session.currentTrajectory {
                WindowSceneView(
                    context: FlightVisualContext(
                        trajectory: trajectory,
                        seat: session.seat,
                        isNight: isNight,
                        showsWing: false,
                        showsSunset: session.hasSunsetScene,
                        showsAurora: session.hasAuroraScene,
                        realWorldTwinEnabled: settings.streamsRealWorldScenery,
                        worldMode: settings.windowWorldMode
                    ),
                    clockAnchor: FlightVisualClockAnchor(
                        legElapsed: session.legElapsed,
                        displayDate: .now
                    )
                )
                .transition(.opacity)
            } else {
                Color(hex: isNight ? "0B0910" : "1A1E2A")
            }
        }
        .allowsHitTesting(false)
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
    }

    private var mapCard: some View {
        FlightMapView(session: session, showsControls: studyView == .map)
            .aspectRatio(0.78, contentMode: .fit)
            .overlay {
                // A warmed map is long past the cover interval and shows this
                // not at all. A genuinely cold one crossfades from the same
                // calm palette as the departure curtain — never bare MapKit.
                if showsMapCover {
                    LinearGradient(
                        colors: [Color(hex: "0D1531"), Color(hex: "050713")],
                        startPoint: .top, endPoint: .bottom
                    )
                    .transition(.opacity)
                    .accessibilityHidden(true)
                }
            }
            .animation(.easeInOut(duration: 0.32), value: showsMapCover)
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
            Text(session.legRemaining.focusCountdownText)
                .font(.system(size: 56, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                // No content transition: `.numericText` cross-dissolves the old
                // and new glyph, and on a monospaced clock ticking every second
                // that morph is visible as a smeared, doubled digit. A plain
                // swap on a fixed-width face is clean at any capture instant.
                .animation(nil, value: session.legRemaining.focusCountdownText)

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.legRemaining.focusCountdownText) remaining to \(session.currentLeg.destination.city)")
        .accessibilityHint(showInfoPill ? "Hide flight details" : "Show flight details")
        .accessibilityAddTraits(.isButton)
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

    // MARK: Beverage cart

    /// The cart is at your row: one tap takes a water, then it moves on.
    private var beverageCartCard: some View {
        Button {
            withAnimation(.snappy(duration: 0.35)) {
                session.takeWater()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stay hydrated")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.95))
                    Text("You've been flying a while — have some water")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Text("Take a sip")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.white.opacity(0.9), in: Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 28)
        .accessibilityLabel("Beverage service. Take a water.")
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
