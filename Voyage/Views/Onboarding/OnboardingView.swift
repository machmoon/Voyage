import SwiftUI
import MapKit

/// First-run onboarding, staged over the *same* satellite globe the Home screen
/// uses. The camera flies from a full-Earth view down to the exact framing Home
/// opens with, and the final screen cross-dissolves straight into Home with no
/// seam. Copy sits in the app's glass cards, with the kerned VOYAGE header,
/// monospaced airport codes, a single accent, and the white pill CTA.
///
/// Four pages, each showing one thing that is specific to Voyage rather than
/// describing it: real block times from the route catalog, a boarding pass you
/// can tear, the 30-second rule beside the real passport stamp, and what stays
/// on the phone. A fifth, Airplane Mode (Screen Time app blocking), sits
/// before privacy in builds that carry Screen Time; it is optional, and
/// Continue works without touching it.
///
/// Sources for the shape:
/// - Apple HIG, Onboarding: "fast, fun, and optional", "Teach through
///   interactivity", let people skip. The tear on page two is the interaction;
///   Skip stays on every page but the last.
/// - Apple HIG, Privacy: "Avoid requesting permission at launch unless the data
///   or resource is required for your app to function." Voyage works without
///   location (Home offers "Set your airport"), so the request moved from this
///   view's `onAppear` to the last page's button, right after the page that
///   says what location is used for. That page has one button and no Skip, as
///   the HIG's pre-alert guidance asks.
/// - Home Assistant iOS (home-assistant/iOS,
///   Sources/App/Onboarding/Steps/Permissions/OnboardingPermissionsNavigationViewModel.swift):
///   value first, then privacy, then permissions. Its location page
///   (Steps/Permissions/Steps/Location/LocationPermissionView.swift) says what
///   the data is for and that it is not sent to third parties, right beside
///   the request, which is what the privacy page does here.
/// - The same rule for Screen Time: the Airplane Mode page says what it does
///   first, and the system's Screen Time prompt appears only from its own
///   "Choose apps to block" button, never on page appear. Foqos asks on a
///   dedicated intro screen too (awaseem/foqos
///   Foqos/Components/Intro/PermissionsIntroScreen.swift at 4f6864c); here it
///   is one optional button instead of a wall.
/// - WhatsNewKit (SvenTiigi/WhatsNewKit, Sources/View/WhatsNewView.swift):
///   the Apple welcome-screen row, symbol plus a semibold line plus a
///   secondary line, each row combined into one accessibility element.
struct OnboardingView: View {
    /// Called once the traveler taps through the final screen.
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settings = SettingsStore.shared
    @State private var page = 0
    @State private var cameraPosition: MapCameraPosition
    @State private var arcRevealed = false
    @State private var locationManager = LocationManager()
    @State private var passTorn = false
    @State private var airplaneMode = AirplaneMode.shared
    @State private var choosingApps = false
    /// Fixed when onboarding opens, so a page cannot vanish under the
    /// traveler if Screen Time turns out to be unavailable on this iPhone.
    @State private var pages: [OnboardingPage] = OnboardingPage.pages(
        offersAirplaneMode: AirplaneMode.shared.isAvailable)

    /// Derived live from settings, never frozen: when location resolves the
    /// nearest airport, the globe, pins, sample arc and camera all follow, so
    /// the final frame still matches Home's and the cross-dissolve stays
    /// seamless.
    private var home: Airport { settings.homeAirport }

    /// A sample long-haul route (the farthest airport), drawn on the globe and
    /// printed on the boarding pass.
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

