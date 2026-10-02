import XCTest

/// The onboarding Airplane Mode page after apps were chosen, for the 1.7
/// App Store set: "AIRPLANE MODE / Go dark at takeoff." over the line
/// "N apps blocked during flights". Walks onboarding to that page, asks for
/// Screen Time (the simulator's passcode is 1234), picks three categories in
/// the Screen Time picker and photographs the page. PNGs and hierarchy dumps
/// land in `VOYAGE_CAPTURE_DIR` (pass `TEST_RUNNER_VOYAGE_CAPTURE_DIR`).
final class AirplaneModeCaptureUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    func testAirplaneModePage() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                                "-VoyageResetOnboarding",
                                "-ambienceEnabled", "<false/>", "-announcementsEnabled", "<false/>"]
        app.launch()

        // Hello, then the tearable pass, then the in-flight rule.
        let next = app.buttons["Continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 15))
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"),
                                                           object: next)], timeout: 5)
        sleep(2)
        next.tap()
        let stub = app.buttons["onboarding-tear-stub"]
        XCTAssertTrue(stub.waitForExistence(timeout: 10))
        stub.tap()
        sleep(2)
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Stay with it until you land."].waitForExistence(timeout: 10))
        sleep(1)
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.staticTexts["Go dark at takeoff."].waitForExistence(timeout: 10))
        sleep(2)
        capture("airplane-0-default")
        dump(app, "airplane-0-default")

        let choose = app.buttons["onboarding-choose-apps"]
        guard choose.waitForExistence(timeout: 5) else {
            XCTFail("no Choose apps button: Screen Time unavailable here")
            return
        }
        choose.tap()

        authorize(app)

        // The Screen Time picker. Categories are rows; tap three.
        sleep(4)
        capture("airplane-1-picker")
        dump(app, "airplane-1-picker")
        var picked = 0
        for name in ["Social", "Games", "Entertainment"] {
            let row = app.descendants(matching: .any).matching(
                NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
            if row.waitForExistence(timeout: 5) {
                row.tap()
                picked += 1
                sleep(1)
            }
        }
        capture("airplane-2-picked")
        dump(app, "airplane-2-picked")
        let done = app.buttons.matching(NSPredicate(format: "label == 'Done' OR identifier == 'Done'")).firstMatch
        if done.waitForExistence(timeout: 5) { done.tap() }

        XCTAssertTrue(app.staticTexts["Go dark at takeoff."].waitForExistence(timeout: 10))
        sleep(2)
        capture("airplane-3-chosen")
        dump(app, "airplane-3-chosen")
        XCTAssertGreaterThan(picked, 0)
    }

    /// The Screen Time consent sheet and the passcode it asks for. It is
    /// served by a system process, so look in SpringBoard as well as the app.
    @MainActor
    private func authorize(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        sleep(3)
        capture("auth-0")
        dump(springboard, "auth-0-springboard")
        dump(app, "auth-0-app")
        for source in [springboard, app] {
            let cont = source.buttons["Continue"]
            if cont.exists && cont.isHittable { cont.tap(); break }
        }
        // The full-screen sheet that follows: "Allow with Passcode".
        let allow = springboard.buttons["Allow with Passcode"]
        if allow.waitForExistence(timeout: 8) { allow.tap() }
        sleep(3)
        capture("auth-1")
        dump(springboard, "auth-1-springboard")
        for source in [springboard, app] {
            let field = source.secureTextFields.firstMatch
            if field.exists {
                field.typeText("1234\n") // Return submits the passcode
                break
            }
            if source.keys["1"].exists {
                for k in ["1", "2", "3", "4"] { source.keys[k].tap() }
                source.buttons["Done"].tap()
                break
            }
        }
        sleep(3)
        capture("auth-2")
        dump(springboard, "auth-2-springboard")
    }

    private var dir: String? { ProcessInfo.processInfo.environment["VOYAGE_CAPTURE_DIR"] }

    private func capture(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir else { return }
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private func dump(_ app: XCUIApplication, _ name: String) {
        guard let dir else { return }
        try? app.debugDescription.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).txt"),
                                        atomically: true, encoding: .utf8)
    }
}
