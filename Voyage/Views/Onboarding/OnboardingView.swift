import SwiftUI
import MapKit

/// First-run onboarding, staged over the *same* satellite globe the Home screen
/// uses. The camera flies from a full-Earth view down to the exact framing Home
/// opens with, and the final screen cross-dissolves straight into Home with no
/// seam. Copy sits in the app's glass cards, with the kerned VOYAGE header,
/// monospaced airport codes, a single accent, and the white pill CTA.
///
/// The three "how it works" steps are carried by type and spacing alone:
/// monospaced index numbers (the same numeric treatment as the airport codes),
/// a semibold headline, and a secondary line. No decorative symbols in the card.
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
    /// page-2 camera all follow, so the final frame still matches Home's and
    /// the cross-dissolve stays seamless.
    private var home: Airport { settings.homeAirport }

    /// A sample long-haul route (the farthest airport) previewed on screen two.
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
            body: "A study session is a real airline route, flown in its real flight time. Stay in the app until you land and the time is logged. Leave early and the session ends."
        ),
        OnboardingPage(
            kicker: "HOW IT WORKS",
            title: "Three steps, start to finish.",
            steps: [
                .init(headline: "Book a real route",
                      detail: "Choose an origin and destination. The airline's real flight time becomes your focus timer."),
                .init(headline: "Study through the window",
                      detail: "The window view and moving map follow your real position. Stay in the app and the flight continues."),
                .init(headline: "Land to log it",
                      detail: "A finished flight adds its miles to your logbook and a stamp to your passport.")
            ]
        ),
        OnboardingPage(
            kicker: "READY",
            title: "Pick your first route.",
            body: "Your origin is set to the nearest airport. Choose a destination on the globe to begin.",
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

            // Calm cover over the globe's blank first frames at cold start —
            // above the map, below the copy — dissolved once MapKit paints.
            StartupGlobeCover()

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
            // the globe (and the page-2 to Home dissolve) tracks the real origin.
            flyCamera(to: page)
        }
        .onAppear {
            // Resolve the nearest airport now so it's already home by the time
            // the traveler lands on the globe. No "home" is ever chosen.
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

    // Globe markers are the app's shared map pins, identical to HomeView's, so
    // the final cross-dissolve into Home lands on the same picture. They are
    // live-map annotations, not onboarding card chrome.
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
                Text("Real routes, flown in real time")
                    .font(.caption.weight(.medium))
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

    // The sample route, shown on the final card. A plain typographic arrow
    // between two monospaced codes, matching the airport-code system. No symbol.
    private var routeChip: some View {
        HStack(spacing: 8) {
            Text(home.code)
                .font(.system(size: 15, weight: .heavy, design: .monospaced))
            Text("\u{2192}")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.accent)
            Text(destination?.code ?? "\u{2022}\u{2022}\u{2022}")
                .font(.system(size: 15, weight: .heavy, design: .monospaced))
        }
        .foregroundStyle(.white)
    }

    // MARK: Footer, page dots and primary action

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
        // A soft haptic when the sample route first draws in, echoing the app's
        // physical beats.
        if revealing, !reduceMotion {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.7) {
                Haptics.softTick()
            }
        }
    }

    /// Cameras for each screen: a *monotonic* descent so the flow reads as one
    /// continuous approach. Full-Earth (34M) to route (26M) to Home. Page 2
    /// exactly matches HomeView's opening framing (`center: home.lat minus 8`,
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
            // space (do not zoom in past Home): centre a touch south of the route
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
                VStack(spacing: 20) {
                    ForEach(Array(model.steps.enumerated()), id: \.element.id) { index, step in
                        stepRow(step, index: index)
                    }
                }
                .padding(.top, 6)
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
            Text("Open source, MIT licensed")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 8)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(height: 1)
                .offset(y: -1)
        }
    }

    // A single step, carried by typography: a monospaced index (the same
    // numeric treatment as the airport codes) sets the rhythm, then a semibold
    // headline and a secondary line. No icon tile, no decorative glyph.
    private func stepRow(_ step: OnboardingPage.Step, index: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(String(format: "%02d", index + 1))
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.accent)
                .frame(width: 24, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(step.headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(step.detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineSpacing(2)
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
