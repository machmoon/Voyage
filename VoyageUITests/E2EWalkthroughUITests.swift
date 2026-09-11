import XCTest

/// End-to-end human-equivalent walkthrough.
///
/// Deliberately covers only ground the existing tours do NOT cover, because
/// `ScreenshotTourUITests` already walks booking -> in-flight and demo-flight ->
/// arrival. What has never been exercised anywhere in this repo:
///
/// 1. A genuinely fresh first run with every permission DENIED.
/// 2. A diversion triggered by really backgrounding the app.
/// 3. Any accessibility text size.
/// 4. Light appearance.
/// 5. The settings toggles.
/// 6. A connecting route, its layover, and the missed connection.
///
/// Every step screenshots and every checkpoint asserts the app is still in the
/// foreground, for the reason spelled out in `ScreenshotTourUITests`: a run that
/// cannot fail launders a crash into a green check.
///
/// PNGs go to `VOYAGE_QA_DIR` when set, otherwise `QA/` beside the checkout.
final class E2EWalkthroughUITests: XCTestCase {

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

    private static let localeArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]

    /// Same rationale as `ScreenshotTourUITests.mutedAudioArguments`: CoreAudio
    /// in the simulator can `abort()` the process on a host RPC timeout, which
    /// is not a Voyage defect but kills the run. `<false/>` and not `0`.
    private static let mutedAudioArguments = [
        "-ambienceEnabled", "<false/>",
        "-soundEffectsEnabled", "<false/>",
        "-announcementsEnabled", "<false/>",
    ]

    private static let originArguments = ["-VoyageHomeAirport", "SFO"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        writesPNGs = (try? FileManager.default.createDirectory(
            at: Self.qaDirectory, withIntermediateDirectories: true)) != nil
    }

    // MARK: - 1. Fresh first run, every permission denied

    /// No `-VoyageHomeAirport`, so onboarding runs and Core Location is really
    /// consulted. Every system alert is answered with the most restrictive
    /// option, which is the path no tour has ever taken.
    @MainActor
    func testE01_FreshFirstRunWithPermissionsDenied() throws {
        let app = XCUIApplication()
        app.launchArguments += Self.localeArguments + Self.mutedAudioArguments
            + ["-VoyageResetOnboarding"]
        app.launch()

        // Whatever alert is first, deny it, then keep denying until quiet.
        denyAllSystemAlerts(for: 20)
        save("e2e-01-onboarding-page1")
        traceState(app, "after-deny", seconds: 5)
        assertForeground(app, "launch with permissions denied")

        // Page 2 of onboarding.
        app.swipeLeft()
        settle(1)
        denyAllSystemAlerts(for: 3)
        capture(app, "e2e-02-onboarding-page2")

        let start = app.buttons["Start flying"]
        if start.waitForExistence(timeout: 5) {
            start.tap()
        } else {
            let cont = app.buttons["Continue"]
            require(cont, "Continue or Start flying on onboarding", timeout: 5)
            cont.tap()
            settle(1)
            let start2 = app.buttons["Start flying"]
            require(start2, "Start flying on the last onboarding page", timeout: 8)
            start2.tap()
        }

        denyAllSystemAlerts(for: 8)
        require(app.staticTexts["VOYAGE"], "the VOYAGE home header after onboarding", timeout: 25)
        settle(2)
        capture(app, "e2e-03-home-permissions-denied")

        // Scroll the home screen so the destination rail and any banners show.
        app.swipeUp()
        settle(1)
        capture(app, "e2e-04-home-scrolled-permissions-denied")

        // The schedule sheet promises a reminder; with notifications denied it
        // should not. Open it and look.
        openScheduleSheetIfReachable(in: app, name: "e2e-05-schedule-notifications-denied")

        assertForeground(app, "end of denied-permissions first run")
    }

    // MARK: - 2. Diversion by really backgrounding

    @MainActor
    func testE02_DiversionByBackgrounding() throws {
        let app = XCUIApplication()
        app.launchArguments += Self.localeArguments + Self.mutedAudioArguments
            + Self.originArguments + ["-VoyageShortFlights"]
        app.launch()
        denyAllSystemAlerts(for: 6)

        try boardAFlight(in: app, prefix: "e2e-06")
        settle(4)
        capture(app, "e2e-07-inflight-before-background")

        // Really leave. 30s grace + margin.
        XCUIDevice.shared.press(.home)
        settle(38)
        let resumeStart = Date()
        app.activate()
        // How long the app takes to come back matters: this is the exact moment
        // a diverted user is looking at the screen. Poll instead of guessing.
        let resumed = app.wait(for: .runningForeground, timeout: 30)
        if !resumed { capture(app, "e2e-08-resume-failure") }
        let resumeSeconds = Date().timeIntervalSince(resumeStart)
        let timing = XCTAttachment(string: String(format: "resume took %.2fs, resumed=%@",
                                                  resumeSeconds, resumed ? "yes" : "no"))
        timing.name = "resume-timing"
        timing.lifetime = .keepAlways
        add(timing)
        XCTAssertTrue(resumed,
                      String(format: "Voyage never returned to the foreground within 30s of "
                             + "activate() after a 38s background (took %.2fs, state %d).",
                             resumeSeconds, app.state.rawValue))
        settle(2)
        capture(app, "e2e-08-diverted")

        // The only way out should be Back to the terminal.
        let back = app.buttons["Back to the terminal"]
        require(back, "Back to the terminal on the diverted screen", timeout: 10)
        back.tap()
        settle(2)
        require(app.staticTexts["VOYAGE"], "Home after a diversion", timeout: 15)
        capture(app, "e2e-09-home-after-divert")
    }

    // MARK: - 3. Accessibility text size sweep

    /// Every crafted surface at `accessibilityLarge`. Nothing in this repo has
    /// ever been captured above the default size.
    @MainActor
    func testE03_AccessibilityTextSizeSweep() throws {
        let app = XCUIApplication()
        app.launchArguments += Self.localeArguments + Self.mutedAudioArguments
            + Self.originArguments + ["-VoyageShortFlights"]
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityL",
        ]
        app.launch()
        denyAllSystemAlerts(for: 6)

        require(app.staticTexts["VOYAGE"], "home header at AX-L", timeout: 25)
        settle(2)
        capture(app, "e2e-ax-01-home")

        openScheduleSheetIfReachable(in: app, name: "e2e-ax-02-schedule")

        try selectDestinationAndDepart(in: app)
        require(app.staticTexts["Choose your seat"], "the seat map at AX-L", timeout: 15)
        settle(1)
        capture(app, "e2e-ax-03-seatmap")

        let available = app.buttons
            .matching(NSPredicate(format: "label MATCHES %@", #"Seat [A-D][0-9]+"#))
            .firstMatch
        require(available, "a selectable seat at AX-L", timeout: 10)
        available.tap()
        settle(1)
        capture(app, "e2e-ax-04-seat-selected")

        let takeSeat = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Take seat"))
            .firstMatch
        require(takeSeat, "the seat CTA at AX-L", timeout: 8)
        takeSeat.tap()
        settle(1)
        capture(app, "e2e-ax-05-checkbag")

        let skip = app.buttons["Skip for now"]
        require(skip, "the bag skip at AX-L", timeout: 10)
        skip.tap()

        let tear = app.buttons["Tear and board"]
        require(tear, "the boarding pass at AX-L", timeout: 25)
        settle(1)
        capture(app, "e2e-ax-06-boarding-pass")
        tear.tap()
        settle(6)
        capture(app, "e2e-ax-07-inflight-window")

        let mapToggle = app.buttons["Map view"]
        require(mapToggle, "the map toggle at AX-L", timeout: 10)
        mapToggle.tap()
        settle(3)
        capture(app, "e2e-ax-08-inflight-map")

        assertForeground(app, "end of the AX sweep")
    }

    // MARK: - 4. Light appearance sweep

    @MainActor
    func testE04_LightAppearanceSweep() throws {
        let app = XCUIApplication()
        app.launchArguments += Self.localeArguments + Self.mutedAudioArguments
            + Self.originArguments + ["-VoyageShortFlights"]
        app.launch()
        denyAllSystemAlerts(for: 6)

        require(app.staticTexts["VOYAGE"], "home header in light mode", timeout: 25)
        settle(2)
        capture(app, "e2e-light-01-home")

        openLogbookIfReachable(in: app, name: "e2e-light-02-logbook")
        openSettingsIfReachable(in: app, name: "e2e-light-03-settings")

        assertForeground(app, "end of the light sweep")
    }

    // MARK: - 5. Settings sweep

    @MainActor
    func testE05_SettingsSweep() throws {
        let app = XCUIApplication()
        app.launchArguments += Self.localeArguments + Self.mutedAudioArguments
            + Self.originArguments
        app.launch()
        denyAllSystemAlerts(for: 6)
        require(app.staticTexts["VOYAGE"], "home header", timeout: 25)

        // Retry loop: a late-arriving system alert invalidates the element
        // mid-tap ("no longer valid after interruption handling").
        var opened = false
        for _ in 0..<5 where !opened {
            denyAllSystemAlerts(for: 3)
            let settings = app.buttons["Settings"]
            if settings.waitForExistence(timeout: 8) && settings.isHittable {
                settings.tap()
                opened = app.staticTexts["Settings"].waitForExistence(timeout: 5)
            }
        }
        XCTAssertTrue(opened, "Could not open Settings from the Home header after 5 attempts.")
        settle(2)
        capture(app, "e2e-set-01-top")

        // Toggle every switch that is on screen, screenshotting as we go, and
        // scroll down through the whole form.
        for pass in 0..<8 {
            let switches = app.switches.allElementsBoundByIndex
            for sw in switches where sw.isHittable {
                sw.tap()
                settle(1)
            }
            capture(app, String(format: "e2e-set-%02d-pass", pass + 2))
            assertForeground(app, "settings pass \(pass)")
            app.swipeUp()
            settle(1)
        }
        capture(app, "e2e-set-99-bottom")
        assertForeground(app, "end of the settings sweep")
    }

    // MARK: - 6. Logbook, passport and replay from the stamp

    @MainActor
    func testE06_LogbookPassportReplay() throws {
        let app = XCUIApplication()
        app.launchArguments += Self.localeArguments + Self.mutedAudioArguments
            + Self.originArguments + ["-VoyageDebugStamp"]
        app.launch()
        denyAllSystemAlerts(for: 6)
        settle(3)
        capture(app, "e2e-lb-01-stamp")

        let back = app.buttons["Back to the terminal"]
        require(back, "Back to the terminal after the stamp", timeout: 20)
        back.tap()
        settle(2)
        require(app.staticTexts["VOYAGE"], "Home after the stamp", timeout: 15)

        openLogbookIfReachable(in: app, name: "e2e-lb-02-logbook")

        // Passport tab.
        let passport = app.buttons["Passport"]
        if passport.waitForExistence(timeout: 5) {
            passport.tap()
            settle(2)
            capture(app, "e2e-lb-03-passport")
            let flights = app.buttons["Flights"]
            if flights.exists { flights.tap(); settle(1) }
        }

        // Replay, if a row offers one.
        let replay = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Replay"))
            .firstMatch
        if replay.waitForExistence(timeout: 5) {
            replay.tap()
            settle(4)
            capture(app, "e2e-lb-04-replay")
            assertForeground(app, "inside the replay")
        }
        assertForeground(app, "end of the logbook sweep")
    }

    // MARK: - 7. Connection: layover and missed connection

    /// `SFO -> YQR` routes via `YVR` (`RouteCatalog.swift:248`), so it is the
    /// cheapest way to reach the lounge. `-VoyageDemoFlight` clamps the leg to
    /// 60s and the layover to 20s (`FlightSession.swift:220`).
    @MainActor
    func testE07_LayoverAndMissedConnection() throws {
        let app = XCUIApplication()
        app.launchArguments += Self.localeArguments + Self.mutedAudioArguments
            + Self.originArguments + ["-VoyageDemoFlight"]
        app.launch()
        denyAllSystemAlerts(for: 6)

        require(app.staticTexts["VOYAGE"], "the VOYAGE home header", timeout: 25)
        let yqr = app.buttons["destination-YQR"]
        require(yqr, "the YQR destination card (the only connecting route)", timeout: 10)
        // Move the target fully into the viewport and tap the element itself.
        // A blind full-width swipe plus an offscreen coordinate tapped YYZ,
        // producing a nonstop flight while this test expected a connection.
        let rail = app.scrollViews.firstMatch
        for _ in 0..<8 {
            let frame = yqr.frame
            if frame.minX >= 0 && frame.maxX <= app.frame.width { break }
            let movingLeft = frame.maxX > app.frame.width
            rail.coordinate(withNormalizedOffset: CGVector(dx: movingLeft ? 0.75 : 0.3, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo:
                    rail.coordinate(withNormalizedOffset: CGVector(dx: movingLeft ? 0.3 : 0.75, dy: 0.5)))
        }
        XCTAssertTrue(yqr.isHittable, "The Regina connection must be visible before booking")
        yqr.tap()
        settle(1)
        capture(app, "e2e-lay-01-connection-selected")

        let depart = app.buttons["depart-now"]
        require(depart, "Depart now for the connecting route", timeout: 10)
        depart.tap()

        require(app.staticTexts["Choose your seat"], "the seat map", timeout: 15)
        let seat = app.buttons
            .matching(NSPredicate(format: "label MATCHES %@", #"Seat [A-D][0-9]+"#))
            .firstMatch
        require(seat, "a selectable seat", timeout: 10)
        seat.tap()
        settle(1)
        let takeSeat = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Take seat"))
            .firstMatch
        require(takeSeat, "the seat CTA", timeout: 8)
        takeSeat.tap()
        let skip = app.buttons["Skip for now"]
        require(skip, "the bag skip", timeout: 12)
        skip.tap()
        let tear = app.buttons["Tear and board"]
        require(tear, "the boarding pass", timeout: 25)
        tear.tap()
        settle(5)
        capture(app, "e2e-lay-02-leg1-inflight")

        // Leg 1 should be 60s under -VoyageDemoFlight. Wait it out and land in
        // the lounge.
        //
        // These are assertions, not just captures. The first version of this
        // test only captured and asserted foreground, so it reported PASSED
        // while every frame it saved was the in-flight window and it had
        // reached neither the lounge nor the missed connection. That is exactly
        // the "a test that cannot fail launders a miss into a green check"
        // problem this whole lane exists to avoid, committed by this lane.
        settle(70)
        assertForeground(app, "at the end of leg 1")
        capture(app, "e2e-lay-03-lounge")
        require(app.staticTexts["VOYAGE LOUNGE"],
                "the layover lounge after leg 1 (LayoverLoungeView.swift:41)",
                timeout: 30)

        // Then do nothing at all: the 20s layover plus the 3-minute final call
        // window should expire into a missed connection.
        settle(30)
        capture(app, "e2e-lay-04-lounge-final-call")
        settle(180)
        assertForeground(app, "after the final call window")
        capture(app, "e2e-lay-05-missed-connection")
        require(app.staticTexts["Connection missed"],
                "the missed-connection screen after the final call window expires",
                timeout: 60)
    }

    // MARK: - Shared steps

    @MainActor
    private func boardAFlight(in app: XCUIApplication, prefix: String) throws {
        require(app.staticTexts["VOYAGE"], "the VOYAGE home header", timeout: 25)
        try selectDestinationAndDepart(in: app)
        require(app.staticTexts["Choose your seat"], "the seat map", timeout: 15)
        let available = app.buttons
            .matching(NSPredicate(format: "label MATCHES %@", #"Seat [A-D][0-9]+"#))
            .firstMatch
        require(available, "a selectable seat", timeout: 10)
        available.tap()
        settle(1)
        let takeSeat = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Take seat"))
            .firstMatch
        require(takeSeat, "the seat CTA", timeout: 8)
        takeSeat.tap()
        let skip = app.buttons["Skip for now"]
        require(skip, "the bag skip", timeout: 12)
        skip.tap()
        let tear = app.buttons["Tear and board"]
        require(tear, "the boarding pass", timeout: 25)
        capture(app, "\(prefix)-pass")
        tear.tap()
        settle(3)
        assertForeground(app, "just after the rip")
    }

    @MainActor
    private func selectDestinationAndDepart(in app: XCUIApplication) throws {
        // Destination cards carry `destination-<CODE>` (HomeView.swift:510).
        // An earlier version of this looked for a button labelled "Fly to",
        // which the app has never shipped; it silently fell through to the code
        // loop and cost eight seconds a run. Identifiers only.
        var tapped = false
        for code in ["LAX", "SEA", "YVR", "JFK"] {
            let card = app.buttons["destination-\(code)"]
            if card.waitForExistence(timeout: 8), card.isHittable {
                card.tap()
                tapped = true
                break
            }
        }
        XCTAssertTrue(tapped, "No destination card on the rail was tappable.")
        settle(2)
        // HomeView.swift:478-495 names this "Depart now" with the identifier
        // `depart-now`, and it only exists once `selectedItinerary != nil`
        // (HomeView.swift:383). The older tours tap a button labelled "Board",
        // which is a different control (HomeView.swift:318).
        let candidates: [XCUIElement] = [
            app.buttons["depart-now"],
            app.buttons["Depart now"],
            app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Depart")).firstMatch,
            app.buttons["Board"],
        ]
        for candidate in candidates where candidate.waitForExistence(timeout: 4) {
            candidate.tap()
            return
        }
        // Nothing matched: record what was actually on screen rather than
        // failing blind.
        save("diag-no-depart-button")
        let dump = XCTAttachment(string: app.debugDescription)
        dump.name = "accessibility-tree-no-depart-button"
        dump.lifetime = .keepAlways
        add(dump)
        XCTFail("No Depart now / Board control after selecting a destination. "
                + "Accessibility tree and screenshot attached.")
    }

    @MainActor
    private func openScheduleSheetIfReachable(in app: XCUIApplication, name: String) {
        // HomeView.swift:471 labels this "Schedule"; the other two were
        // guesses and neither ships.
        for label in ["Schedule"] {
            let b = app.buttons[label]
            if b.waitForExistence(timeout: 3) && b.isHittable {
                b.tap()
                settle(2)
                capture(app, name)
                dismissSheet(in: app)
                return
            }
        }
        XCTContext.runActivity(named: "\(name): schedule sheet not reachable") { _ in }
    }

    @MainActor
    private func openLogbookIfReachable(in app: XCUIApplication, name: String) {
        if tapWithRetry(app.buttons["Open logbook"], in: app)
            || tapWithRetry(app.buttons["Logbook"], in: app) {
            settle(2)
            capture(app, name)
            dismissSheet(in: app)
        } else {
            XCTContext.runActivity(named: "\(name): Logbook not reachable") { _ in }
        }
    }

    /// Taps through late-arriving system alerts, which invalidate an element
    /// mid-tap with "no longer valid after interruption handling".
    @MainActor
    @discardableResult
    private func tapWithRetry(_ element: XCUIElement,
                              in app: XCUIApplication,
                              attempts: Int = 4) -> Bool {
        for _ in 0..<attempts {
            denyAllSystemAlerts(for: 2)
            guard element.waitForExistence(timeout: 6), element.isHittable else { continue }
            element.tap()
            return true
        }
        return false
    }

    @MainActor
    private func openSettingsIfReachable(in app: XCUIApplication, name: String) {
        let b = app.buttons["Settings"]
        if b.waitForExistence(timeout: 6) && b.isHittable {
            b.tap()
            settle(2)
            capture(app, name)
            dismissSheet(in: app)
        } else {
            XCTContext.runActivity(named: "\(name): Settings not reachable") { _ in }
        }
    }

    @MainActor
    private func dismissSheet(in app: XCUIApplication) {
        let done = app.buttons["Done"]
        if done.exists && done.isHittable {
            done.tap()
        } else {
            app.swipeDown()
        }
        settle(1)
    }

    /// Answer every system alert with the most restrictive option available,
    /// repeatedly, for `seconds`. Fresh-install runs stack Focus, Location and
    /// Notification prompts, and they do not all arrive at once.
    @MainActor
    private func denyAllSystemAlerts(for seconds: Int) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let denyLabels = ["Don't Allow", "Don’t Allow", "Not Now", "Cancel"]
        let deadline = Date().addingTimeInterval(TimeInterval(seconds))
        var quietRounds = 0
        while Date() < deadline && quietRounds < 3 {
            var handled = false
            for label in denyLabels {
                let button = springboard.buttons[label]
                if button.exists && button.isHittable {
                    button.tap()
                    handled = true
                    break
                }
            }
            if handled {
                quietRounds = 0
            } else {
                quietRounds += 1
            }
            usleep(700_000)
        }
    }

    /// Records `app.state` every second for `seconds`, so a run that loses the
    /// app says WHEN it lost it instead of only that it is gone.
    private func traceState(_ app: XCUIApplication, _ label: String, seconds: Int) {
        var trace: [String] = []
        for i in 0..<seconds {
            trace.append("t+\(i)s state=\(app.state.rawValue)")
            if app.state != .runningForeground { break }
            sleep(1)
        }
        let attachment = XCTAttachment(string: trace.joined(separator: "\n"))
        attachment.name = "state-trace-\(label)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Plumbing

    private func assertForeground(_ app: XCUIApplication,
                                 _ checkpoint: String,
                                 file: StaticString = #filePath,
                                 line: UInt = #line) {
        XCTAssertEqual(
            app.state, .runningForeground,
            "Voyage is not in the foreground at checkpoint '\(checkpoint)' (state rawValue "
            + "\(app.state.rawValue)).",
            file: file, line: line
        )
    }

    @discardableResult
    @MainActor
    private func require(_ element: XCUIElement,
                         _ description: String,
                         timeout: TimeInterval = 10,
                         file: StaticString = #filePath,
                         line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            "Expected \(description) within \(Int(timeout))s.",
            file: file, line: line
        )
        return element
    }

    private func settle(_ seconds: UInt32) { sleep(seconds) }

    private func capture(_ app: XCUIApplication,
                         _ name: String,
                         file: StaticString = #filePath,
                         line: UInt = #line) {
        assertForeground(app, name, file: file, line: line)
        save(name)
    }

    private func save(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        guard writesPNGs else { return }
        let url = Self.qaDirectory.appendingPathComponent("\(name).png")
        try? shot.pngRepresentation.write(to: url)
    }
}
