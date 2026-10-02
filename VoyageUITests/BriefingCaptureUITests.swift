import XCTest

/// Photographs the onboarding pages and the on-device briefing. PNGs are only
/// written when the runner is given a directory:
///
///     TEST_RUNNER_VOYAGE_CAPTURE_DIR=/path TEST_RUNNER_VOYAGE_CAPTURE_SUFFIX=dark \
///       xcodebuild ... test -only-testing:VoyageUITests/BriefingCaptureUITests
///
/// Without it the tests still walk the flows and assert, and attach the shots.
final class BriefingCaptureUITests: XCTestCase {

    private static let mutedAudio = [
        "-soundEffectsEnabled", "<false/>",
        "-ambienceEnabled", "<false/>",
        "-announcementsEnabled", "<false/>",
    ]
    private static let locale = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]

    private var suffix: String {
        ProcessInfo.processInfo.environment["VOYAGE_CAPTURE_SUFFIX"].map { "-\($0)" } ?? ""
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: Onboarding

    @MainActor
    func testCaptureOnboardingPages() throws {
        let app = XCUIApplication()
        app.launchArguments += Self.locale + Self.mutedAudio + ["-VoyageResetOnboarding"]
        app.launch()

        XCTAssertTrue(app.staticTexts["I made studying feel like a flight."].waitForExistence(timeout: 20))
        sleep(4) // globe settle
        capture("onboarding-1-hello")
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.staticTexts["Tear your pass to take off."].waitForExistence(timeout: 5))
        sleep(2)
        capture("onboarding-2-takeoff")
        app.buttons["onboarding-tear-stub"].tap()
        sleep(1)
        capture("onboarding-2b-takeoff-torn")
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.staticTexts["Stay with it until you land."].waitForExistence(timeout: 5))
        sleep(1)
        capture("onboarding-3-in-flight")
        app.buttons["Continue"].tap()

        // Airplane Mode (Screen Time) appears only in builds that carry it.
        if app.staticTexts["Go dark at takeoff."].waitForExistence(timeout: 3) {
            sleep(1)
            capture("onboarding-4-airplane-mode")
            app.buttons["Continue"].tap()
        }

        XCTAssertTrue(app.staticTexts["Your flights stay on your phone."].waitForExistence(timeout: 5))
        sleep(1)
        capture("onboarding-4-privacy")

        app.buttons["Start flying"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow While Using App"]
        if allow.waitForExistence(timeout: 6) {
            sleep(1)
            capture("onboarding-5-location-alert")
            allow.tap()
        }
        XCTAssertTrue(app.staticTexts["VOYAGE"].waitForExistence(timeout: 15))
    }

    // MARK: In flight

    /// `-VoyageBriefingDemo` swaps in canned answers so a simulator without
    /// Apple Intelligence can show the plan and the note. Without the flag the
    /// real model is used when it is available, and the fallback when not.
    @MainActor
    func testCaptureBriefingWithDemoService() throws {
        try flyToCruise(extraArguments: ["-VoyageBriefingDemo"], name: "demo")
    }

    @MainActor
    func testCaptureBriefingWithSystemModelOrFallback() throws {
        try flyToCruise(extraArguments: [], name: "system")
    }

    /// Apple Intelligence switched off in Settings: the flight must look
    /// exactly as it does without the feature.
    @MainActor
    func testCaptureBriefingSwitchedOff() throws {
        try flyToCruise(extraArguments: ["-onDeviceIntelligenceEnabled", "<false/>"], name: "off", noteWait: 60)
    }

    @MainActor
    func testCaptureSettingsSection() throws {
        let app = XCUIApplication()
        app.launchArguments += Self.locale + Self.mutedAudio + ["-VoyageSkipOnboarding", "-VoyageHomeAirport", "SFO"]
        app.launch()
        XCTAssertTrue(app.staticTexts["VOYAGE"].waitForExistence(timeout: 20))
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let replay = app.buttons["Replay onboarding"]
        for _ in 0..<10 where !(replay.exists && replay.isHittable) { app.swipeUp() }
        app.swipeDown()
        sleep(1)
        capture("settings-apple-intelligence")
    }

    @MainActor
    private func flyToCruise(extraArguments: [String], name: String, noteWait: TimeInterval = 480) throws {
        let app = XCUIApplication()
        app.launchArguments += Self.locale + Self.mutedAudio
            + ["-VoyageShortFlights", "-VoyageHomeAirport", "SFO"] + extraArguments
        app.launch()

        XCTAssertTrue(app.staticTexts["VOYAGE"].waitForExistence(timeout: 20))
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "destination-")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        let depart = app.buttons["depart-now"]
        XCTAssertTrue(depart.waitForExistence(timeout: 10))
        depart.tap()

        XCTAssertTrue(app.staticTexts["Choose your seat"].waitForExistence(timeout: 15))
        let seat = app.buttons.matching(NSPredicate(format: "label MATCHES %@", #"Seat [A-D][0-9]+"#)).firstMatch
        XCTAssertTrue(seat.waitForExistence(timeout: 10))
        seat.tap()
        sleep(1)
        let takeSeat = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Take seat")).firstMatch
        XCTAssertTrue(takeSeat.waitForExistence(timeout: 20))
        takeSeat.tap()

        let fields = app.textFields
        XCTAssertTrue(fields.firstMatch.waitForExistence(timeout: 10))
        // The bag tag feeds out of the printer for about two seconds; a tap
        // during the feed lands before the field can take focus.
        sleep(3)
        fields.element(boundBy: 0).tap()
        fields.element(boundBy: 0).typeText("Finish problem set 4")
        fields.element(boundBy: 1).tap()
        fields.element(boundBy: 1).typeText("Read chapter 9")

        let board = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Check")).firstMatch
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        board.tap()
        let tear = app.buttons["Tear and board"]
        XCTAssertTrue(tear.waitForExistence(timeout: 25))
        tear.tap()

        // Short flights reach cruise about three minutes in.
        let note = app.otherElements["captain-note-card"]
        if note.waitForExistence(timeout: noteWait) {
            sleep(1)
            capture("inflight-\(name)-captain-note")
            // The note can stand without a plan: when the rules drop every
            // step, the bag tags stay (FlightBriefingTests covers it).
            let strip = app.buttons["flight-plan-strip"]
            if strip.waitForExistence(timeout: 5) {
                openPlanSheet(strip, in: app)
                capture("inflight-\(name)-flight-plan-sheet")
            }
        } else {
            // No note: the rules dropped it, or there is no model. Without a
            // model this is today's screen, bag tags and all.
            let strip = app.buttons["flight-plan-strip"]
            if strip.exists {
                capture("inflight-\(name)-plan-strip-no-note")
                openPlanSheet(strip, in: app)
                capture("inflight-\(name)-flight-plan-sheet")
            } else {
                capture("inflight-\(name)-fallback-bag-tags")
            }
        }
    }

    /// The in-flight screen also carries a double-tap gesture (pure mode), so
    /// a single tap can land late; wait for the sheet and try once more.
    @MainActor
    private func openPlanSheet(_ strip: XCUIElement, in app: XCUIApplication) {
        let title = app.navigationBars["Flight plan"]
        strip.tap()
        if !title.waitForExistence(timeout: 4) {
            strip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(title.waitForExistence(timeout: 6), "the flight plan sheet")
        sleep(1)
    }

    private func capture(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name + suffix
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = ProcessInfo.processInfo.environment["VOYAGE_CAPTURE_DIR"] else { return }
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)\(suffix).png"))
    }
}
