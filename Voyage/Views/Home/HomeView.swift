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

    private var destinations: [Airport] {
        Airport.all.filter { $0 != origin }
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
                ScheduleSheet(origin: origin, destination: destination) { departure in
                    scheduler.schedule(destination: destination, departure: departure, origin: origin)
                }
                .presentationDetents([.height(360)])
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
                            itinerary.destination.accentColor,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [7, 5])
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
                ZStack {
                    Circle()
                        .fill(isOrigin ? Color.white : (isSelected ? airport.accentColor : .black.opacity(0.55)))
                        .frame(width: isOrigin || isSelected ? 26 : 20, height: isOrigin || isSelected ? 26 : 20)
                        .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                    Image(systemName: isOrigin ? "house.fill" : "airplane.arrival")
                        .font(.system(size: isOrigin ? 11 : 9, weight: .bold))
                        .foregroundStyle(isOrigin ? .black : .white)
                }
                Text(airport.code)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 2)
            }
        }
        .buttonStyle(.plain)
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

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("VOYAGE")
                    .font(.system(size: 24, weight: .black))
                    .kerning(5)
                    .foregroundStyle(.white)
                HStack(spacing: 6) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 9))
                    Text("\(origin.city) · \(origin.code)")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(.white.opacity(0.75))
            }
            Spacer()
            HStack(spacing: 10) {
                statusChip
                iconButton("book.closed.fill") { showingLogbook = true }
                iconButton("gearshape.fill") { showingSettings = true }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var statusChip: some View {
        let tier = LogbookStats.tier(entries)
        let miles = Int(LogbookStats.totalMiles(entries))
        return VStack(alignment: .trailing, spacing: 1) {
            Text(tier.rawValue.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .kerning(1.2)
            Text("\(miles.formatted()) mi")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func iconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    // MARK: Scheduled flight banner

    @ViewBuilder
    private func scheduledBanner(_ flight: ScheduledFlight) -> some View {
        let status = flight.status(at: nowTick)
        HStack(spacing: 12) {
            Image(systemName: status == .boarding ? "figure.walk.departure" : "clock.badge.checkmark")
                .font(.title3)
                .foregroundStyle(flight.destination.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(status == .boarding
                     ? "Now boarding · \(flight.destination.city)"
                     : "Scheduled · \(flight.destination.city)")
                    .font(.subheadline.weight(.semibold))
                Text(status == .boarding
                     ? "Gate closes \(flight.boardingCloses.formatted(date: .omitted, time: .shortened))"
                     : "Departs \(flight.departure.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if status == .boarding {
                Button("Board") {
                    boardScheduled(flight)
                }
                .buttonStyle(.borderedProminent)
                .tint(flight.destination.accentColor)
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
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 20)
    }

    private func boardScheduled(_ flight: ScheduledFlight) {
        scheduler.cancel()
        depart(to: flight.destination)
    }

    // MARK: Booking panel

    private var bookingPanel: some View {
        VStack(spacing: 14) {
            if let itinerary = selectedItinerary {
                routeSummary(itinerary)
            } else {
                Text("Where are we flying today?")
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

    private func routeSummary(_ itinerary: Itinerary) -> some View {
        HStack(spacing: 10) {
            Text(itinerary.origin.code)
                .font(.system(size: 17, weight: .heavy, design: .monospaced))
            Image(systemName: "airplane")
                .font(.caption)
            if let via = itinerary.connection {
                Text(via.code)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                Image(systemName: "airplane")
                    .font(.caption)
            }
            Text(itinerary.destination.code)
                .font(.system(size: 17, weight: .heavy, design: .monospaced))
            Text("·")
            Text(itinerary.totalFocusDuration.shortDurationText + " focus")
                .font(.subheadline.weight(.medium))
            if itinerary.isConnection {
                Text("+ lounge break")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
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
                    Circle()
                        .fill(airport.accentColor)
                        .frame(width: 8, height: 8)
                }
                Text(airport.city)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: itinerary.isConnection ? "arrow.triangle.swap" : "arrow.right")
                        .font(.system(size: 8, weight: .bold))
                    Text(itinerary.isConnection
                         ? "\(itinerary.totalFocusDuration.shortDurationText) via \(itinerary.connection!.code)"
                         : itinerary.totalFocusDuration.shortDurationText)
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(width: 132, alignment: .leading)
            .background(isSelected ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.ultraThinMaterial),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? airport.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.primary : Color.white)
    }

    private var departButtons: some View {
        HStack(spacing: 10) {
            Button {
                showingSchedule = true
            } label: {
                Label("Schedule", systemImage: "calendar.badge.clock")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Button {
                if let destination = selectedDestination {
                    depart(to: destination)
                }
            } label: {
                Label("Depart now", systemImage: "airplane.departure")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .background(
                selectedDestination?.accentColor ?? .accentColor,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
    }

    private func depart(to destination: Airport) {
        let itinerary = RoutePlanner.itinerary(from: origin, to: destination)
        let session = FlightSession(itinerary: itinerary,
                                    modelContext: modelContext,
                                    tier: LogbookStats.tier(entries))
        Haptics.success()
        onDepart(session)
    }
}
