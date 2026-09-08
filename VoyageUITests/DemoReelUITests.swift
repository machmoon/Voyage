import XCTest

/// Drives a paced walkthrough for the marketing reel: globe → booking → seat →
/// boarding pass → takeoff → window → map. Nothing is asserted for its own
/// sake; the timings exist so a screen recording of this run cuts to ~15s.
///
/// Record around it with:
///   xcrun simctl io booted recordVideo <out>.mp4
final class DemoReelUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
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

        XCTAssertTrue(app.staticTexts["VOYAGE"].waitForExistence(timeout: 15))
        // The simulator recorder drops frames while the globe warms up, so hold
        // well past the point the view looks settled.
        beat(6.0)

        let cards = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "destination-"))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 5))

        // Draw one route, then another, so the globe visibly re-flies the arc.
        if cards.count > 1 {
            cards.element(boundBy: 1).tap()
            beat(3.0)
        }
        let card = cards.firstMatch
        card.tap()
        beat(3.0) // globe flies the route

        let depart = app.buttons["depart-now"]
        XCTAssertTrue(depart.waitForExistence(timeout: 5))
        depart.tap()

        XCTAssertTrue(app.staticTexts["Select Seats"].waitForExistence(timeout: 8))
        beat(1.2)

        let seat = app.buttons.matching(
            NSPredicate(format: "label MATCHES %@", #"Seat [A-D][0-9]+"#)).firstMatch
        XCTAssertTrue(seat.waitForExistence(timeout: 5))
        seat.tap()
        beat(1.2)

        let takeSeat = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Take seat")).firstMatch
        XCTAssertTrue(takeSeat.waitForExistence(timeout: 4))
        takeSeat.tap()

        let skip = app.buttons["Travel light — skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 6))
        skip.tap()

        let tear = app.buttons["Tear and board"]
        XCTAssertTrue(tear.waitForExistence(timeout: 12))
        beat(2.5) // the pass prints itself
        tear.tap()

        beat(4.0) // curtain lifts, takeoff roll, into the climb

        let mapToggle = app.buttons["Map view"]
        XCTAssertTrue(mapToggle.waitForExistence(timeout: 6))
        beat(4.0) // hold on the window scene at cruise
        mapToggle.tap()
        beat(5.0) // map tiles in, plane tracks the great circle

        let satellite = app.buttons["Satellite"]
        if satellite.waitForExistence(timeout: 3) {
            satellite.tap()
            beat(4.0)
        }

        let windowToggle = app.buttons["Window view"]
        if windowToggle.waitForExistence(timeout: 3) {
            windowToggle.tap()
        }

        // -VoyageDemoFlight clamps each leg to a minute and the lounge to 20s,
        // so the descent and landing arrive on their own from here. A route
        // that connects stops at the lounge first, so board through it.
        let welcome = app.staticTexts["Welcome to"]
        let board = app.buttons["Board connecting flight"]
        let deadline = Date().addingTimeInterval(240)
        while Date() < deadline {
            if welcome.exists { break }
            if board.exists {
                board.tap()
                beat(1.0)
            }
            beat(1.0)
        }
        XCTAssertTrue(welcome.waitForExistence(timeout: 30), "Expected the arrival flow")
        beat(4.0) // city name, code and the stats card settle

        let toPassport = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "passport control")).firstMatch
        XCTAssertTrue(toPassport.waitForExistence(timeout: 5))
        toPassport.tap()
        beat(5.0) // the stamp lands

        let terminal = app.buttons["Back to the terminal"]
        if terminal.waitForExistence(timeout: 5) {
            terminal.tap()
            beat(2.0)
        }
    }

    /// Sleep in fractional seconds; the reel is cut on these.
    private func beat(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    @MainActor
    private func dismissLocationPromptIfPresent() {
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            .buttons["Allow While Using App"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
    }
}
