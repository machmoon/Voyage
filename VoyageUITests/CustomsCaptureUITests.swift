import XCTest

/// Photographs customs by voice in each of its states, driven by the
/// scripted officer (`-VoyageCustomsDemo <stage>`, DEBUG only), since the
/// simulator has no on-device speech recogniser. PNGs are written when the
/// runner is given a directory, as in `BriefingCaptureUITests`:
///
///     TEST_RUNNER_VOYAGE_CAPTURE_DIR=/path xcodebuild ... test \
///       -only-testing:VoyageUITests/CustomsCaptureUITests
final class CustomsCaptureUITests: XCTestCase {

    private static let base = [
        "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        "-soundEffectsEnabled", "<false/>", "-ambienceEnabled", "<false/>",
        "-announcementsEnabled", "<false/>",
        "-VoyageDebugArrival", "-VoyageDebugCustoms",
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ stage: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += Self.base + ["-VoyageCustomsDemo", stage] + extra
        app.launch()
        XCTAssertTrue(app.staticTexts["Anything to declare?"].waitForExistence(timeout: 20))
        return app
    }

    @MainActor
    func testCaptureIntro() {
        let app = launch("intro", extra: ["-customsVoiceIntroSeen", "<false/>"])
        XCTAssertTrue(app.buttons["Use voice"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Type instead"].exists)
        sleep(1)
        capture("customs-0-intro")
    }

    @MainActor
    func testCaptureAsking() {
        let app = launch("asking")
        XCTAssertTrue(app.staticTexts["QUESTION 1 OF 3"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Skip"].exists)
        sleep(1)
        capture("customs-1-asking")
    }

    @MainActor
    func testCaptureListening() {
        let app = launch("listening")
        XCTAssertTrue(app.staticTexts["LISTENING"].waitForExistence(timeout: 15))
        sleep(4) // the scripted words land on the card
        capture("customs-2-listening")
    }

    @MainActor
    func testCaptureFeedback() {
        let app = launch("feedback")
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 10))
        let officer = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Nice")).firstMatch
        XCTAssertTrue(officer.waitForExistence(timeout: 20))
        sleep(1)
        capture("customs-3-feedback")
    }

    @MainActor
    func testCaptureTypeInstead() {
        let app = launch("typing")
        let field = app.descendants(matching: .any)["customs-answer-0"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        sleep(2)
        capture("customs-4-type-instead")
    }

    @MainActor
    func testCaptureSettingsRow() {
        let app = XCUIApplication()
        app.launchArguments += Array(Self.base.prefix(8)) + ["-VoyageSkipOnboarding", "-VoyageHomeAirport", "SFO"]
        app.launch()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        let row = app.switches["settings-customs"]
        for _ in 0..<6 where !(row.exists && row.isHittable) { app.swipeUp() }
        XCTAssertTrue(row.exists)
        sleep(1)
        capture("customs-5-settings")
    }

    private func capture(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = ProcessInfo.processInfo.environment["VOYAGE_CAPTURE_DIR"] else { return }
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}
