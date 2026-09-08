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