    private var pageCount: Int { pages.count }

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
                    ForEach(Array(pages.enumerated()), id: \.element) { index, item in
                        // Scrolls only if the card outgrows the frame (large
                        // Dynamic Type); at normal sizes it sits still, so
                        // there's no vertical rubber-band to glitch while paging.
                        ScrollView(.vertical) {
                            OnboardingCard(page: item) { pageContent(item) }
                                .padding(.horizontal, 20)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 500)

                footer
            }
        }
        .preferredColorScheme(.dark)
        .airplaneModePicker(isPresented: $choosingApps)
        .onChange(of: page) { _, newPage in flyCamera(to: newPage) }
        .onChange(of: settings.resolvedOriginCode) { _, _ in
            // Nearest airport just resolved: re-fly the current framing to it so
            // the globe tracks the real origin.
            flyCamera(to: page)
        }
        .onAppear {
            // No permission request here. Location is asked for on the last
            // page's button, after the page that explains it.
            let settled = Self.camera(for: 0, home: home, destination: destination, settled: true)
            if reduceMotion {
                cameraPosition = .camera(settled)
            } else {
                // A gentle settle on first appearance so the Earth feels alive.
                withAnimation(.smooth(duration: 1.4)) { cameraPosition = .camera(settled) }
            }
        }
    }

    // MARK: Pages

    @ViewBuilder
    private func pageContent(_ item: OnboardingPage) -> some View {
        switch item {
        case .hello:
            HelloPage(home: home)
        case .takeoff:
            if let destination {
                TakeoffPage(itinerary: RoutePlanner.itinerary(from: home, to: destination),
                            torn: $passTorn)
            }
        case .inFlight:
            InFlightRulesPage(home: home)
        case .airplaneMode:
            AirplaneModePage(airplaneMode: airplaneMode, choosingApps: $choosingApps)
        case .privacy:
            PrivacyPage(showsIntelligence: IntelligenceAvailability.current.offersSetting,
                        showsAirplaneMode: pages.contains(.airplaneMode))
        }
    }

    private var topScrim: some View {
        LinearGradient(
            colors: [Theme.ink.opacity(0.65), .clear],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: 190)
    }

    // MARK: Globe

    /// The sample arc, built through the same code Home uses so the final
    /// cross-dissolve lands on an identical picture.
    private var routeSegments: [GlobeRoute.Segment] {
        guard let destination, arcRevealed else { return [] }
        return GlobeRoute.segments(legs: [(home.coordinate, destination.coordinate)])
    }

    private var globe: some View {
        Map(position: $cameraPosition, interactionModes: []) {
            // Route first, pins second: map content draws in declaration order,
            // and the old ordering laid the line over the top of the dots.
            GlobeRoute.arc(routeSegments)

            Annotation(home.code, coordinate: home.coordinate) {
                GlobeAirportPin(airport: home, role: .origin)
            }
            .annotationTitles(.hidden)

            if let destination, arcRevealed {
                Annotation(destination.code, coordinate: destination.coordinate) {
                    GlobeAirportPin(airport: destination, role: .destination)
                        .transition(.scale.combined(with: .opacity))
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.imagery(elevation: .realistic))
    }

    private var legibilityScrim: some View {
        LinearGradient(
            colors: [.clear, Theme.ink.opacity(0.55), Theme.ink.opacity(0.9)],
            startPoint: .center, endPoint: .bottom
        )
        .frame(height: 560)
    }

    // MARK: Header (mirrors HomeView)

    private var isLastPage: Bool { page == pageCount - 1 }

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
            // Not on the last page: that page's button is the one that leads
            // to the location alert, and the HIG asks that a pre-alert screen
            // offer no way around it.
            if !isLastPage {
                Button("Skip") { finish(requestLocation: false) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .transition(.opacity)
                    .accessibilityIdentifier("onboarding-skip")
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 4)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .animation(.smooth(duration: 0.3), value: page)
    }

    // MARK: Footer, page dots and primary action

    private var footer: some View {
        VStack(spacing: 22) {
            HStack(spacing: 7) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? Theme.accent : .white.opacity(0.3))
                        .frame(width: index == page ? 22 : 7, height: 7)
                        .animation(.snappy(duration: 0.3), value: page)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Page \(page + 1) of \(pageCount)")

            Button(action: advance) {
                Text(isLastPage ? "Start flying" : "Continue")
                    .contentTransition(.opacity)
            }
            .buttonStyle(VoyagePrimaryButtonStyle())
            .padding(.horizontal, 24)
            .accessibilityIdentifier("onboarding-primary")
        }
        .padding(.bottom, 30)
    }

    // MARK: Actions

    private func advance() {
        Haptics.tap()
        if isLastPage {
            finish(requestLocation: true)
        } else {
            withAnimation(.smooth(duration: 0.45)) { page += 1 }
        }
    }

    /// `requestLocation` is true only from the privacy page's button. A skip
    /// leaves the request to Home, which makes it on appear exactly as before.
    private func finish(requestLocation: Bool) {
        if requestLocation { locationManager.resolveHomeAirport() }
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
    /// continuous approach. Full-Earth (34M) to Home. Every page after the
    /// first exactly matches HomeView's opening framing (`center: home.lat
    /// minus 8`, `distance: 22_000_000`) so the cross-dissolve into Home lands
    /// identically.
    private static func camera(for page: Int, home: Airport, destination: Airport?, settled: Bool = false) -> MapCamera {
        switch page {
        case 0:
            return MapCamera(
                centerCoordinate: CLLocationCoordinate2D(latitude: home.latitude - 4,
                                                         longitude: home.longitude),
                distance: settled ? 34_000_000 : 42_000_000
            )
        default:
            return MapCamera(
                centerCoordinate: CLLocationCoordinate2D(latitude: home.latitude - 8,
                                                         longitude: home.longitude),
                distance: 22_000_000
            )
        }
    }
}

// MARK: - Page list

enum OnboardingPage: Int, CaseIterable, Identifiable {
    case hello, takeoff, inFlight, airplaneMode, privacy

    var id: Int { rawValue }

    /// The pages shown, in order. Airplane Mode only where Screen Time can
    /// actually block something (`AirplaneMode.isAvailable`).
    static func pages(offersAirplaneMode: Bool) -> [OnboardingPage] {
        allCases.filter { $0 != .airplaneMode || offersAirplaneMode }
    }

    var kicker: String {
        switch self {
        case .hello: return "HELLO"
        case .takeoff: return "TAKEOFF"
        case .inFlight: return "IN FLIGHT"
        case .airplaneMode: return "AIRPLANE MODE"
        case .privacy: return "PRIVACY"
        }
    }

    var title: String {
        switch self {
        case .hello: return "I made studying feel like a flight."
        case .takeoff: return "Tear your pass to take off."
        case .inFlight: return "Stay with it until you land."
        case .airplaneMode: return "Go dark at takeoff."
        case .privacy: return "Your flights stay on your phone."
        }
    }
}

// MARK: - Card

private struct OnboardingCard<Content: View>: View {
    let page: OnboardingPage
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FieldLabel(page.kicker).foregroundStyle(Theme.accent)

            Text(page.title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            content
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
                // Opaque: at 0.9 the globe's home pin showed through the copy.
                .fill(Theme.surfaceElevated)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: Theme.ink.opacity(0.45), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding-page-\(page.rawValue)")
    }
}

/// Body copy on the dark card.
private struct CardText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.white.opacity(0.72))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Page 1: hello, with real block times

