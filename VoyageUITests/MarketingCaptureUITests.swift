import XCTest

/// Marketing capture: one booking driven far enough to photograph every
/// surface the App Store page needs, including a real cruise window, which
/// `ScreenshotTourUITests` never reaches (its "cruise" frame is taken eleven
/// seconds after the tear, still on the runway).
///
/// Names are prefixed `mk-` so they never collide with the QA tour's `qa-`
/// captures that `AppStore/screenshots.json` binds to. Output goes to the same
/// place, `VOYAGE_QA_DIR` or `QA/`, following the same convention as the tour.
///
/// Runs under `-VoyageShortFlights`, so cruise begins 180 s after the tear
/// (`FlightPhaseSchedule.make`, `FlightVisualEngine.swift:31-47`). The wait is
/// real and this test takes about four minutes. `-VoyageRecorderDemo` swaps in
/// the in-memory demo logbook so the logbook, recorder and passport captures
/// have history to show; the booking itself is never written anywhere.
/// `-VoyageRealWorldTwinEnabled` forces the streamed satellite window: without
/// it a run can inherit the drawn world from the simulator's saved settings
/// and the climb and cruise frames come out as the procedural sky.
///
/// Set the status bar before running, and again after any run that shut the
/// simulator down, because xcodebuild's restart clears the override:
///
///     xcrun simctl status_bar booted override --time 9:41 --batteryLevel 100 \
///         --batteryState charged --wifiBars 3 --cellularBars 4 --operatorName ""
///
/// Composite the App Store set afterwards with
/// `scripts/make_app_store_screenshots.py --config AppStore/screenshots-1.2.json`.
final class MarketingCaptureUITests: XCTestCase {

