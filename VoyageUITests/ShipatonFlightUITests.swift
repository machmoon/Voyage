import XCTest

/// The Shipaton video's flight beat, recorded on a CI simulator next to
/// `ShipatonDemoUITests`: the miles card and weather delays on Home, the
/// if-then plan in the departure board, one bag tag per task and the peeled
/// claim check, the torn pass, a demo-length flight, baggage claim, the
/// customs recall and the stamp, then the Flight Manual.
///
/// Nothing here asserts for its own sake: it keeps going past a missed step
/// (`continueAfterFailure`) so one flaky tap costs a beat, not the recording.
/// CI (`.github/workflows/ci.yml`, job `demo`) records the screen around it and
/// trims to the `flight-start`/`flight-end` marks.
final class ShipatonFlightUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    func testAFlightWithTheLoyaltyLayer() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-VoyageHomeAirport", "SFO",
            "-VoyageLoyaltyStarter",
            "-VoyageSkipOnboarding",
            "-VoyageDemoFlight",
            "-VoyageSceneHour", "10",
            "-windowWorldMode", "illustrated",
            "-realWorldTwinEnabled", "<false/>",
            "-ambienceEnabled", "<false/>",
            "-announcementsEnabled", "<false/>",
        ]
        mark("flight-start")
        app.launch()
        dismissSystemPrompt()

        // Home: the miles card, streak and banked weather delays.
        let lax = app.buttons["destination-LAX"]
        XCTAssertTrue(lax.waitForExistence(timeout: 25))
        dismissSystemPrompt()
        pause(4)
        save("flight-00-home")

        // The departure board writes the if-then plan.
        lax.tap()
        pause(1.5)
        let schedule = app.buttons["Schedule"]
        if schedule.waitForExistence(timeout: 5) {
            schedule.tap()
            if app.staticTexts["Schedule your focus"].waitForExistence(timeout: 8) {
                pause(1.5)
                let library = app.buttons["Library"]
                if library.waitForExistence(timeout: 2), library.isHittable { library.tap() }
                pause(3)
                save("flight-01-if-then")
                app.swipeDown(velocity: .fast)
                pause(1)
                if app.staticTexts["Schedule your focus"].exists {
                    let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
                    let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
                    start.press(forDuration: 0.1, thenDragTo: end)
                    pause(1)
                }
            }
        }

        // Seat.
        let depart = app.buttons["depart-now"]
        XCTAssertTrue(depart.waitForExistence(timeout: 8))
        depart.tap()
        XCTAssertTrue(app.staticTexts["Choose your seat"].waitForExistence(timeout: 12))
        pause(1.5)
        // Seat labels read "<Cabin> seat 12A, ..."; the skip button's is
        // "Skip seat selection" and assigns the first open seat.
        let skip = app.buttons["Skip seat selection"]
        XCTAssertTrue(skip.waitForExistence(timeout: 6), "Expected the seat picker's skip button")
        skip.tap()
        XCTAssertTrue(app.textFields["Bag 1, e.g. Review chapter 4"].waitForExistence(timeout: 15),
                      "Expected check-in after the seat picker")

        // One bag tag per task.
        let bag1 = app.textFields["Bag 1, e.g. Review chapter 4"]
        if bag1.waitForExistence(timeout: 10) {
            bag1.tap()
            bag1.typeText("Finish problem set 3\n")
            pause(1.5)
            let bag2 = app.textFields["Bag 2, e.g. Review chapter 4"]
            if bag2.waitForExistence(timeout: 3) {
                bag2.tap()
                bag2.typeText("Read chapter 7\n")
            }
            pause(2.5)
            save("flight-02-bag-tags")

            // Peel the claim check across; the button is the fallback.
            let stub = app.otherElements["bag-tag-claim-stub"]
            if stub.waitForExistence(timeout: 4), stub.isHittable {
                let a = stub.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
                let b = stub.coordinate(withNormalizedOffset: CGVector(dx: 1.4, dy: 0.5))
                a.press(forDuration: 0.05, thenDragTo: b, withVelocity: 180, thenHoldForDuration: 0.1)
                pause(1.5)
            }
            let check = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Check ")).firstMatch
            if check.exists, check.isHittable, !app.buttons["Tear and board"].exists { check.tap() }
        }

        // The pass: slide along the tear line.
        let tear = app.buttons["Tear and board"]
        if tear.waitForExistence(timeout: 20) {
            pause(2)
            save("flight-03-pass")
            let cutStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.615))
            let cutEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.62))
            cutStart.press(forDuration: 0.05, thenDragTo: cutEnd, withVelocity: 140, thenHoldForDuration: 0.1)
            pause(2)
            if tear.exists, tear.isHittable { tear.tap() }
        }

        // The demo leg flies itself; landing brings the arrival flow.
        let toClaim = app.buttons["Head to baggage claim"]
        let toPassport = app.buttons["Continue to passport control"]
        _ = toClaim.waitForExistence(timeout: 300) || toPassport.waitForExistence(timeout: 5)
        pause(3)
        save("flight-04-landed")
        if toClaim.exists {
            toClaim.tap()
            pause(2.5)
            // Tear the stub on the bag you finished; leave the other one.
            let claim = app.descendants(matching: .any)["claim-tag-0"]
            if claim.waitForExistence(timeout: 6) {
                let a = claim.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.93))
                let b = claim.coordinate(withNormalizedOffset: CGVector(dx: 1.2, dy: 0.93))
                a.press(forDuration: 0.05, thenDragTo: b, withVelocity: 220, thenHoldForDuration: 0.1)
            }
            pause(3)
            save("flight-05-baggage-claim")
            if toPassport.waitForExistence(timeout: 4) { toPassport.tap() }
        } else if toPassport.exists {
            toPassport.tap()
        }

        // Customs: three quick recalls.
        if app.staticTexts["Anything to declare?"].waitForExistence(timeout: 8) {
            pause(1.5)
            let prompt = "One idea you can now explain without your notes"
            let field = app.textViews[prompt].exists ? app.textViews[prompt] : app.textFields[prompt]
            if field.waitForExistence(timeout: 3) {
                field.tap()
                field.typeText("Spacing beats cramming: review on day 1, 3 and 7")
                pause(1)
            }
            save("flight-06-customs")
            let declare = app.buttons["Declare and continue"].exists
                ? app.buttons["Declare and continue"] : app.buttons["Nothing to declare"]
            if declare.waitForExistence(timeout: 3) {
                // The keyboard can cover it.
                if !declare.isHittable { app.swipeDown() }
                declare.tap()
            }
        }

        // The passport stamp, and a tier-up card if this landing crossed one.
        pause(7)
        save("flight-07-stamp")
        if app.otherElements["tier-up-card"].waitForExistence(timeout: 3) {
            pause(4)
            save("flight-08-tier-up")
            app.swipeDown(velocity: .fast)
            pause(1)
        }
        let back = app.buttons["Back to the terminal"]
        if back.waitForExistence(timeout: 10) { back.tap() }
        pause(3)
        save("flight-09-home-after")

        // The Flight Manual: the research, cited, in the app.
        let settings = app.buttons["Settings"]
        if settings.waitForExistence(timeout: 8) {
            settings.tap()
            let manual = app.descendants(matching: .any)["settings-flight-manual"]
            for _ in 0..<8 where !(manual.exists && manual.isHittable) { app.swipeUp() }
            if manual.exists {
                manual.tap()
                pause(2.5)
                save("flight-10-manual")
                for _ in 0..<4 {
                    app.swipeUp(velocity: .slow)
                    pause(1.2)
                }
                save("flight-11-manual-more")
            }
        }
        mark("flight-end")
    }

    // MARK: Helpers

    private func mark(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SHIPATON_CAPTURE_DIR"] else { return }
        let stamp = String(format: "%.3f", Date().timeIntervalSince1970)
        try? stamp.write(toFile: dir + "/\(name).txt", atomically: true, encoding: .utf8)
    }

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

    /// Location and Focus-status prompts, the same way `ShipatonDemoUITests` does.
    @MainActor
    private func dismissSystemPrompt() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons.matching(NSPredicate(
            format: "label IN %@", ["Allow While Using App", "Allow Once", "Allow"])).firstMatch
        guard allow.waitForExistence(timeout: 3), allow.isHittable else { return }
        allow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
}