private struct HelloPage: View {
    let home: Airport

    /// Three real routes from home, shortest to longest, straight from the
    /// catalog. The numbers on this page are the numbers in the app.
    private var samples: [(Airport, TimeInterval)] {
        let others = Airport.all.filter { $0 != home }
            .map { ($0, RoutePlanner.itinerary(from: home, to: $0).totalFocusDuration) }
            .sorted { $0.1 < $1.1 }
        guard others.count >= 3 else { return others }
        return [others.first!, others[others.count / 2], others.last!]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardText("I'm Patrick. I study electrical engineering at UCSB and I fly a lot. Pick a real route, and its flight time is how long you study.")

            VStack(spacing: 0) {
                ForEach(samples, id: \.0.code) { destination, duration in
                    HStack(spacing: 8) {
                        Text(home.code)
                            .font(.system(size: 15, weight: .heavy, design: .monospaced))
                        Text("\u{2192}")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.accent)
                        Text(destination.code)
                            .font(.system(size: 15, weight: .heavy, design: .monospaced))
                        Text(destination.city)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(duration.shortDurationText)
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(home.city) to \(destination.city), \(duration.shortDurationText) of study")
                }
            }

            Link(destination: URL(string: "https://github.com/machmoon/Voyage")!) {
                Text("Free and open source. No ads, no account.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityHint("Opens the source code on GitHub")
        }
    }
}

// MARK: - Page 2: the boarding pass, tearable

private struct TakeoffPage: View {
    let itinerary: Itinerary
    @Binding var torn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardText("Pack up to three bags, the things you want to finish. Then tear the pass. That's takeoff, and the clock starts.")
            MiniBoardingPass(itinerary: itinerary, torn: $torn)
            Text(torn ? "Cleared for takeoff. Tap the pass to try again."
                      : "Try it. Tap the stub.")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.55))
                .contentTransition(.opacity)
                .frame(maxWidth: .infinity)
        }
    }
}

