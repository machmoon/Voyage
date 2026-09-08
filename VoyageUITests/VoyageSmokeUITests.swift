import XCTest

/// Light smoke path: launch → pick a destination → start boarding → seat → bag → boarding pass.
final class VoyageSmokeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testBookingThroughBoardingPass() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-VoyageSkipOnboarding"]
        app.launch()

        dismissLocationPromptIfPresent()

        XCTAssertTrue(app.staticTexts["VOYAGE"].waitForExistence(timeout: 10))

        try selectDestinationAndDepart(in: app)

        XCTAssertTrue(app.staticTexts["Choose your seat"].waitForExistence(timeout: 12))

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

        let continueWithoutBags = app.buttons["Skip for now"]
        XCTAssertTrue(continueWithoutBags.waitForExistence(timeout: 5))
        continueWithoutBags.tap()

        let stub = app.otherElements["boarding-pass-stub"]
        XCTAssertTrue(stub.waitForExistence(timeout: 8), "Expected boarding pass stub")

        // Capture boarding-pass screen for QA artifacts.
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "boarding-pass"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testScheduleBoardIsReadableAndMultiCarrier() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-VoyageSkipOnboarding"]
        app.launch()

        dismissLocationPromptIfPresent()
        XCTAssertTrue(app.staticTexts["VOYAGE"].waitForExistence(timeout: 10))

        let card = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "destination-"))
            .firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()

        let schedule = app.buttons["Schedule"]
        XCTAssertTrue(schedule.waitForExistence(timeout: 5))
        schedule.tap()

        XCTAssertTrue(app.staticTexts["Schedule your focus"].waitForExistence(timeout: 5))
        let departureRows = app.buttons.matching(
            // Carrier codes are three letters, never two. A two-character code
            // is an IATA designator and would be a claim to a real airline's
            // identity (App Review 5.2.5), so assert the width here.
            NSPredicate(format: "label MATCHES %@", #"[A-Z]{3} [0-9]+, departs .*"#))
        XCTAssertGreaterThanOrEqual(departureRows.count, 5)

        let screenshot = XCUIScreen.main.screenshot()
        let url = URL(fileURLWithPath: "/Users/patliu/Desktop/Coding/Voyage/QA/design-schedule.png")
        try screenshot.pngRepresentation.write(to: url)
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "redesigned-schedule"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testPassportCollectionLayout() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-VoyageSkipOnboarding"]
        app.launch()

        dismissLocationPromptIfPresent()
        XCTAssertTrue(app.staticTexts["VOYAGE"].waitForExistence(timeout: 10))

        let logbook = app.buttons["Open logbook"]
        XCTAssertTrue(logbook.waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.84, dy: 0.09)).tap()

        let passport = app.segmentedControls.buttons["Passport"]
        XCTAssertTrue(passport.waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.74, dy: 0.19)).tap()

        XCTAssertTrue(app.staticTexts["Voyage Passport"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Destination stamps"].exists)

        let screenshot = XCUIScreen.main.screenshot()
        try screenshot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/voyage-passport-redesign.png"))
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "passport-redesign"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testWeeklyReplayDesignAndPlayback() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-VoyageSkipOnboarding"]
        app.launch()

        dismissLocationPromptIfPresent()
        XCTAssertTrue(app.staticTexts["VOYAGE"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Open logbook"].waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.84, dy: 0.09)).tap()

        let replayWeek = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Replay")
        ).firstMatch
        XCTAssertTrue(replayWeek.waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.48)).tap()

        XCTAssertTrue(app.buttons["Pause trip replay"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Recenter replay route"].exists)
        XCTAssertTrue(app.buttons["Playback speed, 1 times"].exists)
        let progressSlider = app.sliders["Trip replay progress"]
        XCTAssertTrue(progressSlider.waitForExistence(timeout: 5))
        let startingValue = String(describing: progressSlider.value)

        let playback = expectation(description: "Replay advances")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { playback.fulfill() }
        wait(for: [playback], timeout: 2)

        XCTAssertNotEqual(String(describing: progressSlider.value), startingValue,
                          "Replay progress should continue advancing while the UI remains responsive")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.84)).tap()
        XCTAssertTrue(app.buttons["Play trip replay"].waitForExistence(timeout: 3))

        let settledFrame = expectation(description: "Replay controls settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { settledFrame.fulfill() }
        wait(for: [settledFrame], timeout: 1)

        let screenshot = XCUIScreen.main.screenshot()
        try screenshot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/voyage-replay-design.png"))
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "weekly-replay-design"
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
