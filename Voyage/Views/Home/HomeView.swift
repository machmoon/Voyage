import SwiftUI
import SwiftData
import MapKit

/// The globe home screen: realistic satellite Earth, airport pins,
/// route-arc previews, and the booking flow (depart now / schedule).
struct HomeView: View {
    /// Called with a fully configured session when the user departs.
    let onDepart: (FlightSession) -> Void

    init(onDepart: @escaping (FlightSession) -> Void) {
        self.onDepart = onDepart
    }

    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [LogbookEntry]

    @State private var settings = SettingsStore.shared
    @State private var scheduler = FlightScheduler.shared
    @State private var locationManager = LocationManager()

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedDestination: Airport?
    @State private var showingSchedule = false
    @State private var showingLogbook = false
    @State private var showingSettings = false
    @State private var nowTick = Date()
    /// A fresh line each time Home is built, i.e. every launch. Picked once so
    /// it stays put while you browse, and never repeats the previous launch.
    @State private var greeting = HomeGreeting.next()

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var origin: Airport { settings.homeAirport }

    /// Destinations ordered shortest flight first, so the card row reads
    /// like a departure board sorted by time.
    private var destinations: [Airport] {
        Airport.all.filter { $0 != origin }
            .sorted {
                RoutePlanner.itinerary(from: origin, to: $0).totalFocusDuration
                    < RoutePlanner.itinerary(from: origin, to: $1).totalFocusDuration
            }
    }

    private var selectedItinerary: Itinerary? {
        selectedDestination.map { RoutePlanner.itinerary(from: origin, to: $0) }
    }

