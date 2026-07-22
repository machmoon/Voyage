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
        Map(position: $cameraPosition, interactionModes: [.pan, .zoom, .rotate]) {
            ForEach(Airport.all) { airport in
                Annotation(airport.code, coordinate: airport.coordinate) {
                    airportPin(airport)
                }
                .annotationTitles(.hidden)
            }
            if let itinerary = selectedItinerary {
                ForEach(itinerary.legs) { leg in
                    MapPolyline(coordinates: [leg.origin.coordinate, leg.destination.coordinate],
                                contourStyle: .geodesic)
                        .stroke(
                            Theme.accent,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                }
            }
        }
        .mapStyle(.imagery(elevation: .realistic))
    }

    private func airportPin(_ airport: Airport) -> some View {
        let isOrigin = airport == origin
        let isSelected = airport == selectedDestination
        return Button {
            guard !isOrigin else { return }
            Haptics.tap()
            withAnimation(.snappy) { selectedDestination = airport }
        } label: {
            VStack(spacing: 3) {
                if labelSitsAbove(airport) { code(airport) }
                ZStack {
                    Circle()
                        .fill(isOrigin ? Color.white : (isSelected ? Theme.accent : .black.opacity(0.55)))
                        .frame(width: isOrigin || isSelected ? 26 : 20, height: isOrigin || isSelected ? 26 : 20)
                        .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                    Image(systemName: isOrigin ? "house.fill" : "airplane.arrival")
                        .font(.system(size: isOrigin ? 11 : 9, weight: .bold))
                        .foregroundStyle(isOrigin ? .black : .white)
                }
                if !labelSitsAbove(airport) { code(airport) }
            }
        }
        .buttonStyle(.plain)
    }

    private func code(_ airport: Airport) -> some View {
        Text(airport.code)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.8), radius: 2)
    }

    /// The globe has no label declutter of its own, so pins that sit within a
    /// few degrees of each other stack their codes (SEA landed on top of YVR).
    /// The more northern of a close pair carries its code above the dot.
    private func labelSitsAbove(_ airport: Airport) -> Bool {
        Airport.all.contains { other in
            other != airport
                && abs(other.latitude - airport.latitude) < 6
                && abs(other.longitude - airport.longitude) < 6
                && other.latitude < airport.latitude
        }
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
                HStack(spacing: 6) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 9))
                    Text("Focus flights · \(origin.code)")
                        .font(.caption.weight(.medium))

                    if lifetimeMiles > 0 {
                        Circle()
                            .frame(width: 3, height: 3)
                            .opacity(0.65)
                        Text("\(lifetimeMiles.formatted()) mi")
                            .font(.caption2.weight(.semibold))
                    }
                }
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                // The whole line is one unit: it shrinks rather than letting the
                // origin code truncate to "S…" behind the Logbook pill.
                .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 8)

            headerActions
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
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
                Text("Notifications are off — boarding calls and final-call alerts can't ring. Enable them in Settings.")
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
                VStack(spacing: 3) {
                    Text("Choose your focus flight")
                        .font(.headline)
                    Text("Each route is an uninterrupted study session")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                }
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
                Label("Schedule focus", systemImage: "clock")
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
                Label("Start focus flight", systemImage: "airplane.departure")
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
        Haptics.success()
        onDepart(session)
    }
}
