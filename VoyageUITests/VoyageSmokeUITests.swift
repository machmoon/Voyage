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

        dismissLocationPromptIfPresent()

        XCTAssertTrue(app.staticTexts["VOYAGE"].waitForExistence(timeout: 10))

        try selectDestinationAndDepart(in: app)

        XCTAssertTrue(app.staticTexts["Select Seats"].waitForExistence(timeout: 12))

        let seat = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Seat ")).firstMatch
        XCTAssertTrue(seat.waitForExistence(timeout: 5), "Expected an accessible seat button")
        // Prefer an available (non-taken) seat. Labels are letter-first: "Seat C10".
        let available = app.buttons.matching(NSPredicate(format: "label MATCHES %@", #"Seat [A-D][0-9]+"#)).firstMatch
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
        let tearButton = app.buttons["Tear and board"]
        let passReady = tearHint.waitForExistence(timeout: 8) || tearButton.waitForExistence(timeout: 1)
        XCTAssertTrue(passReady, "Expected boarding pass tear hint or Tear and board control")

        // Capture boarding-pass screen for QA artifacts.
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "boarding-pass"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func selectDestinationAndDepart(in app: XCUIApplication) throws {
        // Destination cards only (never map home pin). Cards are sorted
        // shortest-flight-first, so the leftmost card is always on-screen.
        let cards = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "destination-"))
        let card = cards.firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "Expected a destination card on home")
        XCTAssertTrue(card.isHittable, "Expected the first destination card to be hittable")
        card.tap()

        let depart = app.buttons["depart-now"]
        XCTAssertTrue(depart.waitForExistence(timeout: 5), "Expected Depart now after selecting a destination")
        depart.tap()
    }

    @MainActor
    private func dismissLocationPromptIfPresent() {
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
}
