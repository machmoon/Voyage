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

    private var isCabinStep: Bool { step == .seat }

    var body: some View {
        ZStack {
            Group {
                switch step {
                case .seat:
                    Theme.seatMapBackground
                case .bag:
                    Color(.systemGroupedBackground)
                case .pass:
                    Theme.boardingBackdrop
                }
            }
            .ignoresSafeArea()
            .animation(.smooth(duration: 0.35), value: step)

            VStack(spacing: 0) {
                topBar
                content
            }
        }
    }

    private var topBar: some View {
        HStack {
            if step < .pass {
                Button(action: onCancel) {
                    Image(systemName: isCabinStep ? "chevron.left" : "xmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(isCabinStep ? Theme.seatMapInk : .secondary)
                        .frame(width: 34, height: 34)
                        .background(
                            isCabinStep ? Theme.seatMapInk.opacity(0.06) : Theme.cardBackground,
                            in: Circle()
                        )
                }
                .accessibilityLabel("Back")
            }
            Spacer()
            stepIndicator
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
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
            BoardingPassView(session: session) {
                session.departFirstLeg()
            }
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
