import SwiftUI
import SwiftData

/// Top-level router: shows the globe home screen until a flight session
/// exists, then drives the ritual → flight → landing flow off its stage.
struct RootView: View {
    @State private var session: FlightSession?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @State private var scheduler = FlightScheduler.shared
    @State private var settings = SettingsStore.shared

    var body: some View {
        ZStack {
            if !settings.hasCompletedOnboarding {
                OnboardingView {
                    withAnimation(.smooth(duration: 0.6)) {
                        settings.hasCompletedOnboarding = true
                    }
                }
                .transition(.opacity)
            } else if let session {
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
        // Cross-dissolve every full-screen stage swap — including the departure
        // curtain → in-flight window — so takeoff reads as one clean fade rather
        // than a hard cut.
        .animation(.smooth(duration: 0.55), value: sessionStageKey)
        .onChange(of: scenePhase) { _, newPhase in
            session?.handleScenePhase(newPhase)
            if newPhase == .active {
                scheduler.pruneExpired()
                if !Self.debugStampScreenshot {
                    Task { await FocusIntegration.shared.refresh() }
                }
            }
        }
        .onAppear {
            Haptics.prepare()
            #if DEBUG
            // QA-only: jump straight to the passport-stamp payoff, and skip the
            // Focus authorization prompt so it can't cover the capture.
            if Self.debugStampScreenshot, session == nil {
                settings.hasCompletedOnboarding = true
                session = FlightSession.debugArrived(modelContext: modelContext)
            }
            #endif
            if !Self.debugStampScreenshot {
                Task { await FocusIntegration.shared.refresh() }
            }
        }
        .preferredColorScheme(session?.stage == .inFlight ? .dark : nil)
    }

    private static var debugStampScreenshot: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-VoyageDebugStamp")
        #else
        false
        #endif
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
                // Ritual dismissed before the rip: back to the gate. Nothing is
                // going to mount a window, so drop the warm map now.
                session.cancelBeforeDeparture()
                MapWarmer.shared.cancel()
                DepartureReadiness.shared.resetForNewBooking()
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
