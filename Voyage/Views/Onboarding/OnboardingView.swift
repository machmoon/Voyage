import SwiftUI
import MapKit

/// First-run "preflight" onboarding, staged over the *same* satellite globe the
/// Home screen uses. The camera flies from a full-Earth view down to the exact
/// framing Home opens with, and the final screen cross-dissolves straight into
/// Home — no seam. Copy sits in the app's glass cards, with the kerned VOYAGE
/// header, monospaced airport codes, single accent, and white pill CTA.
struct OnboardingView: View {
    /// Called once the traveler taps through the final screen.
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settings = SettingsStore.shared
    @State private var page = 0
    @State private var cameraPosition: MapCameraPosition
    @State private var arcRevealed = false
    @State private var locationManager = LocationManager()

    /// Derived live from settings, never frozen: when location resolves the
    /// nearest airport mid-onboarding, the globe, pins, sample arc and the
    /// page-2 camera all follow — so the final frame still matches Home's and
    /// the cross-dissolve stays seamless.
    private var home: Airport { settings.homeAirport }

    /// A dramatic sample route (farthest airport) previewed on the middle screen.
    private var destination: Airport? {
        let home = self.home
        return Airport.all
            .filter { $0 != home }
            .max { home.distanceMiles(to: $0) < home.distanceMiles(to: $1) }
    }

