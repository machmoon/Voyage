import SwiftUI

/// The pre-flight ritual, three beats: seat → check a bag → boarding pass.
/// Ripping the pass IS the departure — no extra confirmation page after.
struct BoardingFlowView: View {
    @Bindable var session: FlightSession
    let onCancel: () -> Void

    enum Step: Int, Comparable {
        case seat, bag, pass
        static func < (lhs: Step, rhs: Step) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    @State private var step: Step = .seat
    @State private var isDeparting = false
    @State private var settings = SettingsStore.shared

    private var isCabinStep: Bool { step == .seat }

    private var leg: FlightLeg { session.itinerary.legs[0] }

    var body: some View {
        ZStack {
            Group {
                switch step {
                case .seat:
                    Theme.seatMapBackground
                case .bag:
                    Theme.seatMapBackground
                case .pass:
                    Theme.boardingBackdrop
                }
            }
            .ignoresSafeArea()
            .animation(.smooth(duration: 0.35), value: step)

            if !isDeparting {
                VStack(spacing: 0) {
                    topBar
                    content
                }
            }

            if isDeparting {
                DepartureCurtainOverlay(
                    originCode: leg.origin.code,
                    destinationCode: leg.destination.code,
                    durationText: session.itinerary.totalFocusDuration.shortDurationText,
                    compact: FlightSession.shortFlightsEnabled,
                    sweepDuration: DepartureGate.minimumHold(
                        shortFlights: FlightSession.shortFlightsEnabled
                    )
                )
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .onAppear {
            // Build the audio graph here, on entry to the ritual, rather than
            // lazily inside the beat that first needs sound. Constructing it
            // is a synchronous RPC to the audio server that aborts the process
            // on timeout, so where it happens is a product decision: a whole
            // view transition away from any tap or drag, and before the rip
            // starts the flight. See `CabinAudioEngine.prewarm()`.
            CabinAudioEngine.shared.prewarm()
        }
    }

    private var topBar: some View {
        HStack {
            if step == .seat {
                Button(action: onCancel) {
                    backButtonIcon("chevron.left", ink: Theme.seatMapInk, background: Theme.seatMapInk.opacity(0.06))
                }
                .accessibilityLabel("Cancel booking")
            } else {
                Button { retreat(by: -1) } label: {
                    backButtonIcon("chevron.left",
                                   ink: step == .seat ? Theme.seatMapInk : (step == .bag ? .secondary : .white.opacity(0.9)),
                                   background: step == .seat ? Theme.seatMapInk.opacity(0.06)
                                       : (step == .bag ? Theme.cardBackground : .white.opacity(0.12)))
                }
                .accessibilityLabel("Back")
            }
            Spacer()
            stepIndicator
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func backButtonIcon(_ systemName: String, ink: Color, background: Color) -> some View {
        Image(systemName: systemName)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(ink)
            .frame(width: 34, height: 34)
            .background(background, in: Circle())
    }

    private func retreat(by delta: Int) {
        guard let previous = Step(rawValue: step.rawValue + delta) else { return }
        withAnimation(.smooth(duration: 0.45)) { step = previous }
    }

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { i in
                Capsule()
                    .fill(
                        i <= step.rawValue
                            ? Theme.accent
                            : (isCabinStep ? Theme.seatMapInk.opacity(0.15) : Color(.systemFill))
                    )
                    .frame(width: i == step.rawValue ? 22 : 8, height: 6)
            }
        }
        .animation(.snappy, value: step)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .seat:
            SeatSelectionView(session: session) {
                advance(to: .bag)
            }
            .transition(stepTransition)
        case .bag:
            CheckBagView(session: session) {
                advance(to: .pass)
            }
            .transition(stepTransition)
        case .pass:
            BoardingPassView(
                session: session,
                onBoarded: beginDeparture
            )
            .transition(stepTransition)
        }
    }

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    private func advance(to next: Step) {
        withAnimation(.smooth(duration: 0.45)) {
            step = next
        }
    }

    /// The curtain is the map's loading screen, so it holds until the satellite
    /// window actually has a frame — floored by the minimum beat so it never
    /// flashes past, and capped so the app always departs.
    private func beginDeparture() {
        withAnimation(.easeOut(duration: 0.2)) {
            isDeparting = true
        }

        let quick = FlightSession.shortFlightsEnabled
        let minimum = DepartureGate.minimumHold(shortFlights: quick)
        let maximum = DepartureGate.maximumHold(shortFlights: quick)
        let waitsForMap = DepartureGate.waitsForMap(
            worldMode: settings.windowWorldMode,
            streamedSceneryAllowed: WorldSceneryConfiguration.streamedSceneryAllowedByProcess,
            isOnline: WorldSceneryAvailability.shared.isOnline
        )

        Task { @MainActor in
            let started = Date()
            while !DepartureGate.shouldDepart(
                mapHasRenderedFrame: DepartureReadiness.shared.mapHasRenderedFrame,
                elapsed: Date().timeIntervalSince(started),
                minimum: minimum,
                maximum: maximum,
                waitsForMap: waitsForMap
            ) {
                try? await Task.sleep(for: .milliseconds(80))
                if Task.isCancelled { break }
            }
            session.departFirstLeg()
        }
    }
}
