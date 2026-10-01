import XCTest

/// Quick captures of the 2026-09-30 redesigns: Home without the miles card,
/// the long bag tags at check-in, baggage claim, and the customs card. PNGs
/// land in `SHIPATON_CAPTURE_DIR` (pass `TEST_RUNNER_SHIPATON_CAPTURE_DIR`),
/// else the repo's `QA/` directory. Keeps going past a missed step.
final class RedesignCaptureUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private var baseArguments: [String] {
        ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
         "-VoyageHomeAirport", "SFO", "-VoyageLoyaltyStarter", "-VoyageSkipOnboarding",
         "-ambienceEnabled", "<false/>", "-announcementsEnabled", "<false/>"]
    }

    @MainActor
    func testPurposeOnPass() throws {
        let app = XCUIApplication()
        app.launchArguments += baseArguments
        app.launch()
        dismissSystemPrompt()
        let lax = app.buttons["destination-LAX"]
        XCTAssertTrue(lax.waitForExistence(timeout: 25))
        dismissSystemPrompt()
        pause(2)
        save("redesign-00-home")
        lax.tap()
        let depart = app.buttons["depart-now"]
        XCTAssertTrue(depart.waitForExistence(timeout: 8))
        depart.tap()
        let skip = app.buttons["Skip seat selection"]
        XCTAssertTrue(skip.waitForExistence(timeout: 12))
        skip.tap()
        let purpose = app.textFields["boarding-pass-purpose"]
        XCTAssertTrue(purpose.waitForExistence(timeout: 15), "The seat goes straight to the pass")
        XCTAssertTrue(app.buttons["Tear and board"].waitForExistence(timeout: 15))
        pause(1)
        save("redesign-01-pass-empty")
        purpose.tap()
        purpose.typeText("Finish problem set 3\n")
        pause(1)
        save("redesign-02-pass-purpose")
        XCTAssertEqual(purpose.value as? String, "Finish problem set 3")
    }

    @MainActor
    func testArrivalPurposeAndCustoms() throws {
        let app = XCUIApplication()
        app.launchArguments += baseArguments + ["-VoyageDebugArrival"]
        app.launch()
        let done = app.buttons["purpose-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 20), "Arrival asks about the purpose")
        pause(2)
        save("redesign-05-welcome")
        app.buttons["purpose-not-yet"].tap()
        XCTAssertTrue(app.buttons["purpose-carry"].waitForExistence(timeout: 3), "Not yet asks to bring it or let it go")
        pause(0.5)
        save("redesign-06-not-yet")
        app.buttons["purpose-carry"].tap()
        XCTAssertTrue(app.staticTexts["Anything to declare?"].waitForExistence(timeout: 8))
        pause(1.5)
        save("redesign-07-customs-empty")
        let prompt = "One idea you can now explain without your notes"
        let field = app.textViews[prompt].exists ? app.textViews[prompt] : app.textFields[prompt]
        field.tap()
        field.typeText("Spacing beats cramming: review on day 1, 3 and 7")
        pause(1)
        save("redesign-08-customs-typed")
        let declare = app.buttons["Declare and continue"]
        if !declare.isHittable { app.swipeDown() }
        declare.tap()
        pause(0.5)
        save("redesign-09-customs-stamped")
    }

    // MARK: Helpers

    private func pause(_ seconds: Double) {
        let done = expectation(description: "pause")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 2)
    }

    private func save(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let dir = ProcessInfo.processInfo.environment["SHIPATON_CAPTURE_DIR"]
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("QA").path
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func dismissSystemPrompt() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons.matching(NSPredicate(
            format: "label IN %@", ["Allow While Using App", "Allow Once", "Allow"])).firstMatch
        guard allow.waitForExistence(timeout: 3), allow.isHittable else { return }
        allow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
}