    init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
        let home = SettingsStore.shared.homeAirport
        _cameraPosition = State(initialValue: .camera(Self.camera(for: 0, home: home, destination: nil)))
    }

    private static let pages: [OnboardingPage] = [
        OnboardingPage(
            kicker: "PREFLIGHT",
            title: "A focus timer you have to land.",
            body: "Every study session is a real airline route, flown in real time. Once you're airborne, leaving the app diverts the flight — the only clean ending is landing."
        ),
        OnboardingPage(
            kicker: "HOW IT WORKS",
            title: "Three steps, gate to gate.",
            steps: [
                .init(symbol: "airplane.departure", headline: "Book a route",
                      detail: "Pick a city pair. The airline's real flight time sets your session length."),
                .init(symbol: "window.vertical.closed", headline: "Study through the window",
                      detail: "The window and the moving map track your real position. Stay in the app and the flight keeps flying."),
                .init(symbol: "seal.fill", headline: "Land and log it",
                      detail: "Every completed flight stamps your passport and adds its miles to your logbook.")
            ]
        ),
        OnboardingPage(
            kicker: "READY",
            title: "Cleared for departure.",
            body: "Your origin is set to the nearest airport. Choose a destination on the globe and take off.",
            showsOpenSource: true
        )
    ]

    var body: some View {
        ZStack {
            globe
                .ignoresSafeArea()
                .overlay(alignment: .top) { topScrim }
                .overlay(alignment: .bottom) { legibilityScrim }
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)

                TabView(selection: $page) {
                    ForEach(Array(Self.pages.enumerated()), id: \.offset) { index, model in
                        // Scrolls only if the card outgrows the frame (large
                        // Dynamic Type); at normal sizes it sits still, so
                        // there's no vertical rubber-band to glitch while paging.
                        ScrollView(.vertical) {
                            OnboardingCard(model: model, isActive: page == index,
                                           route: index == 2 ? routeChip : nil)
                                .padding(.horizontal, 20)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 400)

                footer
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: page) { _, newPage in flyCamera(to: newPage) }
        .onChange(of: settings.resolvedOriginCode) { _, _ in
            // Nearest airport just resolved: re-fly the current framing to it so
            // the globe (and the page-2 → Home dissolve) tracks the real origin.
            flyCamera(to: page)
        }
        .onAppear {
            // Resolve the nearest airport now so it's already home by the time
            // the traveler lands on the globe — no "home" is ever chosen.
            locationManager.resolveHomeAirport()
            let settled = Self.camera(for: 0, home: home, destination: destination, settled: true)
            if reduceMotion {
                cameraPosition = .camera(settled)
            } else {
                // A gentle settle on first appearance so the Earth feels alive.
                withAnimation(.smooth(duration: 1.4)) { cameraPosition = .camera(settled) }
            }
        }
    }

    private var topScrim: some View {
        LinearGradient(
            colors: [Theme.ink.opacity(0.65), .clear],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: 190)
    }

    // MARK: Globe (mirrors HomeView)

    private var globe: some View {
        Map(position: $cameraPosition, interactionModes: []) {
            Annotation(home.code, coordinate: home.coordinate) { homePin }
                .annotationTitles(.hidden)

            if let destination, arcRevealed {
                Annotation(destination.code, coordinate: destination.coordinate) { destinationPin(destination) }
                    .annotationTitles(.hidden)
                MapPolyline(coordinates: [home.coordinate, destination.coordinate], contourStyle: .geodesic)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
        .mapStyle(.imagery(elevation: .realistic))
    }

    private var homePin: some View {
        ZStack {
            Circle().fill(.white).frame(width: 26, height: 26)
                .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
            Image(systemName: "house.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.black)
        }
        .shadow(color: .black.opacity(0.4), radius: 4)
    }

    private func destinationPin(_ airport: Airport) -> some View {
        VStack(spacing: 3) {
            ZStack {
                Circle().fill(Theme.accent).frame(width: 24, height: 24)
                    .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                Image(systemName: "airplane.arrival")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(airport.code)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.8), radius: 2)
        }
        .transition(.scale.combined(with: .opacity))
    }

    private var legibilityScrim: some View {
        LinearGradient(
            colors: [.clear, Theme.ink.opacity(0.55), Theme.ink.opacity(0.9)],
            startPoint: .center, endPoint: .bottom
        )
        .frame(height: 520)
    }

    // MARK: Header (mirrors HomeView)

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("VOYAGE")
                    .font(.system(size: 23, weight: .black))
                    .kerning(5)
                    .foregroundStyle(.white)
                HStack(spacing: 6) {
                    Image(systemName: "location.fill").font(.system(size: 9))
                    Text("Departs from your nearest airport")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(.white.opacity(0.75))
            }
            Spacer(minLength: 8)
            if page < Self.pages.count - 1 {
                Button("Skip") { finish() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .transition(.opacity)
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 4)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .animation(.smooth(duration: 0.3), value: page)
    }

    private var routeChip: some View {
        HStack(spacing: 8) {
            Text(home.code)
                .font(.system(size: 15, weight: .heavy, design: .monospaced))
            Image(systemName: "airplane")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text(destination?.code ?? "•••")
                .font(.system(size: 15, weight: .heavy, design: .monospaced))
        }
        .foregroundStyle(.white)
    }

    // MARK: Footer — dots + primary action

    private var footer: some View {
        VStack(spacing: 22) {
            HStack(spacing: 7) {
                ForEach(0..<Self.pages.count, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? Theme.accent : .white.opacity(0.3))
                        .frame(width: index == page ? 22 : 7, height: 7)
                        .animation(.snappy(duration: 0.3), value: page)
                }
            }

            Button(action: advance) {
                Text(page == Self.pages.count - 1 ? "Start flying" : "Continue")
                    .contentTransition(.opacity)
            }
            .buttonStyle(VoyagePrimaryButtonStyle())
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 30)
    }

    // MARK: Actions

    private func advance() {
        Haptics.tap()
        if page == Self.pages.count - 1 {
            finish()
        } else {
            withAnimation(.smooth(duration: 0.45)) { page += 1 }
        }
    }

    private func finish() {
        Haptics.success()
        onFinished()
    }

    private func flyCamera(to newPage: Int) {
        let duration = reduceMotion ? 0.001 : 1.1
        let revealing = newPage >= 1 && !arcRevealed
        withAnimation(.smooth(duration: 0.4)) {
            arcRevealed = newPage >= 1
        }
        withAnimation(.smooth(duration: duration)) {
            cameraPosition = .camera(Self.camera(for: newPage, home: home, destination: destination, settled: true))
        }
        // A soft haptic when the sample route first draws in — the plane
        // "arriving" at its destination, echoing the app's physical beats.
        if revealing, !reduceMotion {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.7) {
                Haptics.softTick()
            }
        }
    }

    /// Cameras for each screen — a *monotonic* descent so the flow reads as one
    /// continuous approach to your seat: full-Earth (34M) → route (26M) → Home.
    /// Page 2 exactly matches HomeView's opening framing (`center: home.lat − 8`,
    /// `distance: 22_000_000`) so the cross-dissolve into Home lands identically.
    private static func camera(for page: Int, home: Airport, destination: Airport?, settled: Bool = false) -> MapCamera {
        switch page {
        case 0:
            return MapCamera(
                centerCoordinate: CLLocationCoordinate2D(latitude: home.latitude - 4,
                                                         longitude: home.longitude),
                distance: settled ? 34_000_000 : 42_000_000
            )
        case 1:
            // Frame the sample arc while keeping the limb of the Earth in black
            // space (don't zoom in past Home): centre a touch south of the route
            // midpoint so the geodesic sweeps the upper third above the card.
            let dest = destination ?? home
            let mid = CLLocationCoordinate2D(latitude: (home.latitude + dest.latitude) / 2 - 8,
                                             longitude: (home.longitude + dest.longitude) / 2)
            return MapCamera(centerCoordinate: mid, distance: 26_000_000)
        default:
            return MapCamera(
                centerCoordinate: CLLocationCoordinate2D(latitude: home.latitude - 8,
                                                         longitude: home.longitude),
                distance: 22_000_000
            )
        }
    }
}

