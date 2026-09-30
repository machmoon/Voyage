import XCTest

/// Captures the check-bag bag tag for design review: freshly printed, with
/// bags written on it, and mid-peel. Skipped unless `BAGTAG_OUT` names a
/// directory (pass it as `TEST_RUNNER_BAGTAG_OUT` to xcodebuild), so it never
/// writes anywhere during an ordinary test run.
///
/// `BAGTAG_HOME` / `BAGTAG_DEST` pick the route (defaults SFO to YQR, a
/// connection over YVR); `BAGTAG_PREFIX` names the files.
final class BagTagScreenshotUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureBagTag() throws {
        let env = ProcessInfo.processInfo.environment
        guard let out = env["BAGTAG_OUT"], !out.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_BAGTAG_OUT to capture bag tag screenshots.")
        }
        let home = env["BAGTAG_HOME"] ?? "SFO"
        let dest = env["BAGTAG_DEST"] ?? "YQR"
        let prefix = env["BAGTAG_PREFIX"] ?? "bagtag"

        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                                "-VoyageSkipOnboarding", "-VoyageShortFlights",
                                "-VoyageHomeAirport", home, "-VoyageSlowPeel"]
        app.launch()
        dismissLocationPromptIfPresent()

        let card = app.buttons["destination-\(dest)"]
        XCTAssertTrue(card.waitForExistence(timeout: 12), "destination card \(dest)")
        let scroller = app.scrollViews.firstMatch
        var swipes = 0
        // Short drags toward the card from whichever side it is off, with a
        // settle each time: a long fling overshoots the rail.
        while !app.frame.contains(card.frame) && swipes < 12 {
            let goRight = card.frame.midX > app.frame.midX
            let from = CGVector(dx: goRight ? 0.75 : 0.25, dy: 0.5)
            let to = CGVector(dx: goRight ? 0.45 : 0.55, dy: 0.5)
            scroller.coordinate(withNormalizedOffset: from)
                .press(forDuration: 0.1, thenDragTo: scroller.coordinate(withNormalizedOffset: to),
                       withVelocity: .slow, thenHoldForDuration: 0.1)
            pause(0.6)
            swipes += 1
        }
        card.tap()
        let depart = app.buttons["depart-now"]
        XCTAssertTrue(depart.waitForExistence(timeout: 6))
        depart.tap()

        let seat = app.buttons.matching(NSPredicate(format: "label MATCHES %@", #"Seat [A-D][0-9]+"#)).firstMatch
        XCTAssertTrue(seat.waitForExistence(timeout: 12))
        seat.tap()
        let takeSeat = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Take seat")).firstMatch
        XCTAssertTrue(takeSeat.waitForExistence(timeout: 4))
        takeSeat.tap()

        // Mid-feed, then printed.
        XCTAssertTrue(app.buttons["Skip for now"].waitForExistence(timeout: 8))
        pause(0.55)
        save(out, "\(prefix)-1-printing")
        pause(1.6)
        save(out, "\(prefix)-2-printed")

        let bag1 = app.textFields["Bag 1, e.g. Review chapter 4"]
        XCTAssertTrue(bag1.waitForExistence(timeout: 4))
        bag1.tap()
        bag1.typeText("Finish problem set 4")
        let bag2 = app.textFields["Bag 2, e.g. Review chapter 4"]
        bag2.tap()
        bag2.typeText("Read chapter 9\n")
        pause(0.4)
        save(out, "\(prefix)-3-typing")
        // Return prints the line's tag and drops the keyboard, so the third
        // line is tapped first.
        let bag3 = app.textFields["Bag 3, e.g. Review chapter 4"]
        bag3.tap()
        bag3.typeText("Outline the essay\n")
        pause(0.8)
        save(out, "\(prefix)-4-written")

        let check = app.buttons["Check 3 bags"]
        XCTAssertTrue(check.waitForExistence(timeout: 3))
        // Launched with -VoyageSlowPeel, so the ~0.9 s peel runs ~7 s.
        check.tap()
        save(out, "\(prefix)-5-peeling")
        pause(1.2)
        save(out, "\(prefix)-6-peeled")

        XCTAssertTrue(app.otherElements["boarding-pass-stub"].waitForExistence(timeout: 15))
    }

    private func pause(_ seconds: TimeInterval) {
        let done = expectation(description: "pause")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 2)
    }

    private func save(_ dir: String, _ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
        try? shot.pngRepresentation.write(to: url)
    }

    private func dismissLocationPromptIfPresent() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow While Using App", "Allow Once"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 3) {
                button.tap()
                return
            }
        }
    }
}