    private static let qaDirectory: URL = {
        if let override = ProcessInfo.processInfo.environment["VOYAGE_QA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("QA", isDirectory: true)
    }()

    private var writesPNGs = false

    private static let launchArguments = [
        "-AppleLanguages", "(en)",
        "-AppleLocale", "en_US",
        "-VoyageHomeAirport", "SFO",
        "-VoyageShortFlights",
        "-VoyageRecorderDemo",
        "-VoyageSceneHour", "10",
        "-VoyageRealWorldTwinEnabled",
        "-soundEffectsEnabled", "<false/>",
        "-ambienceEnabled", "<false/>",
        "-announcementsEnabled", "<false/>",
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
        writesPNGs = (try? FileManager.default.createDirectory(
            at: Self.qaDirectory, withIntermediateDirectories: true)) != nil
    }

    @MainActor
    func testMarketingCaptureTour() throws {
        let app = XCUIApplication()
        app.launchArguments += Self.launchArguments
        app.launch()
        dismissLocationPromptIfPresent()

        // 1. Home globe with the route rail.
        require(app.staticTexts["VOYAGE"], "the VOYAGE home header", timeout: 20)
        settle(3)
        capture(app, "mk-01-home")

        // 2. A destination chosen: route arc and the route pill.
        let lax = app.buttons["destination-LAX"]
        require(lax, "the LAX destination card")
        lax.tap()
        settle(2)
        capture(app, "mk-02-route-selected")

        // 3. The departure board.
        let schedule = app.buttons["Schedule"]
        require(schedule, "the Schedule button")
        schedule.tap()
        require(app.staticTexts["Schedule your focus"], "the departure board sheet", timeout: 8)
        settle(1)
        capture(app, "mk-03-departure-board")
        app.swipeDown(velocity: .fast)
        settle(1)
        if app.staticTexts["Schedule your focus"].exists {
            // Sheet did not dismiss on the swipe; drag from its grabber.
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
            start.press(forDuration: 0.1, thenDragTo: end)
            settle(1)
        }

        // 4. Seat map.
        let depart = app.buttons["depart-now"]
        require(depart, "Depart now")
        depart.tap()
        require(app.staticTexts["Choose your seat"], "the seat map", timeout: 10)
        let seat = app.buttons
            .matching(NSPredicate(format: "label MATCHES %@", #"Seat [A-D][0-9]+"#))
            .firstMatch
        require(seat, "a selectable seat")
        seat.tap()
        settle(1)
        capture(app, "mk-04-seat-map")

        let takeSeat = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Take seat"))
            .firstMatch
        require(takeSeat, "Take seat", timeout: 6)
        takeSeat.tap()

        // 5. Bags: two intentions typed in, so the pass carries them.
        let bag1 = app.textFields["Bag 1, e.g. Review chapter 4"]
        require(bag1, "the first bag field", timeout: 10)
        bag1.tap()
        bag1.typeText("Finish the problem set")
        let bag2 = app.textFields["Bag 2, e.g. Review chapter 4"]
        require(bag2, "the second bag field")
        bag2.tap()
        bag2.typeText("Read chapter 7")
        settle(1)
        capture(app, "mk-05-check-bags")
        let checkBags = app.buttons["Check 2 bags"]
        require(checkBags, "Check 2 bags")
        checkBags.tap()

        // 6. The printed pass, ready to tear.
        require(app.otherElements["boarding-pass-stub"], "the boarding pass stub", timeout: 15)
        let tear = app.buttons["Tear and board"]
        require(tear, "Tear and board", timeout: 20)
        settle(1)
        capture(app, "mk-06-boarding-pass")
        tear.tap()

        // 7. Climb, about a minute after the tear.
        require(app.staticTexts["Climbing through the cloud deck"], "the climb caption", timeout: 60)
        settle(30)
        capture(app, "mk-07-window-climb")

        // 8. Real cruise. Short flights put it at 180 s; allow slack.
        require(app.staticTexts["Cruising · seatbelt sign off"], "the cruise caption", timeout: 200)
        settle(8)
        capture(app, "mk-08-window-cruise")

        // 9. Pure mode: only the window and the clock.
        app.doubleTap()
        settle(1)
        capture(app, "mk-09-pure-mode")
        app.doubleTap()
        settle(1)

        // 10 and 11. Moving map, route camera then follow camera, satellite.
        // The second double tap is sometimes read as a single tap and pure
        // mode stays on, which left the "map" captures showing the bare window
        // (AppStore/screenshots-1.2 slot 5, September 14). Retry until the
        // chrome is back, then prove the map is up before capturing it.
        let mapToggle = app.buttons["Map view"]
        require(mapToggle, "the Map view toggle")
        for _ in 0..<3 where !mapToggle.isHittable {
            app.doubleTap()
            settle(2)
        }
        mapToggle.tap()
        settle(2)
        require(app.buttons["Follow"], "the map camera controls")
        tapIfPresent(app.buttons["Satellite"])
        tapIfPresent(app.buttons["Route"])
        settle(4)
        capture(app, "mk-10-map-route")
        tapIfPresent(app.buttons["Follow"])
        settle(4)
        capture(app, "mk-11-map-follow")

    }

    /// Logbook, recorder and passport from the demo logbook. Separate launch so
    /// these frames never depend on the four-minute flight above.
    @MainActor
    func testMarketingCaptureLogbook() throws {
        let app = XCUIApplication()
        app.launchArguments += Self.launchArguments
        app.launch()
        dismissLocationPromptIfPresent()

        let logbook = app.buttons["open-logbook"]
        require(logbook, "the Logbook button on home", timeout: 20)
        logbook.tap()
        require(app.staticTexts["Insights"], "the insights row", timeout: 10)
        settle(2)
        capture(app, "mk-12-logbook")

        app.buttons["open-recorder"].tap()
        settle(3)
        capture(app, "mk-13-recorder")

        // The study coach under the findings.
        let plan = app.staticTexts["Study coach"]
        for _ in 0..<6 where !(plan.exists && plan.isHittable) {
            app.swipeUp()
        }
        require(plan, "the Study coach heading")
        app.swipeUp()
        settle(1)
        capture(app, "mk-15-coach")
        app.swipeUp()
        app.swipeUp()
        require(app.buttons["coach-copy-logbook"], "the Ask an AI card")
        settle(1)
        capture(app, "mk-16-coach-ask")
        app.navigationBars.buttons.firstMatch.tap()
        settle(1)

        let passportTab = app.buttons["Passport"]
        if passportTab.waitForExistence(timeout: 5) {
            passportTab.tap()
            settle(2)
            capture(app, "mk-14-passport")
        }
    }

    // MARK: Helpers

    @MainActor
    private func tapIfPresent(_ element: XCUIElement) {
        if element.waitForExistence(timeout: 2), element.isHittable { element.tap() }
    }

    @MainActor
    private func assertForeground(_ app: XCUIApplication, _ checkpoint: String,
                                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(app.state, .runningForeground,
                       "Voyage is not in the foreground at '\(checkpoint)'.", file: file, line: line)
    }

    @discardableResult
    @MainActor
    private func require(_ element: XCUIElement, _ description: String,
                         timeout: TimeInterval = 10,
                         file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: timeout),
                      "Expected \(description) within \(Int(timeout))s.", file: file, line: line)
        return element
    }

    private func settle(_ seconds: UInt32) { sleep(seconds) }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String,
                         file: StaticString = #filePath, line: UInt = #line) {
        assertForeground(app, name, file: file, line: line)
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard writesPNGs else { return }
        let url = Self.qaDirectory.appendingPathComponent("\(name).png")
        try? shot.pngRepresentation.write(to: url)
    }

    @MainActor
    private func dismissLocationPromptIfPresent() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow While Using App"]
        if allow.waitForExistence(timeout: 3) { allow.tap(); return }
        let once = springboard.buttons["Allow Once"]
        if once.waitForExistence(timeout: 1) { once.tap() }
    }
}