    var body: some View {
        ZStack {
            globe
                .ignoresSafeArea()

            // Calm cover over the globe's blank first frames at cold start —
            // above the map, below the chrome — dissolved once MapKit paints.
            StartupGlobeCover()

            VStack(spacing: 0) {
                header
                if let scheduled = scheduler.scheduled {
                    scheduledBanner(scheduled)
                        .padding(.top, 8)
                }
                Spacer()
                bookingPanel
            }
        }
        .sheet(isPresented: $showingSchedule) {
            if let destination = selectedDestination {
                ScheduleSheet(origin: origin, destination: destination) { option in
                    scheduler.schedule(destination: destination,
                                       departure: option.departure,
                                       origin: origin,
                                       flightNumber: option.flightNumber)
                }
                .presentationDetents([.large])
                .presentationCornerRadius(28)
            }
        }
        .sheet(isPresented: $showingLogbook) {
            LogbookView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .onAppear {
            locationManager.resolveHomeAirport()
            scheduler.pruneExpired()
            recenter(animated: false)
            applyPendingShortcutDeparture()
        }
        .onChange(of: settings.originOverrideCode) {
            selectedDestination = nil
            recenter(animated: true)
        }
        .onChange(of: settings.resolvedOriginCode) {
            recenter(animated: true)
        }
        .onReceive(clock) { nowTick = $0 }
    }

    // MARK: Globe

    private var globe: some View {
        // Resolved once per render rather than per pin: `selectedItinerary`
        // runs the route planner, and asking it inside the annotation loop
        // planned the same route once for every airport on screen.
        let roles = routeRoles
        let segments = routeSegments
        return Map(position: $cameraPosition, interactionModes: [.pan, .zoom, .rotate]) {
            // Route first, pins second. Map content draws in declaration order,
            // so the old ordering laid the line over the top of every dot it
            // passed and made the arc read as a pipe crossing the airports.
            GlobeRoute.arc(segments)

            ForEach(Airport.all) { airport in
                Annotation(airport.code, coordinate: airport.coordinate) {
                    airportPin(airport, role: roles[airport.code] ?? .available)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.imagery(elevation: .realistic))
    }

    // MARK: Route line

    private var routeRoles: [String: GlobeRoute.PinRole] {
        let itinerary = selectedItinerary
        var roles: [String: GlobeRoute.PinRole] = [:]
        for airport in Airport.all {
            if airport == origin {
                roles[airport.code] = .origin
            } else if let itinerary {
                if airport == itinerary.destination {
                    roles[airport.code] = .destination
                } else if itinerary.connection == airport {
                    roles[airport.code] = .connection
                } else {
                    roles[airport.code] = .offRoute
                }
            } else {
                roles[airport.code] = .available
            }
        }
        return roles
    }

    private var routeSegments: [GlobeRoute.Segment] {
        guard let itinerary = selectedItinerary else { return [] }
        return GlobeRoute.segments(
            legs: itinerary.legs.map { ($0.origin.coordinate, $0.destination.coordinate) }
        )
    }

    // MARK: Pins

    private func airportPin(_ airport: Airport, role: GlobeRoute.PinRole) -> some View {
        Button {
            guard role != .origin else { return }
            Haptics.tap()
            withAnimation(.snappy) { selectedDestination = airport }
        } label: {
            GlobeAirportPin(airport: airport, role: role)
            // Airports off the booked route stay tappable but stop shouting.
            // In a SFO to YVR to YQR booking this is what finally separates
            // SEA, which sits almost on the line without being part of it.
            .opacity(role == .offRoute ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.35), value: role == .offRoute)
    }

    private func recenter(animated: Bool) {
        let camera = MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: origin.latitude - 8,
                                                     longitude: origin.longitude),
            distance: 22_000_000
        )
        if animated {
            withAnimation(.smooth(duration: 1.2)) {
                cameraPosition = .camera(camera)
            }
        } else {
            cameraPosition = .camera(camera)
        }
    }

    /// Siri / Shortcuts "Depart on a focus flight" lands here with a destination pre-selected.
    private func applyPendingShortcutDeparture() {
        guard let code = PendingDepartureStore.destinationCode,
              let airport = Airport.all.first(where: { $0.code == code }),
              airport != origin else {
            PendingDepartureStore.destinationCode = nil
            return
        }
        PendingDepartureStore.destinationCode = nil
        withAnimation(.snappy) { selectedDestination = airport }
        Haptics.success()
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("VOYAGE")
                    .font(.system(size: 23, weight: .black))
                    .kerning(5)
                    .foregroundStyle(.white)
                if settings.originIsUnknown {
                    // No fix and no choice, so the app does not know what is
                    // nearest and must not draw a location arrow next to a
                    // default. Name the airport it is actually flying from and
                    // make the line the way to change it: one tap, no extra
                    // screen, and nothing on screen claims to be your location.
                    Button {
                        Haptics.tap()
                        showingSettings = true
                    } label: {
                        originLine(
                            glyph: "airplane.departure",
                            trailing: "Set your airport",
                            showsChevron: true
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "Departing \(origin.city), \(origin.code). "
                        + "Voyage could not find your nearest airport. Set it in Settings."
                    )
                } else {
                    originLine(
                        // A chosen origin is not a location fix, so it does not
                        // get the location glyph either.
                        glyph: settings.originIsFromLocation ? "location.fill" : "airplane.departure",
                        trailing: lifetimeMiles > 0 ? "\(lifetimeMiles.formatted()) mi" : nil,
                        showsChevron: false
                    )
                }
            }

            Spacer(minLength: 8)

            headerActions
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    /// The origin line under the VOYAGE mark. One shape for all three origin
    /// states so they keep the same rhythm and only the glyph and the trailing
    /// item change.
    private func originLine(glyph: String,
                            trailing: String?,
                            showsChevron: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: glyph)
                .font(.system(size: 9))
            Text("\(origin.city) · \(origin.code)")
                .font(.caption.weight(.medium))

            if let trailing {
                Circle()
                    .frame(width: 3, height: 3)
                    .opacity(0.65)
                Text(trailing)
                    .font(.caption2.weight(.semibold))
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.8)
            }
        }
        .foregroundStyle(.white.opacity(0.75))
        .lineLimit(1)
        // The whole line is one unit: it shrinks rather than letting the
        // origin code truncate to "S…" behind the Logbook pill.
        .minimumScaleFactor(0.75)
    }

    private var lifetimeMiles: Int {
        Int(LogbookStats.totalMiles(entries))
    }

    private var headerActions: some View {
        HStack(spacing: 2) {
            Button {
                Haptics.tap()
                showingLogbook = true
            } label: {
                Label("Logbook", systemImage: "book.closed.fill")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open logbook")

            Button {
                Haptics.tap()
                showingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    // Without this the hit area is the glyph, not the frame:
                    // XCUITest measured this button at 16x16pt on device while
                    // the frame above asks for 34x34. An Image label has no fill
                    // of its own, so `Button` takes the drawn glyph's bounds.
                    // The sibling Logbook button already does this (above).
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
    }

    // MARK: Scheduled flight banner

    @ViewBuilder
    private func scheduledBanner(_ flight: ScheduledFlight) -> some View {
        let status = flight.status(at: nowTick)
        VStack(spacing: 8) {
            scheduledBannerRow(flight, status: status)
            if scheduler.notificationsDenied {
                Text("Notifications are off, so boarding and final calls won't reach you. Turn them on in Settings.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 20)
    }

    private func scheduledBannerRow(_ flight: ScheduledFlight,
                                    status: ScheduledFlight.Status) -> some View {
        HStack(spacing: 12) {
            Image(systemName: status == .boarding ? "figure.walk.departure" : "clock.badge.checkmark")
                .font(.title3)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(status == .boarding
                     ? "Now boarding · \(flight.destination.city)"
                     : "Upcoming flight · \(flight.destination.city)")
                    .font(.subheadline.weight(.semibold))
                Text(scheduledDetail(flight, status: status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if status == .boarding {
                Button("Board") {
                    boardScheduled(flight)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .font(.subheadline.weight(.bold))
            } else {
                Button {
                    scheduler.cancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func scheduledDetail(_ flight: ScheduledFlight, status: ScheduledFlight.Status) -> String {
        let number = flight.flightNumber.map { "\($0) · " } ?? ""
        if status == .boarding {
            return number + "Gate closes \(flight.boardingCloses.formatted(date: .omitted, time: .shortened))"
        }
        let day = Calendar.current.isDateInToday(flight.departure) ? "" : " tomorrow"
        return number + "Departs\(day) \(flight.departure.formatted(date: .omitted, time: .shortened))"
    }

    private func boardScheduled(_ flight: ScheduledFlight) {
        let number = flight.flightNumber
        scheduler.cancel()
        depart(to: flight.destination, flightNumber: number)
    }

    // MARK: Booking panel

    private var bookingPanel: some View {
        VStack(spacing: 14) {
            if let itinerary = selectedItinerary {
                routeSummary(itinerary)
            } else {
                Text(greeting)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 3)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(destinations) { airport in
                        destinationCard(airport)
                    }
                }
                .padding(.horizontal, 20)
            }

            if selectedItinerary != nil {
                departButtons
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 12)
    }

    /// Two calm lines: the route on top, the focus math underneath.
    /// Never wraps mid-pill.
    private func routeSummary(_ itinerary: Itinerary) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 8) {
                Text(itinerary.origin.code)
                    .font(.system(size: 16, weight: .heavy, design: .monospaced))
                Image(systemName: "airplane")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                if let via = itinerary.connection {
                    Text(via.code)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                    Image(systemName: "airplane")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Text(itinerary.destination.code)
                    .font(.system(size: 16, weight: .heavy, design: .monospaced))
            }
            Text(itinerary.totalFocusDuration.shortDurationText + " focus"
                 + (itinerary.isConnection ? " · lounge break" : ""))
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
        .fixedSize()
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(.black.opacity(0.45), in: Capsule())
    }

    private func destinationCard(_ airport: Airport) -> some View {
        let itinerary = RoutePlanner.itinerary(from: origin, to: airport)
        let isSelected = airport == selectedDestination
        return Button {
            Haptics.tap()
            withAnimation(.snappy) {
                selectedDestination = isSelected ? nil : airport
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(airport.code)
                        .font(.system(size: 20, weight: .heavy, design: .monospaced))
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.accent)
                    }
                }
                Text(airport.city)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: itinerary.isConnection ? "arrow.triangle.swap" : "timer")
                        .font(.system(size: 8, weight: .bold))
                    Text(itinerary.connection.map {
                        "\(itinerary.totalFocusDuration.shortDurationText) focus · via \($0.code)"
                    } ?? "\(itinerary.totalFocusDuration.shortDurationText) focus")
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .opacity(0.65)
            }
            .padding(12)
            .frame(width: 132, alignment: .leading)
            .background(
                isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.ultraThinMaterial),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .shadow(color: .black.opacity(isSelected ? 0.25 : 0), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .black : .white)
        .accessibilityIdentifier("destination-\(airport.code)")
    }

    /// Pill buttons matching the app's capsule language: quiet glass for
    /// scheduling and solid white for the immediate focus-flight action.
    private var departButtons: some View {
        HStack(spacing: 10) {
            Button {
                showingSchedule = true
            } label: {
                Label("Schedule", systemImage: "clock")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            Button {
                if let destination = selectedDestination {
                    depart(to: destination)
                }
            } label: {
                Label("Depart now", systemImage: "airplane.departure")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(.white, in: Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .accessibilityIdentifier("depart-now")
        }
    }

    private func depart(to destination: Airport, flightNumber: String? = nil) {
        let itinerary = RoutePlanner.itinerary(from: origin, to: destination,
                                               flightNumberOverride: flightNumber)
        let session = FlightSession(itinerary: itinerary,
                                    modelContext: modelContext,
                                    tier: LogbookStats.tier(entries))
        session.prepareRealWorldTwin()

        // Every departure starts cold: the curtain must not be waved through by
        // a previous flight's success.
        DepartureReadiness.shared.resetForNewBooking()

        // Start warming the satellite tiles around the origin runway now, so the
        // real-world window has a rendered frame ready by the time it mounts.
        if settings.streamsRealWorldScenery {
            MapWarmer.shared.warm(around: origin.coordinate,
                                  headingDegrees: origin.runway?.heading ?? 0)
        }

        Haptics.success()
        onDepart(session)
    }
}
