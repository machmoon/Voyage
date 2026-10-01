import XCTest
import SwiftUI
import WidgetKit

/// The widget's entry logic, plus a render of every style, state and family.
///
/// Rendering: set `VOYAGE_WIDGET_SNAPSHOT_DIR` (from xcodebuild,
/// `TEST_RUNNER_VOYAGE_WIDGET_SNAPSHOT_DIR=<dir>`) and each view is written
/// there as a PNG through `ImageRenderer`. Without it the renders still run,
/// so a view that cannot lay out still fails here, but nothing is written.
/// WidgetKit's own chrome (container background, content margins, the
/// island's black capsule, the Lock Screen's vibrant tint) is not drawn by
/// `ImageRenderer`, so the helpers supply a stand-in for each.
@MainActor
final class WidgetSnapshotTests: XCTestCase {
    /// 7:02 PM local, boarding at 7:30: the concepts sheet's sample day.
    private let now: Date = {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = 19; c.minute = 2
        return Calendar.current.date(from: c)!
    }()

    private var scheduled: WidgetSnapshot.ScheduledLeg {
        let departure = now.addingTimeInterval(28 * 60)
        return .init(originCode: "SFO", destinationCode: "LAX", destinationCity: "Los Angeles",
                     flightNumber: "VOY 741", departure: departure,
                     boardingOpens: departure.addingTimeInterval(-600),
                     boardingCloses: departure.addingTimeInterval(900),
                     duration: 85 * 60, courseDegrees: 139)
    }

    private var quick: WidgetSnapshot.QuickRoute {
        .init(originCode: "SFO", destinationCode: "SJC", duration: 25 * 60,
              destinationCity: "San Jose", courseDegrees: 129)
    }

    /// 8:13 PM, 43 minutes flown, 42 left.
    private var active: WidgetSnapshot.ActiveLeg {
        let takeoff = now.addingTimeInterval(28 * 60)
        return .init(originCode: "SFO", destinationCode: "LAX", destinationCity: "Los Angeles",
                     departure: takeoff, arrival: takeoff.addingTimeInterval(85 * 60),
                     seat: "12A", bags: 3, courseDegrees: 139)
    }

    private var flyingAt: Date { active.departure.addingTimeInterval(43 * 60) }

    // MARK: Entry logic

    func testNoSnapshotIsReady() {
        let glance = NextFlightEntry(date: now, snapshot: .empty).glance
        XCTAssertEqual(glance.mode, .ready)
        XCTAssertTrue(glance.tapDeparts)
        XCTAssertFalse(glance.hasRoute)
    }

    func testPrecedenceIsFlightThenBookingThenQuickRoute() {
        let all = WidgetSnapshot(scheduled: scheduled, quickRoute: quick, active: active)
        XCTAssertEqual(NextFlightEntry(date: flyingAt, snapshot: all).glance.mode, .flying)
        XCTAssertEqual(NextFlightEntry(date: active.arrival, snapshot: all).glance.mode, .ready,
                       "landed and the booking's window has closed")

        let booked = WidgetSnapshot(scheduled: scheduled, quickRoute: quick)
        XCTAssertEqual(NextFlightEntry(date: now, snapshot: booked).glance.mode, .scheduled(boarding: false))
        XCTAssertEqual(NextFlightEntry(date: scheduled.boardingOpens, snapshot: booked).glance.mode,
                       .scheduled(boarding: true))
        XCTAssertEqual(NextFlightEntry(date: scheduled.boardingCloses, snapshot: booked).glance.mode, .ready)
        XCTAssertFalse(NextFlightEntry(date: now, snapshot: booked).glance.tapDeparts,
                       "a booked flight opens Home; it does not start another")
    }

    func testFlyingGlanceCountsFromTheLeg() {
        let glance = NextFlightEntry(date: flyingAt, snapshot: WidgetSnapshot(active: active)).glance
        XCTAssertEqual(glance.minutesLeft, 42)
        XCTAssertEqual(glance.minutesFlown, 43)
        XCTAssertEqual(glance.progress, 43.0 / 85.0, accuracy: 0.001)
    }

    func testInFlightTimelineHasAnEntryEveryMinuteToArrival() {
        let dates = NextFlightProvider.entryDates(for: WidgetSnapshot(active: active), now: flyingAt)
        XCTAssertEqual(dates.first, flyingAt)
        XCTAssertEqual(dates.last, active.arrival)
        XCTAssertEqual(dates.count, 43, "now, the 41 whole minutes before arrival, arrival")
        XCTAssertEqual(Set(dates).count, dates.count)
    }

