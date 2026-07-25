import SwiftUI
import MapKit
import SwiftData
import StoreKit

/// Strava-style landing payoff: a short route replay celebration, then a post
/// composer with title, optional notes, and a route overview card for the logbook.
struct FlightPostView: View {
    @Bindable var session: FlightSession
    let onDone: () -> Void

    @Environment(\.requestReview) private var requestReview
    @Environment(\.modelContext) private var modelContext
    @Query private var logbookEntries: [LogbookEntry]

    private enum Phase {
        case celebrate, compose
    }

    @State private var phase: Phase = .celebrate
    @State private var routeProgress: CGFloat = 0
    @State private var celebrateRevealed = false
    @State private var postTitle = ""
    @State private var shareCaption = ""
    @State private var posted = false
    @State private var receiptPNG: Data?

    private var itinerary: Itinerary { session.itinerary }
    private var destination: Airport { itinerary.destination }

    var body: some View {
        ZStack {
            backdrop

            switch phase {
            case .celebrate:
                celebrateScreen
                    .transition(.opacity)
            case .compose:
                composeScreen
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            postTitle = LogbookStats.defaultPostTitle()
            startCelebrate()
        }
    }

    // MARK: Celebrate — route draws in like Strava Activity Replay

    private var celebrateScreen: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            Text("Landed in \(destination.city)")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .opacity(celebrateRevealed ? 1 : 0)
                .offset(y: celebrateRevealed ? 0 : 12)

            routeHeroCard(animated: true)
                .padding(.horizontal, 24)
                .padding(.top, 20)

            statsRow
                .padding(.top, 18)
                .opacity(celebrateRevealed ? 1 : 0)

            if let badge = achievementBadge {
                Label(badge, systemImage: "trophy.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.statusAmber)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.statusAmber.opacity(0.14), in: Capsule())
                    .padding(.top, 14)
                    .opacity(celebrateRevealed ? 1 : 0)
            }

            Spacer()

            Button { advanceToCompose() } label: {
                Text("Continue")
            }
            .buttonStyle(VoyagePrimaryButtonStyle())
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
            .opacity(routeProgress > 0.85 ? 1 : 0.35)
            .disabled(routeProgress < 0.85)
        }
    }

    // MARK: Compose — title, notes, route card, post to logbook

    private var composeScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("LOG YOUR FLIGHT")
                        .font(.system(size: 11, weight: .heavy))
                        .kerning(2)
                        .foregroundStyle(Theme.statusAmber)
                    Text("Post to your logbook")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }

                TextField("What did you work on? (optional)", text: $shareCaption, axis: .vertical)
                    .lineLimit(2...5)
                    .font(.subheadline)
                    .padding(12)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(.white)

                TextField("Title", text: $postTitle)
                    .font(.headline)
                    .padding(12)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(.white)

                routeHeroCard(animated: false)

                statsRow

                if let badge = achievementBadge {
                    Label(badge, systemImage: "trophy.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.statusAmber)
                }

                if posted {
                    shareSection
                }

                Button(action: posted ? onDone : postToLogbook) {
                    Text(posted ? "Back to the terminal" : "Post to logbook")
                }
                .buttonStyle(VoyagePrimaryButtonStyle())

                if !posted {
                    Button("Skip for now", action: onDone)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 36)
            .padding(.bottom, 30)
        }
    }

    // MARK: Shared pieces

    private var backdrop: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.surfaceSubtle, Theme.surfaceDark, Theme.ink],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [Theme.accent.opacity(0.22), .clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }

    private func routeHeroCard(animated: Bool) -> some View {
        ZStack(alignment: .bottomLeading) {
            RouteOverviewMap(
                legs: itinerary.legs,
                progress: animated ? routeProgress : 1
            )
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .center, endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("\(itinerary.origin.code) → \(itinerary.destination.code)")
                    .font(.system(size: 16, weight: .heavy, design: .monospaced))
                Text(itinerary.primaryFlightNumber)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .foregroundStyle(.white)
            .padding(14)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            postStat("Focus", session.itinerary.totalFocusDuration.shortDurationText)
            postStat("Miles", "+\(Int(session.completedMiles).formatted())")
            postStat("Seat", session.seat)
        }
        .padding(.vertical, 12)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 24)
    }

    private func postStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
    }

    private var achievementBadge: String? {
        guard let entry = session.logEntry,
              LogbookStats.isPersonalBestFocus(entry, among: logbookEntries) else { return nil }
        return "Personal best focus on this route"
    }

    private var shareSection: some View {
        VStack(spacing: 12) {
            if let receiptPNG, let uiImage = UIImage(data: receiptPNG) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                ShareLink(
                    item: ReceiptShareItem(pngData: receiptPNG),
                    preview: SharePreview(
                        postTitle.isEmpty ? "Flight to \(destination.code)" : postTitle,
                        image: Image(uiImage: uiImage)
                    )
                ) {
                    Label("Share flight card", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(.white.opacity(0.22), lineWidth: 1)
                        )
                }
            }
        }
    }

    // MARK: Actions

    private func startCelebrate() {
        Task { @MainActor in
            withAnimation(.smooth(duration: 0.6)) { celebrateRevealed = true }
            Haptics.success()
            withAnimation(.easeInOut(duration: 2.2)) { routeProgress = 1 }
            try? await Task.sleep(for: .milliseconds(2_400))

            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-VoyageDebugStampHold") { return }
            #endif

            advanceToCompose()
        }
    }

    private func advanceToCompose() {
        withAnimation(.smooth(duration: 0.45)) { phase = .compose }
    }

    private func postToLogbook() {
        guard let entry = session.logEntry else {
            onDone()
            return
        }
        let trimmedTitle = postTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCaption = shareCaption.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.postTitle = trimmedTitle.isEmpty ? LogbookStats.defaultPostTitle() : trimmedTitle
        entry.shareCaption = trimmedCaption.isEmpty ? nil : trimmedCaption
        try? modelContext.save()
        receiptPNG = FlightReceiptRenderer.pngData(session: session, caption: shareCaption)
        Haptics.success()
        withAnimation(.smooth(duration: 0.35)) { posted = true }
        Task { await askForReviewIfEarned() }
    }

    private func askForReviewIfEarned() async {
        guard AppFeedback.shouldRequestReview() else { return }
        try? await Task.sleep(for: .milliseconds(800))
        AppFeedback.markReviewRequested()
        requestReview()
    }
}

