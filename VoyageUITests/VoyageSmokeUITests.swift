import XCTest

/// Light smoke path: launch → pick a destination → start boarding → seat → bag → boarding pass.
final class VoyageSmokeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testBookingThroughBoardingPass() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        dismissLocationPromptIfPresent(app)

        XCTAssertTrue(app.staticTexts["VOYAGE"].waitForExistence(timeout: 10))

        let destination = firstExisting(in: app, labels: ["SFO", "LAX", "JFK", "BOS", "MIA", "YYZ", "YVR", "YQR"])
        XCTAssertNotNil(destination, "Expected at least one destination card on home")
        destination?.tap()

        let depart = app.buttons["Depart now"]
        XCTAssertTrue(depart.waitForExistence(timeout: 5))
        depart.tap()

        XCTAssertTrue(app.staticTexts["Choose your seat"].waitForExistence(timeout: 6))

        let seat = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Seat ")).firstMatch
        XCTAssertTrue(seat.waitForExistence(timeout: 5), "Expected an accessible seat button")
        // Prefer an available (non-taken) seat.
        let available = app.buttons.matching(NSPredicate(format: "label MATCHES %@", #"Seat [0-9]+[A-F]"#)).firstMatch
        if available.exists {
            available.tap()
        } else {
            seat.tap()
        }

        let takeSeat = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Take seat")).firstMatch
        XCTAssertTrue(takeSeat.waitForExistence(timeout: 3))
        takeSeat.tap()

        let skip = app.buttons["Travel light — skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()

        let tearHint = app.staticTexts["Pull the stub down to tear & board"]
        let tearButton = app.buttons["Tear & board"]
        let passReady = tearHint.waitForExistence(timeout: 8) || tearButton.waitForExistence(timeout: 1)
        XCTAssertTrue(passReady, "Expected boarding pass tear hint or Tear & board control")

        // Capture boarding-pass screen for QA artifacts.
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "boarding-pass"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func dismissLocationPromptIfPresent(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow While Using App"]
        if allow.waitForExistence(timeout: 3) {
            allow.tap()
            return
        }
        let once = springboard.buttons["Allow Once"]
        if once.waitForExistence(timeout: 1) {
            once.tap()
        }
    }

    @MainActor
    private func firstExisting(in app: XCUIApplication, labels: [String]) -> XCUIElement? {
        for label in labels {
            let button = app.buttons[label]
            if button.waitForExistence(timeout: 1.2) { return button }
            let containing = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
            if containing.waitForExistence(timeout: 0.4) { return containing }
        }
        return nil
    }
}