// MARK: - Page model

private struct OnboardingPage {
    let kicker: String
    let title: String
    var body: String?
    var steps: [Step] = []
    var showsOpenSource: Bool = false

    struct Step: Identifiable {
        let id = UUID()
        let symbol: String
        let headline: String
        let detail: String
    }
}

// MARK: - Glass card

private struct OnboardingCard<Route: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: OnboardingPage
    let isActive: Bool
    let route: Route?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                FieldLabel(model.kicker).foregroundStyle(Theme.accent)
                Spacer()
                if let route { route }
            }

            Text(model.title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            if let body = model.body {
                Text(body)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !model.steps.isEmpty {
                VStack(spacing: 14) {
                    ForEach(Array(model.steps.enumerated()), id: \.element.id) { index, step in
                        stepRow(step, index: index)
                    }
                }
                .padding(.top, 2)
            }

            if model.showsOpenSource { openSourceLink }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background {
            // The same ink-blue surface used on the arrival/logbook cards
            // (Theme.surfaceElevated). Deliberately *not* .ultraThinMaterial:
            // a live blur over the MapKit globe layer samples stale frames and
            // flickers while paging. A mostly-opaque app surface reads on-brand
            // and stays rock-steady during the swipe.
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Theme.surfaceElevated.opacity(0.9))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: Theme.ink.opacity(0.45), radius: 18, y: 8)
    }

    private var openSourceLink: some View {
        Link(destination: URL(string: "https://github.com/machmoon/Voyage")!) {
            HStack(spacing: 7) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 11, weight: .bold))
                Text("Open source · MIT")
                    .font(.caption.weight(.semibold))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(Theme.accent)
        }
        .padding(.top, 6)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(height: 1)
                .offset(y: -2)
        }
    }

    private func stepRow(_ step: OnboardingPage.Step, index: Int) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.accent.opacity(0.16))
                Image(systemName: step.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 1) {
                Text(step.headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(step.detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .opacity(isActive || reduceMotion ? 1 : 0)
        .offset(y: isActive || reduceMotion ? 0 : 10)
        .animation(reduceMotion ? nil : .smooth(duration: 0.5).delay(isActive ? Double(index) * 0.08 : 0),
                   value: isActive)
    }
}

#Preview {
    OnboardingView(onFinished: {})
}
