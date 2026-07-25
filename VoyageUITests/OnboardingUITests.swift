import XCTest

/// Verifies the first-run preflight onboarding: it appears on a fresh install,
/// walks two screens, and hands off to the home globe. `-VoyageResetOnboarding`
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
        app.launch()

        // Screen 1, welcome
        XCTAssertTrue(app.staticTexts["Thank you for downloading Voyage."].waitForExistence(timeout: 10))
        capture(app, name: "onboarding-1-hello")

        app.buttons["Continue"].tap()

        // Screen 2, how it works, and the route handoff
        XCTAssertTrue(app.staticTexts["Book a real route"].waitForExistence(timeout: 5))
        capture(app, name: "onboarding-2-steps")

        app.buttons["Start flying"].tap()

        // Hands off to the home globe.
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
