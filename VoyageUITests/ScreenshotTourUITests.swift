import XCTest

/// Full QA screenshot tour through boarding → rip → short in-flight phases.
/// Artifacts land in `/Users/patliu/Desktop/Coding/Voyage/QA/`.
final class ScreenshotTourUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testQAScreenshotTour() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-VoyageShortFlights",
        ]
        app.launch()

        dismissLocationPromptIfPresent()

        XCTAssertTrue(app.staticTexts["VOYAGE"].waitForExistence(timeout: 10))
        sleep(1)
        save("qa-01-home")

        try selectDestinationAndDepart(in: app)
        save("qa-02-departing")

        XCTAssertTrue(app.staticTexts["Choose your seat"].waitForExistence(timeout: 6))
        let available = app.buttons.matching(NSPredicate(format: "label MATCHES %@", #"Seat [0-9]+[A-F]"#)).firstMatch
        XCTAssertTrue(available.waitForExistence(timeout: 5))
        available.tap()
        sleep(1)
        save("qa-03-seats")

        let takeSeat = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Take seat")).firstMatch
        XCTAssertTrue(takeSeat.waitForExistence(timeout: 3))
        takeSeat.tap()

        let skip = app.buttons["Travel light — skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()

        let tearHint = app.staticTexts["Pull the stub down to tear & board"]
        // Button accessibilityLabel is "Tear and board" (ampersand expanded).
        let tearButton = app.buttons["Tear and board"]
        XCTAssertTrue(
            tearHint.waitForExistence(timeout: 10) || tearButton.waitForExistence(timeout: 1),
            "Expected boarding pass"
        )
        sleep(2) // let print animation finish
        save("qa-04-boarding-pass-pre-tear")

        XCTAssertTrue(tearButton.waitForExistence(timeout: 3), "Expected Tear and board control")
        tearButton.tap()

        let ready = app.buttons["Ready for departure"]
        XCTAssertTrue(ready.waitForExistence(timeout: 8), "Expected Flight Mode after rip")
        save("qa-05-flight-mode-post-rip")
        ready.tap()

        // Short-flight takeoff (~3s) then climb (~8s total).
        sleep(2)
        save("qa-06-inflight-runway")

        sleep(5) // into climb with short flights
        save("qa-07-inflight-climb-clouds")
    }

    private func save(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let url = URL(fileURLWithPath: "/Users/patliu/Desktop/Coding/Voyage/QA/\(name).png")
        try? shot.pngRepresentation.write(to: url)
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func selectDestinationAndDepart(in app: XCUIApplication) throws {
        let codes = ["BOS", "JFK", "MIA", "LAX", "YYZ", "YVR", "YQR", "SFO"]
        var selected = false
        for code in codes {
            let card = app.buttons["destination-\(code)"]
            guard card.waitForExistence(timeout: 0.8) else { continue }
            if !card.isHittable {
                for _ in 0..<4 where !card.isHittable {
                    app.swipeLeft()
                }
            }
            guard card.isHittable else { continue }
            card.tap()
            selected = true
            break
        }
        XCTAssertTrue(selected, "Expected a hittable destination card on home")
        save("qa-02-selected")

        let depart = app.buttons["depart-now"]
        XCTAssertTrue(depart.waitForExistence(timeout: 5), "Expected Depart now after selecting a destination")
        depart.tap()
    }

    @MainActor
    private func dismissLocationPromptIfPresent() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow While Using App"]
        if allow.waitForExistence(timeout: 3) {
            allow.tap()
            return
        }
        let once = springboard.buttons["Allow Once"]
        if once.waitForExistence(timeout: 1) {
            once.tap()
        }
    }
}
