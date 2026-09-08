import SwiftUI
import SwiftData

/// Top-level router: shows the globe home screen until a flight session
/// exists, then drives the ritual → flight → landing flow off its stage.
struct RootView: View {
    @State private var session: FlightSession?
    @Environment(\.scenePhase) private var scenePhase
    @State private var scheduler = FlightScheduler.shared

    var body: some View {
        ZStack {
            if let session {
                sessionFlow(session)
                    .transition(.opacity)
            } else {
                HomeView { newSession in
                    withAnimation(.smooth(duration: 0.5)) {
                        self.session = newSession
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.45), value: sessionStageKey)
        .onChange(of: scenePhase) { _, newPhase in
            session?.handleScenePhase(newPhase)
            if newPhase == .active {
                scheduler.pruneExpired()
                sweepOrphanedActivity()
            }
        }
        .onAppear {
            Haptics.prepare()
            sweepOrphanedActivity()
        }
        .preferredColorScheme(session?.stage == .inFlight ? .dark : nil)
    }

    /// A Live Activity outlives the process that started it. If we are here
    /// with no session, anything still on the lock screen belongs to a flight
    /// that ended while the app was suspended or killed, so close it.
    private func sweepOrphanedActivity() {
        guard session == nil else { return }
        FlightActivityController.shared.endOrphaned()
    }

    private var sessionStageKey: String {
        guard let session else { return "home" }
        return String(describing: session.stage)
    }

    @ViewBuilder
    private func sessionFlow(_ session: FlightSession) -> some View {
        switch session.stage {
        case .preflight:
            BoardingFlowView(session: session) {
                // Ritual dismissed before the rip: back to the gate.
                session.cancelBeforeDeparture()
                self.session = nil
            }
        case .inFlight:
            InFlightView(session: session)
        case .layover:
            LayoverLoungeView(session: session)
        case .arrived:
            ArrivalFlowView(session: session) {
                self.session = nil
            }
        case .diverted:
            DivertedView(session: session, kind: .diverted) {
                self.session = nil
            }
        case .missedConnection:
            DivertedView(session: session, kind: .missedConnection) {
                self.session = nil
            }
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: LogbookEntry.self, inMemory: true)
}
