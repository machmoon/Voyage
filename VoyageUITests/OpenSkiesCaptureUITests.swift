import XCTest

/// Walks an Open skies flight on a demo-length clock: the card on Home, the
/// in-flight screen with its nearest-field line, a tap on the aircraft for
/// "YOU HAVE CONTROL", and the landing welcome. Each beat is attached to the
/// result and, when `OPENSKIES_CAPTURE_DIR` is set (pass it to xcodebuild as
/// `TEST_RUNNER_OPENSKIES_CAPTURE_DIR`), written there as a PNG.
final class OpenSkiesCaptureUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    func testOpenSkiesFlight() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-VoyageHomeAirport", "SFO",
            "-VoyageSkipOnboarding",
            "-VoyageDemoFlight",
            "-VoyageSceneHour", "10",
            "-ambienceEnabled", "<false/>",
            "-announcementsEnabled", "<false/>",
        ]
        app.launch()
        dismissSystemPrompt()

        let card = app.buttons["open-skies"]
        XCTAssertTrue(card.waitForExistence(timeout: 25), "Open skies leads the departure row")
        pause(3)
        shoot(app, "01-home-open-skies-card")

        card.tap()
        dismissSystemPrompt()
        XCTAssertTrue(app.staticTexts["Open skies"].waitForExistence(timeout: 30),
                      "the countdown names no destination")
        let line = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "earest field")).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 15), "the nearest-field line is under the countdown")
        pause(4)
        shoot(app, "02-inflight-nearest-field")

        let plane = app.descendants(matching: .any)["Your aircraft"]
        XCTAssertTrue(plane.waitForExistence(timeout: 10))
        plane.tap()
        XCTAssertTrue(app.staticTexts["YOU HAVE CONTROL"].waitForExistence(timeout: 5)
                      || app.staticTexts["You have control."].waitForExistence(timeout: 2))
        pause(1)
        shoot(app, "03-you-have-control")

        XCTAssertTrue(app.buttons["Continue to passport control"].waitForExistence(timeout: 90))
        pause(2)
        shoot(app, "04-you-made-it")
        XCTAssertTrue(app.staticTexts["You made it to"].exists)
    }

    private func shoot(_ app: XCUIApplication, _ name: String) {
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = ProcessInfo.processInfo.environment["OPENSKIES_CAPTURE_DIR"] else { return }
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private func pause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// Location and Focus-status prompts on a fresh simulator.
    private func dismissSystemPrompt() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons.matching(NSPredicate(
            format: "label IN %@", ["Allow While Using App", "Allow Once", "Allow"])).firstMatch
        if allow.waitForExistence(timeout: 2) { allow.tap() }
    }
}
