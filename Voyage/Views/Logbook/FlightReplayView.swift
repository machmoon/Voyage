import AVFoundation
import Combine
import CoreText
import MapKit
import SwiftUI
import UIKit

/// Map-first replay for either one flight or an automatically assembled week.
/// Every segment uses the same Voyage route ink and plays in chronological order.
struct FlightReplayView: View {
    private let replayEntries: [LogbookEntry]
    private let title: String
    private let flightAPI: any FlightDataProviding
    private let replayRoutes: [[CLLocationCoordinate2D]]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var playbackClock = ReplayDisplayLinkClock()
    @State private var progress = 0.0
    @State private var isPlaying = true
    @State private var replaySpeed = 1.0
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var previousClockTick: Date?
    @State private var milestoneText: String?
    @State private var milestoneID = UUID()
    @State private var sharePNG: Data?
    @State private var videoURL: URL?
    @State private var isExportingVideo = false
    @State private var exportError: String?
    @State private var showsStats = true

    init(entry: LogbookEntry, flightAPI: any FlightDataProviding = FlightDataAPI.shared) {
        replayEntries = [entry]
        title = "Flight \(entry.flightNumber)"
        self.flightAPI = flightAPI
        replayRoutes = Self.makeRoutes(for: [entry], flightAPI: flightAPI)
    }

    init(entries: [LogbookEntry], title: String, flightAPI: any FlightDataProviding = FlightDataAPI.shared) {
        let completedEntries = entries.filter(\.completed).sorted { $0.date < $1.date }
        replayEntries = completedEntries
        self.title = title
        self.flightAPI = flightAPI
        replayRoutes = Self.makeRoutes(for: completedEntries, flightAPI: flightAPI)
    }

    private var activeIndex: Int {
        guard !replayEntries.isEmpty else { return 0 }
        if progress >= 1 { return replayEntries.count - 1 }
        return min(replayEntries.count - 1, Int(progress * Double(replayEntries.count)))
    }

    private var activeEntry: LogbookEntry? {
        replayEntries.indices.contains(activeIndex) ? replayEntries[activeIndex] : nil
    }

    private var segmentProgress: Double {
        guard !replayEntries.isEmpty else { return 0 }
        if progress >= 1 { return 1 }
        return (progress * Double(replayEntries.count)).truncatingRemainder(dividingBy: 1)
    }

    private var activeSnapshot: FlightReplaySnapshot? {
        activeEntry.map { flightAPI.replaySnapshot(for: $0, progress: segmentProgress) }
    }

    /// Long enough to read each flight, capped so a busy week remains a recap.
    private var replayDuration: TimeInterval {
        min(60, max(14, Double(replayEntries.count) * 5))
    }

    private var liveMiles: Int {
        guard !replayEntries.isEmpty else { return 0 }
        let completed = replayEntries.prefix(activeIndex).reduce(0.0) { $0 + $1.miles }
        return Int((completed + (activeEntry?.miles ?? 0) * segmentProgress).rounded())
    }

    private var liveFocus: TimeInterval {
        guard !replayEntries.isEmpty else { return 0 }
        let completed = replayEntries.prefix(activeIndex).reduce(0.0) { $0 + $1.focusSeconds }
        return completed + (activeEntry?.focusSeconds ?? 0) * segmentProgress
    }

    /// The three closing highlights, shown only once the replay reaches the end.
    /// Deliberately capped at three so each one keeps its weight.
    private var recapHighlights: [(value: String, label: String)] {
        guard progress >= 1, !replayEntries.isEmpty else { return [] }
        let longest = replayEntries.max { $0.miles < $1.miles }
        let deepest = replayEntries.max { $0.focusSeconds < $1.focusSeconds }
        let destinations = Set(replayEntries.map(\.destinationCode)).count
        return [
            (longest.map { "\($0.originCode)–\($0.destinationCode)" } ?? "—", "LONGEST FLIGHT"),
            (deepest?.focusSeconds.shortDurationText ?? "—", "DEEPEST FOCUS"),
            ("\(destinations)", destinations == 1 ? "DESTINATION" : "DESTINATIONS")
        ]
    }