    func testSnapshotStoreReportsChangesOnly() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "WidgetSnapshotTests"))
        defaults.removePersistentDomain(forName: "WidgetSnapshotTests")
        let snapshot = WidgetSnapshot(scheduled: scheduled, quickRoute: quick)
        XCTAssertTrue(WidgetSnapshotStore.save(snapshot, to: defaults))
        XCTAssertFalse(WidgetSnapshotStore.save(snapshot, to: defaults), "unchanged: no reload")
        XCTAssertTrue(WidgetSnapshotStore.setActive(active, in: defaults))
        XCTAssertEqual(WidgetSnapshotStore.load(from: defaults).scheduled, scheduled, "setActive keeps Home's part")
    }

    func testOlderSnapshotStillDecodes() throws {
        let old = #"{"scheduled":null,"quickRoute":{"originCode":"SFO","destinationCode":"LAX","duration":1500}}"#
        let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(old.utf8))
        XCTAssertEqual(snapshot.quickRoute?.destinationCode, "LAX")
        XCTAssertNil(snapshot.active)
    }

    func testTakeOffRequestIsConsumedOnceAndOnlyWhileFresh() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "TakeOffRequestTests"))
        defaults.removePersistentDomain(forName: "TakeOffRequestTests")
        TakeOffRequest.post(at: now, to: defaults)
        XCTAssertTrue(TakeOffRequest.consume(at: now.addingTimeInterval(5), from: defaults))
        XCTAssertFalse(TakeOffRequest.consume(at: now.addingTimeInterval(6), from: defaults))
        TakeOffRequest.post(at: now, to: defaults)
        XCTAssertFalse(TakeOffRequest.consume(at: now.addingTimeInterval(TakeOffRequest.freshness + 1),
                                              from: defaults),
                       "a tap from minutes ago must not start a flight now")
    }

    func testCardStatusFollowsTheActivityState() {
        let attributes = FlightActivityAttributes(originCode: "SFO", destinationCode: "JFK",
                                                  viaCode: nil, flightNumber: "VOY 741")
        var state = FlightActivityAttributes.ContentState(
            phaseCaption: "Cruise · deep work", phaseSymbol: "airplane",
            arrival: now.addingTimeInterval(1800), departure: now.addingTimeInterval(-600),
            legNumber: 1, legCount: 1, concluded: false)
        XCTAssertEqual(FlightCard(attributes: attributes, state: state, isStale: false, now: now).status, .live)
        XCTAssertEqual(FlightCard(attributes: attributes, state: state, isStale: true, now: now).status, .ended)
        state.graceDeadline = now.addingTimeInterval(30)
        let returning = FlightCard(attributes: attributes, state: state, isStale: false, now: now)
        XCTAssertEqual(returning.status, .returning(deadline: now.addingTimeInterval(30)))
        XCTAssertEqual(returning.caption, "Return to Voyage")
        state.concluded = true
        state.phaseSymbol = "airplane.arrival"
        XCTAssertEqual(FlightCard(attributes: attributes, state: state, isStale: true, now: now).status, .landed)
    }

    // MARK: Renders

    func testRenderEveryStyle() throws {
        let states: [(String, NextFlightEntry)] = [
            ("next", NextFlightEntry(date: now, snapshot: WidgetSnapshot(scheduled: scheduled, quickRoute: quick))),
            ("ready", NextFlightEntry(date: now, snapshot: WidgetSnapshot(quickRoute: quick))),
            ("flying", NextFlightEntry(date: flyingAt, snapshot: WidgetSnapshot(quickRoute: quick, active: active))),
        ]
        for style in [VoyageWidgetStyle.horizon, .flapboard, .orbit, .heading] {
            let schemes: [ColorScheme] = (style == .orbit || style == .heading) ? [.light, .dark] : [.light]
            for scheme in schemes {
                for (state, base) in states {
                    var entry = base
                    entry.style = style
                    let name = "\(style.rawValue)-\(state)" + (schemes.count > 1 ? "-\(scheme == .dark ? "dark" : "light")" : "")
                    try render("w-\(name)", homeRow(entry), scheme: scheme)
                }
            }
            for (state, base) in states {
                var entry = base
                entry.style = style
                try render("l-\(style.rawValue)-\(state)", lockRow(entry), scheme: .dark)
            }
        }
    }

    func testRenderLiveActivity() throws {
        let t = Date.now
        func card(_ status: FlightCard.Status, caption: String) -> FlightCard {
            FlightCard(origin: "SFO", destination: "LAX", caption: caption,
                       departure: t.addingTimeInterval(-43 * 60), arrival: t.addingTimeInterval(42 * 60),
                       status: status)
        }
        let live = card(.live, caption: "Cruise · deep work")
        let returning = card(.returning(deadline: t.addingTimeInterval(24)), caption: "Return to Voyage")
        let landed = card(.landed, caption: "Landed in Los Angeles")

        for (name, item) in [("live", live), ("returning", returning), ("landed", landed)] {
            try render("activity-lock-\(name)", FlightLockScreenView(card: item)
                .frame(width: 370)
                .clipShape(RoundedRectangle(cornerRadius: 22)), scheme: .dark)
        }
        try render("activity-island-expanded", VStack(spacing: 8) {
            HStack {
                FlightIslandPlace(card: live)
                Spacer()
                FlightIslandCaption(card: live)
            }
            FlightIslandBottom(card: live)
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .frame(width: 370)
        .background(.black, in: RoundedRectangle(cornerRadius: 44)), scheme: .dark)
        try render("activity-island-compact", HStack {
            FlightIslandGlyph(card: live)
            Spacer()
            FlightCountdown(card: live, size: 14).frame(maxWidth: 56)
        }
        .padding(.horizontal, 14)
        .frame(width: 250, height: 37)
        .background(.black, in: Capsule()), scheme: .dark)
        try render("activity-island-minimal", FlightIslandMinimal(card: live)
            .padding(4)
            .frame(width: 37, height: 37)
            .background(.black, in: Circle()), scheme: .dark)
    }

    // MARK: Stand-ins for WidgetKit's chrome

    /// Small and medium side by side on a Home Screen wallpaper, at the
    /// iPhone 17's widget sizes (170 and 364 x 170 points).
    private func homeRow(_ entry: NextFlightEntry) -> some View {
        HStack(spacing: 18) {
            homeTile(entry, family: .systemSmall, width: 170)
            homeTile(entry, family: .systemMedium, width: 364)
        }
        .padding(18)
        .background(LinearGradient(colors: [hex(0xF2EEF6), hex(0x9FB7EA)], startPoint: .topLeading,
                                   endPoint: .bottomTrailing))
    }

    private func homeTile(_ entry: NextFlightEntry, family: WidgetFamily, width: CGFloat) -> some View {
        NextFlightWidgetView(entry: entry, family: family)
            .padding(16)
            .frame(width: width, height: 170)
            .background { WidgetBackground(entry: entry, family: family) }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Rectangular and circular on a night Lock Screen, white as the system's
    /// vibrant rendering draws them.
    private func lockRow(_ entry: NextFlightEntry) -> some View {
        HStack(spacing: 14) {
            NextFlightWidgetView(entry: entry, family: .accessoryRectangular)
                .frame(width: 160, height: 72)
            NextFlightWidgetView(entry: entry, family: .accessoryCircular)
                .frame(width: 72, height: 72)
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(LinearGradient(colors: [hex(0x0D1531), hex(0x050713)], startPoint: .top, endPoint: .bottom))
    }

    private func render(_ name: String, _ view: some View, scheme: ColorScheme) throws {
        let renderer = ImageRenderer(content: view
            .environment(\.colorScheme, scheme)
            .environment(\.frozenTimeline, true))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage, "\(name) did not render")
        XCTAssertGreaterThan(image.size.width, 0)
        guard let dir = ProcessInfo.processInfo.environment["VOYAGE_WIDGET_SNAPSHOT_DIR"],
              !dir.isEmpty else { return }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try XCTUnwrap(image.pngData()).write(to: url)
    }
}

/// What each style hands `containerBackground`, which `ImageRenderer` drops.
private struct WidgetBackground: View {
    var entry: NextFlightEntry
    var family: WidgetFamily
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        switch entry.style {
        case .horizon: entry.glance.isFlying ? HorizonWidget.night : HorizonWidget.dusk
        case .flapboard: FlapboardWidget.background
        case .orbit: OrbitScene(palette: scheme == .dark ? .dark : .light, glance: entry.glance,
                                medium: family == .systemMedium)
        case .heading:
            let p = scheme == .dark ? HeadingWidget.Palette.dark : .light
            RadialGradient(colors: [p.face, p.bg], center: UnitPoint(x: 0.3, y: 0.2), startRadius: 0, endRadius: 200)
        }
    }
}
