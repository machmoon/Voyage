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

    private var isCabinStep: Bool { step == .seat }

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

            VStack(spacing: 0) {
                topBar
                    .opacity(isDeparting ? 0 : 1)
                    .allowsHitTesting(!isDeparting)
                content
            }
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
            // The pass owns the tear animation and only reports back once the
            // rip commits — tearing is departing, so the chrome leaves with it.
            BoardingPassView(
                session: session,
                onBoarded: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isDeparting = true
                    }
                    session.departFirstLeg()
                }
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
}
