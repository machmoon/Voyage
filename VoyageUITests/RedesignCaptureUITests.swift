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
    func testCheckInTags() throws {
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
        let bag1 = app.textFields["Bag 1, e.g. Review chapter 4"]
        XCTAssertTrue(bag1.waitForExistence(timeout: 15))
        pause(1)
        save("redesign-01-checkin-empty")
        bag1.tap()
        bag1.typeText("Finish problem set 3\n")
        pause(0.5)
        save("redesign-02-checkin-printing")
        pause(1.5)
        let bag2 = app.textFields["Bag 2, e.g. Review chapter 4"]
        bag2.tap()
        bag2.typeText("Read chapter 7\n")
        pause(1)
        let bag3 = app.textFields["Bag 3, e.g. Review chapter 4"]
        bag3.tap()
        bag3.typeText("Outline the history essay\n")
        pause(2.5)
        save("redesign-03-checkin-three")
        let check = app.buttons["Check 3 bags"]
        XCTAssertTrue(check.waitForExistence(timeout: 4))
        check.tap()
        pause(0.3)
        save("redesign-04-checkin-check")
        XCTAssertTrue(app.buttons["Tear and board"].waitForExistence(timeout: 15))
    }

    @MainActor
    func testArrivalClaimAndCustoms() throws {
        let app = XCUIApplication()
        app.launchArguments += baseArguments + ["-VoyageDebugArrival"]
        app.launch()
        let bag0 = app.buttons["arrival-bag-0"]
        XCTAssertTrue(bag0.waitForExistence(timeout: 20), "The welcome screen lists the checked bags")
        pause(2)
        save("redesign-05-welcome")
        bag0.tap()
        pause(1)
        XCTAssertEqual(bag0.value as? String, "Finished", "A tap marks the bag finished")
        save("redesign-06-claim")
        app.buttons["Continue to passport control"].tap()
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
