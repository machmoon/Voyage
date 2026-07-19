import SwiftUI

/// The pre-flight ritual: seat → check a bag → boarding pass rip → flight mode.
/// Ends by telling the session to depart.
struct BoardingFlowView: View {
    @Bindable var session: FlightSession
    let onCancel: () -> Void

    enum Step: Int, Comparable {
        case seat, bag, pass, flightMode
        static func < (lhs: Step, rhs: Step) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    @State private var step: Step = .seat

    private var isCabinStep: Bool { step == .seat }

    var body: some View {
        ZStack {
            Group {
                if isCabinStep {
                    Theme.cabinCanvas
                } else {
                    Color(.systemGroupedBackground)
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
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(isCabinStep ? Theme.cabinSecondary : .secondary)
                        .frame(width: 34, height: 34)
                        .background(
                            isCabinStep ? Theme.cabinAisle : Theme.cardBackground,
                            in: Circle()
                        )
                }
            }
            Spacer()
            stepIndicator
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<4) { i in
                Capsule()
                    .fill(
                        i <= step.rawValue
                            ? (isCabinStep ? session.itinerary.destination.accentColor : Color.accentColor)
                            : (isCabinStep ? Theme.cabinMetal : Color(.systemFill))
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
                advance(to: .flightMode)
            }
            .transition(stepTransition)
        case .flightMode:
            FlightModeView(session: session) {
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
