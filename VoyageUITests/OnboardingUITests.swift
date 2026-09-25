import XCTest

/// Verifies the first-run preflight onboarding: it appears on a fresh install,
/// walks four screens, and hands off to the home globe. `-VoyageResetOnboarding`
/// forces the first-run state regardless of prior launches.
final class OnboardingUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOnboardingWalkthroughReachesHome() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                                "-VoyageResetOnboarding"]
        // The location alert now follows the last page's button, not launch.
        addUIInterruptionMonitor(withDescription: "Location") { alert in
            let allow = alert.buttons["Allow While Using App"]
            if allow.exists { allow.tap(); return true }
            return false
        }
        app.launch()

        // Screen 1, hello, with real block times
        XCTAssertTrue(app.staticTexts["I made studying feel like a flight."].waitForExistence(timeout: 10))
        capture(app, name: "onboarding-1-hello")
        app.buttons["Continue"].tap()

        // Screen 2, the boarding pass you can tear
        XCTAssertTrue(app.staticTexts["Tear your pass to take off."].waitForExistence(timeout: 5))
        let stub = app.buttons["onboarding-tear-stub"]
        XCTAssertTrue(stub.waitForExistence(timeout: 5))
        stub.tap()
        XCTAssertTrue(app.staticTexts["Cleared for takeoff. Tap the pass to try again."].waitForExistence(timeout: 5))
        capture(app, name: "onboarding-2-takeoff")
        app.buttons["Continue"].tap()

        // Screen 3, the 30-second rule and the stamp
        XCTAssertTrue(app.staticTexts["Stay with it until you land."].waitForExistence(timeout: 5))
        capture(app, name: "onboarding-3-in-flight")
        app.buttons["Continue"].tap()

        // Screen 4, privacy. No Skip here: its button leads to the location alert.
        XCTAssertTrue(app.staticTexts["Your flights stay on your phone."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["onboarding-skip"].exists)
        capture(app, name: "onboarding-4-privacy")

        app.buttons["Start flying"].tap()
        app.tap() // lets the interruption monitor answer the alert

        // Hands off to the home globe.
        XCTAssertTrue(app.staticTexts["VOYAGE"].waitForExistence(timeout: 10))
    }

    /// Skip leaves from any page before the last and never asks for anything
    /// on the way out.
    @MainActor
    func testSkipGoesStraightHome() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                                "-VoyageResetOnboarding"]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding-skip"].waitForExistence(timeout: 10))
        app.buttons["onboarding-skip"].tap()
        XCTAssertTrue(app.staticTexts["VOYAGE"].waitForExistence(timeout: 10))
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let shot = XCUIScreen.main.screenshot()
        try? shot.pngRepresentation.write(
            to: URL(fileURLWithPath: "/Users/patliu/Desktop/Coding/Voyage/QA/\(name).png"))
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
