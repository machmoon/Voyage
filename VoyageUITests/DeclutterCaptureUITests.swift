import XCTest

/// One capture per main screen, for the 2026-10-01 de-clutter pass (Pat:
/// "theres like a lot of clutter"). PNGs land in `SHIPATON_CAPTURE_DIR`
/// (pass `TEST_RUNNER_SHIPATON_CAPTURE_DIR`), else the repo's `QA/`.
/// Keeps going past a missed step, so one moved button costs one picture.
final class DeclutterCaptureUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private var baseArguments: [String] {
        ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
         "-VoyageHomeAirport", "SFO", "-VoyageSkipOnboarding", "-VoyageShortFlights",
         "-ambienceEnabled", "<false/>", "-announcementsEnabled", "<false/>"]
    }

    /// Home, destination selected, schedule sheet, seat map, check-in,
    /// boarding pass, in flight.
    @MainActor
    func testDepartureFlow() throws {
        let app = XCUIApplication()
        app.launchArguments += baseArguments
        app.launch()
        dismissSystemPrompt()
        let lax = app.buttons["destination-LAX"]
        XCTAssertTrue(lax.waitForExistence(timeout: 25))
        dismissSystemPrompt()
        pause(3)
        save("declutter-home")
        lax.tap()
        pause(1.5)
        save("declutter-destination")

        let schedule = app.buttons["Schedule"]
        if schedule.waitForExistence(timeout: 5) {
            schedule.tap()
            pause(2)
            save("declutter-schedule")
            let close = app.buttons.matching(NSPredicate(
                format: "label IN %@", ["Close", "Cancel", "Done"])).firstMatch
            if close.exists { close.tap() } else { app.swipeDown(velocity: .fast) }
            pause(1.5)
        }

        let depart = app.buttons["depart-now"]
        XCTAssertTrue(depart.waitForExistence(timeout: 8))
        depart.tap()
        XCTAssertTrue(app.staticTexts["Choose your seat"].waitForExistence(timeout: 15))
        pause(1.5)
        save("declutter-seat")
        let seat = app.buttons["Seat D8"]
        if seat.waitForExistence(timeout: 5), (seat.value as? String) != "Selected" { seat.tap() }
        pause(1.5)
        save("declutter-seat-selected")
        let take = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Take seat")).firstMatch
        if take.exists { take.tap() } else { app.buttons["Skip seat selection"].tap() }

        let bag1 = app.textFields["Bag 1, e.g. Review chapter 4"]
        XCTAssertTrue(bag1.waitForExistence(timeout: 15))
        pause(1)
        save("declutter-checkin")
        bag1.tap()
        bag1.typeText("Finish problem set 3\n")
        pause(2)
        save("declutter-checkin-one")
        let check = app.buttons["Check 1 bag"]
        if check.waitForExistence(timeout: 4) { check.tap() } else { app.buttons["Skip for now"].tap() }

        let tear = app.buttons["Tear and board"]
        XCTAssertTrue(tear.waitForExistence(timeout: 25))
        pause(1.5)
        save("declutter-boarding-pass")
        tear.tap()
        pause(8)
        save("declutter-inflight-window")
        let mapToggle = app.buttons["Map view"]
        if mapToggle.waitForExistence(timeout: 10) {
            mapToggle.tap()
            pause(4)
            save("declutter-inflight-map")
        }
    }

    @MainActor
    func testArrival() throws {
        let app = XCUIApplication()
        app.launchArguments += baseArguments + ["-VoyageDebugArrival"]
        app.launch()
        dismissSystemPrompt()
        let bag0 = app.buttons["arrival-bag-0"]
        XCTAssertTrue(bag0.waitForExistence(timeout: 20))
        pause(2)
        save("declutter-arrival")
        let next = app.buttons["Continue to passport control"]
        if next.exists {
            next.tap()
            _ = app.staticTexts["Anything to declare?"].waitForExistence(timeout: 8)
            pause(2)
            save("declutter-customs")
        }
    }

    /// The seat sheet at accessibility text size: the selected-seat row
    /// must wrap, not clip, and never cover the cabin.
    @MainActor
    func testSeatAtLargeText() throws {
        let app = XCUIApplication()
        app.launchArguments += baseArguments + [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        app.launch()
        dismissSystemPrompt()
        let lax = app.buttons["destination-LAX"]
        XCTAssertTrue(lax.waitForExistence(timeout: 25))
        dismissSystemPrompt()
        lax.tap()
        let depart = app.buttons["depart-now"]
        XCTAssertTrue(depart.waitForExistence(timeout: 8))
        depart.tap()
        let seat = app.buttons
            .matching(NSPredicate(format: "label MATCHES %@", #"Seat [A-F][0-9]+"#))
            .firstMatch
        XCTAssertTrue(seat.waitForExistence(timeout: 15))
        seat.tap()
        pause(1.5)
        save("declutter-seat-large-text")
    }

    @MainActor
    func testStamp() throws {
        let app = XCUIApplication()
        app.launchArguments += baseArguments + ["-VoyageDebugStamp"]
        app.launch()
        dismissSystemPrompt()
        pause(9)
        dismissSystemPrompt()
        save("declutter-stamp")
    }

    @MainActor
    func testLogbookAndSettings() throws {
        let app = XCUIApplication()
        app.launchArguments += baseArguments + ["-VoyageRecorderDemo"]
        app.launch()
        dismissSystemPrompt()
        let logbook = app.buttons["open-logbook"]
        XCTAssertTrue(logbook.waitForExistence(timeout: 25))
        dismissSystemPrompt()
        pause(1)
        logbook.tap()
        pause(2.5)
        save("declutter-logbook")
        app.swipeUp()
        pause(1)
        save("declutter-logbook-2")
        let done = app.buttons["Done"]
        if done.exists { done.tap() } else { app.swipeDown(velocity: .fast) }
        pause(1.5)
        app.buttons["Settings"].tap()
        pause(2)
        save("declutter-settings")
        app.swipeUp()
        pause(1)
        save("declutter-settings-2")
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