    private var completedFlights: Int {
        guard !replayEntries.isEmpty else { return 0 }
        let completed = floor(progress * Double(replayEntries.count) + 0.000_001)
        return min(replayEntries.count, Int(completed))
    }

    var body: some View {
        ZStack {
            replayMap
                .ignoresSafeArea()

            LinearGradient(
                colors: [Theme.ink.opacity(0.74), .clear, Theme.ink.opacity(0.90)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                replayHeader
                Spacer()
                if let milestoneText {
                    milestoneBanner(milestoneText)
                        .padding(.bottom, 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if activeEntry != nil {
                    activityCard
                } else {
                    emptyCard
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .background(Theme.ink)
        .preferredColorScheme(.dark)
        .onReceive(playbackClock.$tick.dropFirst()) { tick in advanceReplay(at: tick) }
        .onAppear {
            restart()
            updatePlaybackClock()
            sharePNG = ReplaySummaryRenderer.pngData(entries: replayEntries, title: title)
        }
        .onDisappear { playbackClock.stop() }
        .onChange(of: isPlaying) { _, _ in updatePlaybackClock() }
        .onChange(of: scenePhase) { _, _ in updatePlaybackClock() }
        .alert("Couldn’t export replay", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "Please try again.")
        }
    }

    private var replayMap: some View {
        Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {
            ForEach(Array(replayEntries.enumerated()), id: \.offset) { index, entry in
                let coordinates = replayRoutes[index]
                if coordinates.count >= 2 {
                    MapPolyline(coordinates: coordinates, contourStyle: .geodesic)
                        .stroke(.white.opacity(0.18),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }

                let revealed = revealedCoordinates(for: index)
                if revealed.count >= 2 {
                    MapPolyline(coordinates: revealed, contourStyle: .geodesic)
                        .stroke(Theme.accent,
                                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }

                Annotation("", coordinate: entry.origin.coordinate) {
                    milestone(entry.origin.code, reached: progress >= segmentStart(for: index))
                }
                .annotationTitles(.hidden)

                Annotation("", coordinate: entry.destination.coordinate) {
                    milestone(entry.destination.code, reached: progress >= segmentEnd(for: index))
                }
                .annotationTitles(.hidden)
            }

            if let snapshot = activeSnapshot {
                Annotation("", coordinate: snapshot.coordinate) {
                    aircraftMarker(course: snapshot.course)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls { MapCompass() }
    }

    private var replayHeader: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Close trip replay")

            VStack(alignment: .leading, spacing: 2) {
                Text("TRIP REPLAY")
                    .font(.system(size: 10, weight: .black))
                    .kerning(2.2)
                    .foregroundStyle(Theme.accent)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }

            Spacer()

            Button {
                withAnimation(.smooth(duration: 0.28)) { showsStats.toggle() }
                Haptics.tap()
            } label: {
                Image(systemName: showsStats ? "chart.bar.fill" : "chart.bar")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel(showsStats ? "Hide replay statistics" : "Show replay statistics")

            Button { updateCamera() } label: {
                Image(systemName: "scope")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Recenter replay route")

            if let sharePNG {
                ShareLink(
                    item: ReceiptShareItem(pngData: sharePNG),
                    preview: SharePreview("\(title) on Voyage")
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Share trip replay summary")
            }

            Text(replayEntries.isEmpty ? "—" : "\(activeIndex + 1)/\(replayEntries.count)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.82))
                .padding(.horizontal, 11)
                .frame(height: 38)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var activityCard: some View {
        if let entry = activeEntry {
            VStack(spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(entry.originCode)  →  \(entry.destinationCode)")
                            .font(.system(size: 25, weight: .black, design: .monospaced))
                        Text("\(entry.origin.city) to \(entry.destination.city) · \(entry.date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                    }
                    Spacer()
                    Button { cycleReplaySpeed() } label: {
                        Text("\(Int(replaySpeed))×")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 30)
                            .background(.white.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Playback speed, \(Int(replaySpeed)) times")
                    .accessibilityHint("Cycles between one, two, and four times speed")
                }

                if showsStats {
                    if replayEntries.count > 1 {
                        flightTimeline
                    }

                    let recap = recapHighlights
                    HStack(spacing: 0) {
                        if recap.isEmpty {
                            activityStat("\(liveMiles.formatted())", "MILES FLOWN")
                            activityStat(liveFocus.shortDurationText, "FOCUS EARNED")
                            activityStat("\(completedFlights)/\(replayEntries.count)", "FLIGHTS DONE")
                        } else {
                            ForEach(recap, id: \.label) { highlight in
                                activityStat(highlight.value, highlight.label)
                            }
                        }
                    }
                    .animation(.smooth(duration: 0.3), value: progress >= 1)
                }

                VStack(spacing: 7) {
                    Slider(value: $progress, in: 0...1, onEditingChanged: { editing in
                        if editing {
                            isPlaying = false
                            previousClockTick = nil
                        } else {
                            updateCamera()
                        }
                    })
                    .tint(Theme.accent)
                    .accessibilityLabel("Trip replay progress")

                    HStack {
                        Text(replayEntries.first?.date.formatted(.dateTime.month(.abbreviated).day()) ?? "")
                        Spacer()
                        Text(progress >= 1 ? "WEEK COMPLETE" : "FLIGHT \(activeIndex + 1) OF \(replayEntries.count)")
                            .foregroundStyle(Theme.accent)
                        Spacer()
                        Text(replayEntries.last?.date.formatted(.dateTime.month(.abbreviated).day()) ?? "")
                    }
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .kerning(0.7)
                    .foregroundStyle(.white.opacity(0.5))
                }

                HStack(spacing: 12) {
                    Button { previousFlight() } label: {
                        Image(systemName: "backward.end.fill")
                            .frame(width: 42, height: 42)
                            .background(.white.opacity(0.10), in: Circle())
                    }
                    .accessibilityLabel("Previous flight")

                    Button {
                        if progress >= 1 { progress = 0; updateCamera() }
                        isPlaying.toggle()
                        previousClockTick = nil
                        Haptics.tap()
                    } label: {
                        Label(isPlaying ? "Pause" : "Play",
                              systemImage: isPlaying ? "pause.fill" : "play.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Theme.accent, in: Capsule())
                    }
                    .accessibilityLabel(isPlaying ? "Pause trip replay" : "Play trip replay")

                    Button { nextFlight() } label: {
                        Image(systemName: "forward.end.fill")
                            .frame(width: 42, height: 42)
                            .background(.white.opacity(0.10), in: Circle())
                    }
                    .accessibilityLabel("Next flight")
                }
                .buttonStyle(.plain)

                videoExportButton
            }
            .foregroundStyle(.white)
            .padding(20)
            .background(Theme.surfaceDark.opacity(0.94),
                        in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var videoExportButton: some View {
        if let videoURL {
            ShareLink(item: videoURL, preview: SharePreview("\(title) replay")) {
                Label("Share replay video", systemImage: "square.and.arrow.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(.white.opacity(0.07), in: Capsule())
            }
        } else {
            Button {
                exportVideo()
            } label: {
                HStack(spacing: 8) {
                    if isExportingVideo {
                        ProgressView().controlSize(.small).tint(.white)
                        Text("Rendering replay…")
                    } else {
                        Image(systemName: "film")
                        Text("Export replay video")
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.78))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(.white.opacity(0.07), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isExportingVideo)
        }
    }

    private var flightTimeline: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(Array(replayEntries.enumerated()), id: \.offset) { index, entry in
                        Button {
                            jump(to: index)
                        } label: {
                            Text("\(entry.originCode)–\(entry.destinationCode)")
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                .foregroundStyle(index == activeIndex ? .white : .white.opacity(0.62))
                                .padding(.horizontal, 10)
                                .frame(height: 27)
                                .background(index == activeIndex ? Theme.accent : .white.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .id(index)
                    }
                }
            }
            .onChange(of: activeIndex) { _, index in
                withAnimation(.smooth(duration: 0.3)) { proxy.scrollTo(index, anchor: .center) }
            }
        }
    }

    private var emptyCard: some View {
        ContentUnavailableView(
            "No completed flights",
            systemImage: "airplane",
            description: Text("Complete a flight this week to create a replay.")
        )
        .foregroundStyle(.white)
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func activityStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(label)
                .font(.system(size: 8, weight: .black))
                .kerning(1)
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func milestone(_ code: String, reached: Bool) -> some View {
        VStack(spacing: 4) {
            Circle()
                .fill(reached ? Theme.accent : Theme.surfaceSubtle)
                .frame(width: 12, height: 12)
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            Text(code)
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black.opacity(0.70), in: Capsule())
        }
    }

    private func milestoneBanner(_ text: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(Theme.accent)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Theme.surfaceDark.opacity(0.94), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.10), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func aircraftMarker(course: Double) -> some View {
        ZStack {
            Circle()
                .fill(Theme.accent.opacity(0.20))
                .frame(width: 48, height: 48)
            Circle()
                .fill(Theme.accent)
                .frame(width: 30, height: 30)
            Image(systemName: "airplane")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(.white)
                // The SF Symbol points east at 0°. The map stays north-up, so
                // converting true course to screen rotation requires -90°.
                .rotationEffect(.degrees(course - 90))
        }
        .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
        .accessibilityLabel("Replay aircraft")
    }

    private func revealedCoordinates(for index: Int) -> [CLLocationCoordinate2D] {
        let coordinates = replayRoutes[index]
        guard coordinates.count > 1 else { return coordinates }
        let reveal: Double
        if index < activeIndex { reveal = 1 }
        else if index == activeIndex { reveal = segmentProgress }
        else { reveal = 0 }
        guard reveal > 0 else { return [] }
        let lastIndex = min(coordinates.count - 1,
                            max(1, Int((Double(coordinates.count - 1) * reveal).rounded(.up))))
        return Array(coordinates.prefix(lastIndex + 1))
    }

    private func segmentStart(for index: Int) -> Double {
        guard !replayEntries.isEmpty else { return 0 }
        return Double(index) / Double(replayEntries.count)
    }

    private func segmentEnd(for index: Int) -> Double {
        guard !replayEntries.isEmpty else { return 1 }
        return Double(index + 1) / Double(replayEntries.count)
    }

    private func restart() {
        progress = 0
        previousClockTick = nil
        milestoneText = nil
        isPlaying = !replayEntries.isEmpty
        updateCamera()
        Haptics.tap()
    }

    private func updatePlaybackClock() {
        let shouldRun = isPlaying && scenePhase == .active
        playbackClock.setActive(shouldRun)
        if !shouldRun { previousClockTick = nil }
    }

    private func jump(to index: Int) {
        guard replayEntries.indices.contains(index) else { return }
        progress = segmentStart(for: index)
        isPlaying = false
        previousClockTick = nil
        updateCamera()
        Haptics.tap()
    }

    private func previousFlight() {
        let target = segmentProgress < 0.12 ? max(0, activeIndex - 1) : activeIndex
        jump(to: target)
    }

    private func nextFlight() {
        guard !replayEntries.isEmpty else { return }
        if activeIndex == replayEntries.count - 1 {
            progress = 1
            isPlaying = false
            previousClockTick = nil
            updateCamera()
        } else {
            jump(to: activeIndex + 1)
        }
    }

    private func advanceReplay(at tick: Date) {
        guard isPlaying, !replayEntries.isEmpty else {
            previousClockTick = nil
            return
        }
        let previousIndex = activeIndex
        let elapsed = previousClockTick.map { min(0.1, max(0, tick.timeIntervalSince($0))) } ?? 0
        previousClockTick = tick
        progress = min(1, progress + (elapsed * replaySpeed) / replayDuration)
        if activeIndex != previousIndex {
            Haptics.softTick()
            updateCamera()
            let destination = replayEntries[previousIndex].destinationCode
            showMilestone("\(destination) collected · Flight \(previousIndex + 1) complete")
        }
        if progress >= 1 {
            isPlaying = false
            previousClockTick = nil
            let completion = replayEntries.count == 1
                ? "Flight replay complete · \(replayEntries[0].destinationCode) collected"
                : "Week complete · \(replayEntries.count) flights replayed"
            showMilestone(completion)
            Haptics.success()
        }
    }

    private func cycleReplaySpeed() {
        switch replaySpeed {
        case 1: replaySpeed = 2
        case 2: replaySpeed = 4
        default: replaySpeed = 1
        }
        previousClockTick = nil
        Haptics.tap()
    }

    private func showMilestone(_ text: String) {
        let id = UUID()
        milestoneID = id
        withAnimation(.snappy(duration: 0.28)) {
            milestoneText = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            guard milestoneID == id else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                milestoneText = nil
            }
        }
    }

    private func exportVideo() {
        guard !isExportingVideo, !replayEntries.isEmpty else { return }
        isExportingVideo = true
        isPlaying = false
        Task {
            do {
                videoURL = try await ReplayVideoExporter.export(entries: replayEntries, title: title)
                Haptics.success()
            } catch {
                exportError = error.localizedDescription
                Haptics.warning()
            }
            isExportingVideo = false
        }
    }

    private func updateCamera() {
        guard replayRoutes.indices.contains(activeIndex) else { return }
        let coordinates = replayRoutes[activeIndex]
        guard let first = coordinates.first else { return }
        var routeRect = MKMapRect(origin: MKMapPoint(first), size: .init(width: 1, height: 1))
        for coordinate in coordinates.dropFirst() {
            let point = MKMapPoint(coordinate)
            routeRect = routeRect.union(MKMapRect(origin: point, size: .init(width: 1, height: 1)))
        }
        let horizontalPadding = max(routeRect.size.width * 0.24, 24_000)
        let verticalPadding = max(routeRect.size.height * 0.30, 24_000)
        routeRect = routeRect.insetBy(dx: -horizontalPadding, dy: -verticalPadding)
        withAnimation(.smooth(duration: 0.45)) {
            cameraPosition = .rect(routeRect)
        }
    }

    private static func makeRoutes(
        for entries: [LogbookEntry],
        flightAPI: any FlightDataProviding
    ) -> [[CLLocationCoordinate2D]] {
        entries.map { flightAPI.routeCoordinates(for: $0) }
    }
}

/// A display-synchronized replay clock avoids the uneven delivery of a
/// run-loop timer when MapKit is decoding tiles or SwiftUI is laying out the
/// activity card. Playback remains time-based, but presentation lands on
/// actual display refreshes for visibly steadier aircraft motion.
@MainActor
private final class ReplayDisplayLinkClock: NSObject, ObservableObject {
    @Published private(set) var tick = Date()
    private var displayLink: CADisplayLink?

    func setActive(_ active: Bool) {
        if active {
            if displayLink == nil {
                let link = CADisplayLink(target: self, selector: #selector(didRefresh(_:)))
                link.preferredFrameRateRange = CAFrameRateRange(
                    minimum: 30,
                    maximum: 60,
                    preferred: 60
                )
                link.add(to: .main, forMode: .common)
                displayLink = link
            }
            displayLink?.isPaused = false
        } else {
            displayLink?.isPaused = true
        }
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func didRefresh(_ link: CADisplayLink) {
        tick = Date(timeIntervalSinceReferenceDate: link.targetTimestamp)
    }
}

// MARK: - Shareable portrait recap

private struct ReplaySummaryCard: View {
    let entries: [LogbookEntry]
    let title: String

    private var miles: Int { Int(LogbookStats.totalMiles(entries)) }
    private var focus: TimeInterval { entries.reduce(0) { $0 + $1.focusSeconds } }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.surfaceSubtle, Theme.ink],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Theme.accent.opacity(0.22), .clear],
                           center: .topLeading, startRadius: 10, endRadius: 330)

            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("VOYAGE")
                            .font(.system(size: 10, weight: .black))
                            .kerning(2.4)
                            .foregroundStyle(Theme.accent)
                        Text("TRIP REPLAY")
                            .font(.system(size: 22, weight: .black))
                    }
                    Spacer()
                    Image(systemName: "airplane")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }

                Text(title)
                    .font(.system(size: 38, weight: .black))

                HStack(spacing: 0) {
                    summaryStat("\(entries.count)", "FLIGHTS")
                    summaryStat("\(miles.formatted())", "MILES")
                    summaryStat(focus.shortDurationText, "FOCUS")
                }

                VStack(spacing: 0) {
                    ForEach(Array(entries.prefix(7).enumerated()), id: \.offset) { index, entry in
                        HStack {
                            Circle()
                                .fill(Theme.accent)
                                .frame(width: 8, height: 8)
                            Text("\(entry.originCode)  →  \(entry.destinationCode)")
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                            Spacer()
                            Text(entry.date.formatted(.dateTime.weekday(.abbreviated)))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .frame(height: 38)
                        if index < min(entries.count, 7) - 1 {
                            Divider().overlay(.white.opacity(0.10))
                        }
                    }
                    if entries.count > 7 {
                        Text("+ \(entries.count - 7) more flights")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 12)
                    }
                }
                .padding(16)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                Spacer()

                Text("FOCUS, FLOWN")
                    .font(.system(size: 10, weight: .black))
                    .kerning(2)
                    .foregroundStyle(.white.opacity(0.42))
            }
            .foregroundStyle(.white)
            .padding(26)
        }
        .frame(width: 390, height: 520)
    }

    private func summaryStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(label)
                .font(.system(size: 8, weight: .black))
                .kerning(1)
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum ReplaySummaryRenderer {
    @MainActor
    static func pngData(entries: [LogbookEntry], title: String) -> Data? {
        guard !entries.isEmpty else { return nil }
        let renderer = ImageRenderer(content: ReplaySummaryCard(entries: entries, title: title))
        renderer.scale = 3
        return renderer.uiImage?.pngData()
    }
}

// MARK: - Offline portrait video export

private enum ReplayVideoExporter {
    private static let size = CGSize(width: 1080, height: 1920)
    private static let fps: Int32 = 30
    private static let frameCount = 180
    private static let routeBlue = UIColor(red: 94 / 255, green: 143 / 255, blue: 1, alpha: 1)

    enum ExportError: LocalizedError {
        case noRoutes, snapshot, writer, pixelBuffer

        var errorDescription: String? {
            switch self {
            case .noRoutes: return "There are no completed routes to export."
            case .snapshot: return "The map could not be prepared for export."
            case .writer: return "The replay video could not be encoded."
            case .pixelBuffer: return "A video frame could not be created."
            }
        }
    }

    static func export(entries: [LogbookEntry], title: String) async throws -> URL {
        let routes = entries.map(routeCoordinates)
        guard routes.contains(where: { $0.count >= 2 }) else { throw ExportError.noRoutes }

        let options = MKMapSnapshotter.Options()
        options.size = size
        options.mapType = .standard
        options.pointOfInterestFilter = .excludingAll
        options.showsBuildings = false
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        options.mapRect = mapRect(for: routes)
        let snapshot = try await MKMapSnapshotter(options: options).start()
        guard let baseImage = snapshot.image.cgImage else { throw ExportError.snapshot }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Voyage-Trip-Replay-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 7_000_000]
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ]
        )
        guard writer.canAdd(input) else { throw ExportError.writer }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ExportError.writer }
        writer.startSession(atSourceTime: .zero)
        guard let pool = adaptor.pixelBufferPool else { throw ExportError.pixelBuffer }

        for frame in 0..<frameCount {
            try Task.checkCancellation()
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(4))
            }
            var optionalBuffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer) == kCVReturnSuccess,
                  let buffer = optionalBuffer else { throw ExportError.pixelBuffer }
            let globalProgress = Double(frame) / Double(frameCount - 1)
            drawFrame(
                buffer,
                snapshot: snapshot,
                baseImage: baseImage,
                entries: entries,
                routes: routes,
                title: title,
                progress: globalProgress
            )
            let time = CMTime(value: CMTimeValue(frame), timescale: fps)
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw writer.error ?? ExportError.writer
            }
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? ExportError.writer }
        return url
    }

    private static func routeCoordinates(for entry: LogbookEntry) -> [CLLocationCoordinate2D] {
        FlightDataAPI.shared.routeCoordinates(for: entry)
    }

    private static func mapRect(for routes: [[CLLocationCoordinate2D]]) -> MKMapRect {
        var rect = MKMapRect.null
        for coordinate in routes.flatMap({ $0 }) {
            let point = MKMapPoint(coordinate)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
        }
        let horizontal = max(20_000, rect.size.width * 0.20)
        let vertical = max(20_000, rect.size.height * 0.28)
        return rect.insetBy(dx: -horizontal, dy: -vertical)
    }

    private static func drawFrame(
        _ buffer: CVPixelBuffer,
        snapshot: MKMapSnapshotter.Snapshot,
        baseImage: CGImage,
        entries: [LogbookEntry],
        routes: [[CLLocationCoordinate2D]],
        title: String,
        progress: Double
    ) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let address = CVPixelBufferGetBaseAddress(buffer),
              let context = CGContext(
                data: address,
                width: Int(size.width),
                height: Int(size.height),
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              ) else { return }

        let count = max(1, entries.count)
        let scaled = min(Double(count) - 0.000_001, progress * Double(count))
        let activeIndex = progress >= 1 ? count - 1 : Int(scaled)
        let localProgress = progress >= 1 ? 1 : scaled - floor(scaled)
        let entry = entries[activeIndex]
        let flight = FlightDataAPI.shared.replaySnapshot(for: entry, progress: localProgress)
        let aircraftTop = snapshot.point(for: flight.coordinate)
        let aircraft = bottomPoint(aircraftTop)
        let zoom = 1.52 - 0.10 * sin(progress * .pi)
        let outputCenter = CGPoint(x: size.width / 2, y: size.height * 0.55)

        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        let imageRect = CGRect(
            x: outputCenter.x - aircraft.x * zoom,
            y: outputCenter.y - aircraft.y * zoom,
            width: size.width * zoom,
            height: size.height * zoom
        )
        context.draw(baseImage, in: imageRect)
        context.setFillColor(UIColor.black.withAlphaComponent(0.20).cgColor)
        context.fill(CGRect(origin: .zero, size: size))

        for (index, route) in routes.enumerated() {
            stroke(route, in: context, snapshot: snapshot, aircraft: aircraft,
                   outputCenter: outputCenter, zoom: zoom,
                   color: UIColor.white.withAlphaComponent(0.18), width: 8)
            let reveal = index < activeIndex ? 1 : (index == activeIndex ? localProgress : 0)
            if reveal > 0 {
                let end = max(2, Int(Double(route.count) * reveal))
                stroke(Array(route.prefix(min(route.count, end))), in: context, snapshot: snapshot,
                       aircraft: aircraft, outputCenter: outputCenter, zoom: zoom,
                       color: routeBlue, width: 11)
            }
        }

        drawAircraft(in: context, center: outputCenter, course: flight.course)

        context.setFillColor(UIColor.black.withAlphaComponent(0.68).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: 320))
        context.setFillColor(UIColor.black.withAlphaComponent(0.58).cgColor)
        context.fill(CGRect(x: 0, y: size.height - 210, width: size.width, height: 210))

        drawText("VOYAGE  ·  TRIP REPLAY", at: CGPoint(x: 64, y: size.height - 100),
                 size: 28, weight: .bold, color: routeBlue, context: context)
        drawText(title.uppercased(), at: CGPoint(x: 64, y: size.height - 150),
                 size: 22, weight: .semibold, color: .white, context: context)
        drawText("\(entry.originCode)  →  \(entry.destinationCode)", at: CGPoint(x: 64, y: 205),
                 size: 54, weight: .black, color: .white, context: context)
        drawText("FLIGHT \(activeIndex + 1) OF \(entries.count)   ·   \(Int(progress * 100))%", at: CGPoint(x: 64, y: 135),
                 size: 24, weight: .bold, color: UIColor.white.withAlphaComponent(0.72), context: context)

        context.setFillColor(UIColor.white.withAlphaComponent(0.18).cgColor)
        context.fill(CGRect(x: 64, y: 70, width: size.width - 128, height: 8))
        context.setFillColor(routeBlue.cgColor)
        context.fill(CGRect(x: 64, y: 70, width: (size.width - 128) * progress, height: 8))
    }

    private static func stroke(
        _ coordinates: [CLLocationCoordinate2D],
        in context: CGContext,
        snapshot: MKMapSnapshotter.Snapshot,
        aircraft: CGPoint,
        outputCenter: CGPoint,
        zoom: CGFloat,
        color: UIColor,
        width: CGFloat
    ) {
        guard let first = coordinates.first else { return }
        context.beginPath()
        context.move(to: transformed(bottomPoint(snapshot.point(for: first)), aircraft: aircraft,
                                     outputCenter: outputCenter, zoom: zoom))
        for coordinate in coordinates.dropFirst() {
            context.addLine(to: transformed(bottomPoint(snapshot.point(for: coordinate)), aircraft: aircraft,
                                            outputCenter: outputCenter, zoom: zoom))
        }
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
    }

    private static func bottomPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: size.height - point.y)
    }

    private static func transformed(_ point: CGPoint, aircraft: CGPoint,
                                    outputCenter: CGPoint, zoom: CGFloat) -> CGPoint {
        CGPoint(x: outputCenter.x + (point.x - aircraft.x) * zoom,
                y: outputCenter.y + (point.y - aircraft.y) * zoom)
    }

    private static func drawAircraft(in context: CGContext, center: CGPoint, course: Double) {
        let radians = course * .pi / 180
        let direction = CGVector(dx: sin(radians), dy: cos(radians))
        let side = CGVector(dx: direction.dy, dy: -direction.dx)
        let nose = CGPoint(x: center.x + direction.dx * 38, y: center.y + direction.dy * 38)
        let left = CGPoint(x: center.x - direction.dx * 25 + side.dx * 27,
                           y: center.y - direction.dy * 25 + side.dy * 27)
        let right = CGPoint(x: center.x - direction.dx * 25 - side.dx * 27,
                            y: center.y - direction.dy * 25 - side.dy * 27)
        context.beginPath()
        context.move(to: nose)
        context.addLine(to: left)
        context.addLine(to: right)
        context.closePath()
        context.setFillColor(routeBlue.cgColor)
        context.setShadow(offset: .zero, blur: 22, color: routeBlue.withAlphaComponent(0.6).cgColor)
        context.fillPath()
        context.setShadow(offset: .zero, blur: 0, color: nil)
    }

    private static func drawText(_ text: String, at point: CGPoint, size fontSize: CGFloat,
                                 weight: UIFont.Weight, color: UIColor, context: CGContext) {
        let attributed = NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: color
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = point
        CTLineDraw(line, context)
    }
}