// MARK: - Route overview map

/// Draws the flown route with a trim-style reveal for the celebration beat.
private struct RouteOverviewMap: View {
    let legs: [FlightLeg]
    let progress: CGFloat

    @State private var cameraPosition: MapCameraPosition = .automatic

    private var clampedProgress: CGFloat { min(1, max(0, progress)) }

    var body: some View {
        Map(position: $cameraPosition, interactionModes: []) {
            ForEach(Array(legs.enumerated()), id: \.offset) { index, leg in
                let legFraction = legDrawFraction(index: index)
                if legFraction > 0 {
                    MapPolyline(
                        coordinates: partialRoute(from: leg.origin.coordinate,
                                                  to: leg.destination.coordinate,
                                                  fraction: legFraction),
                        contourStyle: .geodesic
                    )
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                }
            }
            if let plane = planeCoordinate {
                Annotation("", coordinate: plane) {
                    Image(systemName: "airplane")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Theme.accent, in: Circle())
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.imagery(elevation: .realistic))
        .onAppear { fitCamera() }
        .onChange(of: progress) { _, _ in fitCamera() }
    }

    private func legDrawFraction(index: Int) -> CGFloat {
        guard !legs.isEmpty else { return 0 }
        let slice = 1 / CGFloat(legs.count)
        let start = slice * CGFloat(index)
        let local = (clampedProgress - start) / slice
        return min(1, max(0, local))
    }

    private var planeCoordinate: CLLocationCoordinate2D? {
        guard !legs.isEmpty else { return nil }
        let overall = Double(clampedProgress) * Double(legs.count)
        let index = min(legs.count - 1, Int(overall))
        let local = overall - Double(index)
        let leg = legs[index]
        return GreatCircle.point(from: leg.origin.coordinate,
                                 to: leg.destination.coordinate,
                                 fraction: min(1, local))
    }

    private func partialRoute(from start: CLLocationCoordinate2D,
                              to end: CLLocationCoordinate2D,
                              fraction: CGFloat) -> [CLLocationCoordinate2D] {
        let samples = GreatCircle.points(from: start, to: end, count: 48)
        let count = max(2, Int(Double(samples.count - 1) * Double(fraction)) + 1)
        return Array(samples.prefix(count))
    }

    private func fitCamera() {
        let coords = legs.flatMap { [$0.origin.coordinate, $0.destination.coordinate] }
        guard !coords.isEmpty else { return }
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        let latSpan = lats.max()! - lats.min()!
        let lonSpan = lons.max()! - lons.min()!
        let span = max(max(latSpan, lonSpan), 4)
        let distance = span * 180_000
        cameraPosition = .camera(MapCamera(centerCoordinate: center, distance: distance))
    }
}
