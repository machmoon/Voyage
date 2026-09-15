import XCTest

/// Drives a paced walkthrough for the marketing reel. Nothing is asserted for
/// its own sake; the pauses exist so a screen recording of this run cuts down
/// to about fifteen seconds without losing a beat mid-animation.
///
/// Record around it with:
///   xcrun simctl io booted recordVideo <out>.mp4
///
/// Runs under `-VoyageDemoFlight`, which squeezes each leg to a minute and the
/// lounge to twenty seconds, so the run actually reaches the arrival flow and
/// the trip replay rather than stopping at cruise.
///
/// Beat sheet (approx, after launch settle):
///   0–6s    Home globe, held long past settling
///   6–12s   Two destinations picked so the route arc visibly redraws
///  12–18s   Seat map, seat taken
///  18–26s   Bags skipped, boarding pass prints, stub torn
///  26–34s   Curtain, takeoff roll, climb through the window
///  34–42s   Map view, satellite
///  42–?     Descent and landing arrive on their own
///     end   Landed, posted to the logbook, trip replay playing
final class DemoReelUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    func testDemoReel() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-VoyageDemoFlight",
        ]
        app.launch()

        dismissLocationPromptIfPresent()

        // The simulator recorder drops frames while the globe warms up, so hold
        // well past the point the view looks settled or the opening shot is
        // missing from the capture entirely.
        _ = app.staticTexts["VOYAGE"].waitForExistence(timeout: 15)
        pause(6.0)

        bookAFlight(in: app)
        pickASeat(in: app)
        boardTheAircraft(in: app)
        flyTheLeg(in: app)
        landAndReplay(in: app)
    }

    /// Boarding-pass close-up: stops immediately after the rip so a screen
    /// recording of it stays short. The full reel runs ~6 minutes, and
    /// `simctl recordVideo` has proven unreliable over that long.
    @MainActor
    func testTearCloseUp() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-VoyageDemoFlight",
        ]
        app.launch()

        dismissLocationPromptIfPresent()
        _ = app.staticTexts["VOYAGE"].waitForExistence(timeout: 15)
        pause(1.0)

        bookAFlight(in: app)
        pickASeat(in: app)

        skipBags(in: app)

        // Hold on the printed pass, tear, then hold on the aftermath. The rip
        // and the frames just after it are what this capture is for.
        // The button's text is "Tear & board"; its accessibility label is
        // "Tear and board" (BoardingPassView.swift:89) and replaces it in the
        // tree, so only the label matches.
        _ = app.buttons["Tear and board"].waitForExistence(timeout: 15)
        pause(3.0)
        _ = tap(app.buttons["Tear and board"], timeout: 4)
        pause(6.0)
    }

    /// The same close-up, torn by sliding a finger across the stub instead of
    /// the button, so the cut's own frames can be reviewed.
    @MainActor
    func testTearSlideCloseUp() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-VoyageDemoFlight",
        ]
        app.launch()

        dismissLocationPromptIfPresent()
        _ = app.staticTexts["VOYAGE"].waitForExistence(timeout: 15)
        pause(1.0)

        bookAFlight(in: app)
        pickASeat(in: app)
        skipBags(in: app)

        _ = app.buttons["Tear and board"].waitForExistence(timeout: 15)
        pause(3.0)
        let stub = app.otherElements["boarding-pass-stub"]
        _ = stub.waitForExistence(timeout: 4)
        let start = stub.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.3))
        let end = stub.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.32))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: 120, thenHoldForDuration: 0.1)
        pause(6.0)
    }

    /// The App Store preview: one booking, paced for a 15 to 30 second clip.
    ///
    /// Driven by `scripts/record_app_preview.sh`, which starts `simctl
    /// recordVideo` the moment this test writes `QA/preview-ready` (just
    /// before launch, so the flyover is on tape) and stops it after the
    /// takeoff hold. Under
    /// `-VoyageShortFlights` the schedule rolls for 28 s with rotation at
    /// about 19 s (`FlightPhaseSchedule.make`), and the leg starts 2 to 3 s
    /// after the tear. Booking takes about 10 s of the 30 s cap, so the clip
    /// ends on the takeoff roll; rotation does not fit alongside the globe
    /// opening, and the globe is the stronger first frame. The hold below
    /// simply outlasts the recording.
    ///
    /// Beat sheet from the first app frame:
    ///   0–2s     Launch flyover into the globe
    ///   2–3.5s   Home globe
    ///   1.5–3s   Destination picked, route arc drawn
    ///   3–8s     Departure zoom, seat map, seat taken
    ///   8–12s    Pass prints, torn
    ///   12–30s   Curtain and takeoff roll (rotation lands after the cap)
    @MainActor
    func testAppPreview() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-VoyageHomeAirport", "SFO",
            "-VoyageShortFlights",
            "-VoyageSkipOnboarding",    // the script uninstalls first, so this is a fresh install
            "-VoyageSceneHour", "10",   // a daylight window whatever the wall clock says
            // The drawn world, whatever the simulator's persisted setting is;
            // the satellite twin can be left on by the settings tour.
            "-windowWorldMode", "illustrated",
            "-realWorldTwinEnabled", "<false/>",
        ]
        // The clip opens on the cold-launch flyover (`LaunchFlyoverView`),
        // which plays once per process, so the recorder has to be running
        // before the app starts. `simctl recordVideo` takes about a second to
        // write its first frame; the script trims the dead lead-in.
        try? "ready".write(to: Self.previewMarker, atomically: true, encoding: .utf8)
        pause(2.0)
        app.launch()

        dismissLocationPromptIfPresent()
        _ = app.staticTexts["VOYAGE"].waitForExistence(timeout: 15)
        pause(0.8)

        let cards = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "destination-"))
        if cards.firstMatch.waitForExistence(timeout: 6) {
            cards.firstMatch.tap()
            pause(1.4)
        }
        _ = tap(app.buttons["depart-now"], timeout: 5)

        // Tighter than `pickASeat`: the reel can linger, a preview cannot.
        _ = app.staticTexts["Choose your seat"].waitForExistence(timeout: 8)
        // Glide from the nose back to the wing, so the airframe is in the shot.
        pause(0.8)
        app.swipeUp(velocity: .slow)
        // Seat C7, the first open Extra Legroom seat, where one slow swipe
        // leaves it. A miss is harmless: the footer then reads "Skip", which
        // assigns the first open seat and the flow carries on.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.41, dy: 0.39)).tap()
        pause(0.6)
        // Coordinate taps from here on. Every element query snapshots the
        // seat map's accessibility tree (about 150 seats), which cost a second
        // a lookup and left the clip holding on a still seat map for five.
        // Footer button: "Continue", labelled "Take seat C7".
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.908)).tap()
        skipBags(in: app)

        // Slide along the tear line rather than pressing the button, so the
        // clip shows the cut. The stub sits at about 61% of the screen height
        // once the pass has printed; the drag covers the cut span with margin.
        _ = app.buttons["Tear and board"].waitForExistence(timeout: 12)
        let cutStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.615))
        let cutEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.62))
        cutStart.press(forDuration: 0.05, thenDragTo: cutEnd, withVelocity: 140, thenHoldForDuration: 0.1)
        pause(26.0)
        try? FileManager.default.removeItem(at: Self.previewMarker)
    }

    /// Host path, the same way `ScreenshotTourUITests.qaDirectory` reaches the
    /// repo from inside the simulator.
    private static let previewMarker = URL(fileURLWithPath:
        "/Users/patliu/Desktop/Coding/Voyage/QA/preview-ready")

    /// Landing close-up: one nonstop demo leg (60 s), then the arrival flow.
    /// Record around it with `xcrun simctl io booted recordVideo`; the run is
    /// under three minutes so the recorder stays reliable.
    @MainActor
    func testLandingCloseUp() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-VoyageHomeAirport", "SFO",
            "-VoyageDemoFlight",
        ]
        app.launch()
        dismissLocationPromptIfPresent()
        _ = app.staticTexts["VOYAGE"].waitForExistence(timeout: 15)
        pause(1.0)

        // The first card is the shortest route from SFO, a nonstop.
        let cards = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "destination-"))
        if cards.firstMatch.waitForExistence(timeout: 6) { cards.firstMatch.tap(); pause(1.0) }
        _ = tap(app.buttons["depart-now"], timeout: 5)
        pickASeat(in: app)
        skipBags(in: app)
        _ = app.buttons["Tear and board"].waitForExistence(timeout: 15)
        pause(1.0)
        _ = tap(app.buttons["Tear and board"], timeout: 4)

        let landed = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Landed in")).firstMatch
        _ = landed.waitForExistence(timeout: 120)
        pause(4.0)
        _ = tap(app.buttons["Continue"], timeout: 4)
        pause(3.0)
        if !tap(app.buttons["Post to your logbook"], timeout: 4) {
            _ = tap(app.buttons["Skip for now"], timeout: 2)
        }
        pause(4.0)
        _ = tap(app.buttons["Back to the terminal"], timeout: 4)
        pause(3.0)
    }

    /// Website demo source: globe, fast seat, skip bags, print and tear, the
    /// window (held), the route map, landing, and the trip replay. One nonstop
    /// demo leg, about 2.5 minutes real time; the site cut is sped to 20 s.
    @MainActor
    func testWebsiteDemo() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-VoyageHomeAirport", "SFO",
            "-VoyageDemoFlight",
            "-VoyageSceneHour", "10",
        ]
        app.launch()
        dismissLocationPromptIfPresent()
        _ = app.staticTexts["VOYAGE"].waitForExistence(timeout: 15)
        pause(4.0)   // globe settles; the cut opens here

        let cards = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "destination-"))
        if cards.firstMatch.waitForExistence(timeout: 6) { cards.firstMatch.tap(); pause(2.0) }
        _ = tap(app.buttons["depart-now"], timeout: 5)

        _ = app.staticTexts["Choose your seat"].waitForExistence(timeout: 8)
        pause(0.6)
        let seat = app.buttons.matching(
            NSPredicate(format: "label MATCHES %@", #"Seat [A-F][0-9]+"#)).firstMatch
        if seat.waitForExistence(timeout: 5) { seat.tap(); pause(0.6) }
        _ = tap(app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Take seat")).firstMatch, timeout: 3)
        skipBags(in: app)

        _ = app.buttons["Tear and board"].waitForExistence(timeout: 15)
        pause(1.0)
        _ = tap(app.buttons["Tear and board"], timeout: 4)

        // Window first and longest, then the route.
        let mapToggle = app.buttons["Map view"]
        _ = mapToggle.waitForExistence(timeout: 20)
        pause(14.0)
        mapToggle.tap()
        pause(6.0)
        _ = tap(app.buttons["Window view"], timeout: 3)

        // ArrivalFlowView greets with "Welcome to" over the city name.
        let welcome = app.staticTexts["Welcome to"]
        XCTAssertTrue(welcome.waitForExistence(timeout: 120), "the demo leg should land inside two minutes")
        pause(3.0)
        _ = tap(app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Continue")).firstMatch, timeout: 4)
        pause(2.5)   // passport control, the stamp lands
        if !tap(app.buttons["Post to your logbook"], timeout: 6) {
            _ = tap(app.buttons["Skip for now"], timeout: 2)
        }
        pause(2.0)
        _ = tap(app.buttons["Back to the terminal"], timeout: 4)
        pause(1.5)
        tourReplay(in: app)
        pause(2.0)
    }

    // MARK: Beats

    /// Draws one route, then another, so the globe re-flies the arc on camera.
    @MainActor
    private func bookAFlight(in app: XCUIApplication) {
        let cards = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "destination-"))
        guard cards.firstMatch.waitForExistence(timeout: 6) else { return }

        if cards.count > 1 {
            cards.element(boundBy: 1).tap()
            pause(3.0)
        }
        cards.firstMatch.tap()
        pause(3.0)

        _ = tap(app.buttons["depart-now"], timeout: 5)
    }

    /// Clears the bag screen. The button is `CheckBagView.swift:84`, which reads
    /// "Skip for now" until something is packed and "Check N bags" after. The
    /// reel packs nothing, so the first spelling is the one it meets; the
    /// second is here so a seeded run does not stall on the screen.
    @MainActor
    private func skipBags(in app: XCUIApplication) {
        if tap(app.buttons["Skip for now"], timeout: 6) { return }
        _ = tap(app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Check ")).firstMatch, timeout: 3)
    }

    @MainActor
    private func pickASeat(in app: XCUIApplication) {
        // SeatSelectionView.swift:111.
        _ = app.staticTexts["Choose your seat"].waitForExistence(timeout: 8)
        pause(1.5)

        // Sold seats are not buttons, so the first match is always bookable.
        let seat = app.buttons.matching(
            NSPredicate(format: "label MATCHES %@", #"Seat [A-F][0-9]+"#)).firstMatch
        if seat.waitForExistence(timeout: 5) {
            seat.tap()
            pause(2.0)   // the callout rises
        }

        let takeSeat = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Take seat")).firstMatch
        if !tap(takeSeat, timeout: 3) {
            _ = tap(app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Skip")).firstMatch, timeout: 2)
        }
    }

    @MainActor
    private func boardTheAircraft(in app: XCUIApplication) {
        skipBags(in: app)

        // The pass prints itself line by line; that print is the shot.
        _ = app.buttons["Tear and board"].waitForExistence(timeout: 12)
        pause(3.0)
        _ = tap(app.buttons["Tear and board"], timeout: 4)
    }

    @MainActor
    private func flyTheLeg(in app: XCUIApplication) {
        pause(5.0)   // curtain lifts, takeoff roll, into the climb

        let mapToggle = app.buttons["Map view"]
        guard mapToggle.waitForExistence(timeout: 8) else { return }
        pause(4.0)   // hold the window at cruise
        mapToggle.tap()
        pause(4.0)   // tiles in, plane tracks the great circle

        if tap(app.buttons["Satellite"], timeout: 3) { pause(3.0) }
        _ = tap(app.buttons["Window view"], timeout: 3)
    }

    /// Descent and landing arrive on their own under the demo flag. A route
    /// that connects stops at the lounge on the way, so board through it.
    @MainActor
    private func landAndReplay(in app: XCUIApplication) {
        let landed = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Landed in")).firstMatch
        let board = app.buttons["Board connecting flight"]

        let deadline = Date().addingTimeInterval(240)
        while Date() < deadline && !landed.exists {
            if board.exists && board.isHittable {
                board.tap()
                pause(1.0)
            }
            pause(1.0)
        }

        guard landed.waitForExistence(timeout: 30) else { return }
        pause(4.0)   // the arrival card settles

        _ = tap(app.buttons["Continue"], timeout: 4)
        pause(2.5)   // "Post to your logbook"

        // Posting is what puts this flight at the top of the logbook, which is
        // the flight the replay then opens on.
        if !tap(app.buttons["Post to your logbook"], timeout: 4) {
            _ = tap(app.buttons["Skip for now"], timeout: 2)
        }
        pause(2.5)

        tourReplay(in: app)
    }

    /// The payoff shot: a finished flight retracing its own route.
    @MainActor
    private func tourReplay(in app: XCUIApplication) {
        guard tap(app.buttons["Open logbook"], timeout: 4) else { return }
        pause(2.0)

        let replay = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Replay")).firstMatch
        guard tap(replay, timeout: 4) else { return }

        pause(8.0)   // autoplays; let the route draw across the map
        _ = tap(app.buttons["Pause trip replay"], timeout: 1.5)
        pause(2.0)
    }

    // MARK: Helpers

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Taps an element if it shows up in time. Returns whether it did, so a
    /// caller can spend the beat's time elsewhere when a screen is absent.
    @MainActor
    private func tap(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        guard element.waitForExistence(timeout: timeout), element.isHittable else { return false }
        element.tap()
        return true
    }

    @MainActor
    private func dismissLocationPromptIfPresent() {
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            .buttons["Allow While Using App"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
    }
}