/// A small copy of the real pass (`BoardingPassView`): ink on paper, the
/// route in monospaced codes, the catalog's flight number and block time, the
/// same `BarcodeView` on the stub. Tapping the stub drops it the way the real
/// one falls; tapping the torn pass puts it back.
private struct MiniBoardingPass: View {
    let itinerary: Itinerary
    @Binding var torn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            passBody
            stub
        }
        // Printed paper, always light, as on the real pass.
        .environment(\.colorScheme, .light)
        .frame(maxWidth: .infinity)
    }

    private var passBody: some View {
        VStack(spacing: 12) {
            HStack {
                FieldLabel("Boarding pass")
                Spacer()
                Text(itinerary.primaryFlightNumber)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            HStack {
                code(itinerary.origin)
                Spacer()
                VStack(spacing: 2) {
                    Image(systemName: "airplane")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text(itinerary.totalFocusDuration.shortDurationText)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                code(itinerary.destination)
            }
        }
        .foregroundStyle(Color.black)
        .padding(16)
        .background(Color.white, in: UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 0,
                                                            bottomTrailingRadius: 0, topTrailingRadius: 16,
                                                            style: .continuous))
        .overlay(alignment: .bottom) {
            Line()
                .stroke(style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                .foregroundStyle(Color.black.opacity(0.25))
                .frame(height: 1)
                .padding(.horizontal, 10)
        }
        .contentShape(Rectangle())
        .onTapGesture { if torn { reset() } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Boarding pass, \(itinerary.origin.city) to \(itinerary.destination.city), \(itinerary.totalFocusDuration.shortDurationText)")
    }

    private func code(_ airport: Airport) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(airport.code)
                .font(.system(size: 28, weight: .heavy, design: .monospaced))
            Text(airport.city)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var stub: some View {
        Button(action: tear) {
            HStack {
                BarcodeView(seed: itinerary.primaryFlightNumber)
                    .frame(width: 130, height: 30)
                Spacer()
                Image(systemName: "hand.tap.fill")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white, in: UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 16,
                                                                bottomTrailingRadius: 16, topTrailingRadius: 0,
                                                                style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.black)
        .rotationEffect(.degrees(torn && !reduceMotion ? 8 : 0), anchor: .topLeading)
        .offset(y: torn && !reduceMotion ? 70 : 0)
        .opacity(torn ? 0 : 1)
        .disabled(torn)
        .accessibilityLabel("Tear the boarding pass")
        .accessibilityHidden(torn)
        .accessibilityIdentifier("onboarding-tear-stub")
    }

    private func tear() {
        guard !torn else { return }
        Haptics.rip()
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeIn(duration: 0.5)) { torn = true }
    }

    private func reset() {
        Haptics.tap()
        withAnimation(.smooth(duration: 0.35)) { torn = false }
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}

// MARK: - Page 3: the 30-second rule and the stamp

private struct InFlightRulesPage: View {
    let home: Airport

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("30s")
                    .font(.system(size: 26, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 64, alignment: .leading)
                CardText("Leave the app for more than 30 seconds and your flight stops early. That's the whole trick. It's easier to stay when there's a plane to land.")
            }
            .accessibilityElement(children: .combine)

            HStack(alignment: .center, spacing: 14) {
                // The real cachet from the arrival screen, on passport paper.
                ArrivalCachet(code: home.code, city: home.city,
                              dateText: Self.dateText, milesText: "+0 MI")
                    // Laid out at its real size, then shrunk; scaling a
                    // cachet squeezed into the frame truncated its text.
                    .fixedSize()
                    .rotationEffect(.degrees(-6))
                    .scaleEffect(0.56)
                    .frame(width: 118, height: 116)
                    .background(Theme.passportPaper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                CardText("When you land, you get a passport stamp and the flight goes in your logbook. You can replay any trip on the map.")
            }
        }
    }

    private static var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd MMM yyyy"
        return formatter.string(from: .now).uppercased()
    }
}

// MARK: - Page 4: Airplane Mode (Screen Time)

/// Optional. The button asks for Screen Time access (the system prompt) and
/// then opens the app picker; Continue works without either. If Screen Time
/// cannot be used on this iPhone, the page says so in place of the button.
private struct AirplaneModePage: View {
    let airplaneMode: AirplaneMode
    @Binding var choosingApps: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardText("Pick the apps that pull you away. They're blocked from takeoff until you land. Wi-Fi stays on.")

            if airplaneMode.isAvailable {
                Button {
                    Haptics.tap()
                    Task {
                        if await airplaneMode.requestAuthorization() { choosingApps = true }
                    }
                } label: {
                    Label(airplaneMode.selectionCount > 0 ? "Change apps" : "Choose apps to block",
                          systemImage: "airplane")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Theme.accent.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding-choose-apps")

                Group {
                    if airplaneMode.selectionCount > 0 {
                        Text(AirplaneModeCopy.blockedLine(count: airplaneMode.selectionCount))
                    } else if airplaneMode.authorization == .denied {
                        Text("Screen Time access is off. You can turn it on later in Settings.")
                    } else {
                        Text("Optional. Uses Apple's Screen Time; your choices stay on this iPhone.")
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Screen Time isn't available on this iPhone, so this one is skipped.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { airplaneMode.refresh() }
    }
}

// MARK: - Page 5: privacy

/// Every row is checked against the code; the report that shipped this page
/// lists the file behind each one. If a row stops being true, change it.
private struct PrivacyPage: View {
    let showsIntelligence: Bool
    let showsAirplaneMode: Bool

    private struct Row: Identifiable {
        let symbol: String
        let title: String
        let detail: String
        var id: String { title }
    }

    private var rows: [Row] {
        var rows = [
            Row(symbol: "iphone",
                title: "Your logbook lives on this iPhone.",
                detail: "No account, no ads, no tracking. It only leaves if you share it."),
            Row(symbol: "location",
                title: "Location finds your nearest airport.",
                detail: "It's worked out on the phone. Only the airport code is kept."),
            Row(symbol: "cloud.sun",
                title: "Weather comes from Open-Meteo.",
                detail: "It gets points along your route, never your own location."),
            Row(symbol: "map",
                title: "Maps come from Apple.",
                detail: "The globe and maps are Apple Maps, so Apple gets those map requests."),
        ]
        if showsAirplaneMode {
            // AppBlockerUtil.swift: the selection is Apple's opaque tokens in
            // the App Group, and nothing in the app sends it anywhere.
            rows.append(Row(symbol: "airplane",
                            title: "Airplane Mode uses Screen Time.",
                            detail: "The apps you pick stay on this iPhone, as tokens only Apple can read."))
        }
        if showsIntelligence {
            rows.append(Row(symbol: "sparkles",
                            title: "Apple Intelligence runs on this iPhone.",
                            detail: "The flight plan and the captain's note are written on the device."))
        }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Image(systemName: row.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 22)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(row.detail)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Next, iOS asks for your location once. You can say no and pick an airport.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Link("Privacy notice",
                     destination: URL(string: "https://github.com/machmoon/Voyage/blob/main/PRIVACY.md")!)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.top, 2)
        }
    }
}

#Preview {
    OnboardingView(onFinished: {})
}
