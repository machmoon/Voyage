import XCTest

/// Screen-capture harness for the in-flight map's Follow camera. Boards a
/// demo-length flight, switches the map card to Follow and holds still for the
/// leg, so a `simctl io recordVideo` around it shows the camera from takeoff
/// to landing. Asserts nothing about pixels; the recording is the evidence.
final class FollowCameraCaptureUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    /// Satellite, the map card's default style.
    @MainActor
    func testFollowSatellite() throws {
        try flyFollowing(style: nil)
    }

    /// The standard map style.
    @MainActor
    func testFollowMap() throws {
        try flyFollowing(style: "Map")
    }

    @MainActor
    private func flyFollowing(style: String?) throws {
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

        let lax = app.buttons["destination-LAX"]
        XCTAssertTrue(lax.waitForExistence(timeout: 25))
        lax.tap()
        dismissSystemPrompt()
        let depart = app.buttons["depart-now"]
        XCTAssertTrue(depart.waitForExistence(timeout: 8))
        depart.tap()
        dismissSystemPrompt()
        // The seat map preselects a seat ("Take seat A8"); older builds had a
        // skip button instead.
        let take = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Take seat")).firstMatch
        let skip = app.buttons["Skip seat selection"]
        if take.waitForExistence(timeout: 12) { take.tap() } else if skip.exists { skip.tap() }

        let bag1 = app.textFields["Bag 1, e.g. Review chapter 4"]
        if bag1.waitForExistence(timeout: 15) {
            bag1.tap()
            bag1.typeText("Finish problem set 3\n")
            pause(1)
            let check = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Check ")).firstMatch
            if check.exists, check.isHittable, !app.buttons["Tear and board"].exists { check.tap() }
        }
        let tear = app.buttons["Tear and board"]
        if tear.waitForExistence(timeout: 20) {
            pause(1)
            let cutStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.615))
            let cutEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.62))
            cutStart.press(forDuration: 0.05, thenDragTo: cutEnd, withVelocity: 140, thenHoldForDuration: 0.1)
            pause(2)
            if tear.exists, tear.isHittable { tear.tap() }
        }

        let follow = app.buttons["Follow"]
        XCTAssertTrue(follow.waitForExistence(timeout: 30), "Expected the map card's camera picker")
        if let style {
            let button = app.buttons[style]
            if button.waitForExistence(timeout: 3) { button.tap() }
        }
        follow.tap()
        mark("follow-on")
        // The demo leg is 60 s; hold for most of it.
        _ = app.buttons["Continue to passport control"].waitForExistence(timeout: 75)
        mark("follow-end")
    }

    private func mark(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["FOLLOW_CAPTURE_DIR"] else { return }
        let stamp = String(format: "%.3f", Date().timeIntervalSince1970)
        try? stamp.write(toFile: dir + "/\(name).txt", atomically: true, encoding: .utf8)
    }

    /// Location, and the Focus-status prompt, on a local simulator.
    private func dismissSystemPrompt() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons.matching(NSPredicate(
            format: "label IN %@", ["Allow While Using App", "Allow Once", "Allow"])).firstMatch
        guard allow.waitForExistence(timeout: 3), allow.isHittable else { return }
        allow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func pause(_ seconds: Double) {
        let done = expectation(description: "pause")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 2)
    }
}
