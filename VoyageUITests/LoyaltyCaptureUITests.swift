import XCTest

/// Captures the loyalty progression as a traveler meets it after their first
/// landing (`-VoyageLoyaltyStarter`: one landed SFO to LAX hop, locks
/// enforced): the booking rail with far destinations dimmed, a locked card's
/// notice, and the seat map with the front row of First open early.
///
/// PNGs land in `LOYALTY_CAPTURE_DIR` when set (pass it to xcodebuild as
/// `TEST_RUNNER_LOYALTY_CAPTURE_DIR`), else the repo's `QA/` directory.
final class LoyaltyCaptureUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLockedDestinationsAndEarlyUpgradeSeats() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-VoyageHomeAirport", "SFO",
            "-VoyageLoyaltyStarter",
            "-soundEffectsEnabled", "<false/>",
            "-ambienceEnabled", "<false/>",
            "-announcementsEnabled", "<false/>",
        ]
        app.launch()

        // Regional routes open, next band announced under the greeting.
        let lax = app.buttons["destination-LAX"]
        XCTAssertTrue(lax.waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["next-unlock"].exists)
        sleep(3)
        save("loyalty-01-home-locked-destinations")

        // A locked card previews the route but offers no departure.
        let yvr = app.buttons["destination-YVR"]
        XCTAssertTrue(yvr.exists)
        yvr.tap()
        XCTAssertTrue(app.descendants(matching: .any)["destination-locked-notice"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["depart-now"].exists)
        sleep(2)
        save("loyalty-02-home-locked-selected")

        // An open regional route books as before.
        lax.tap()
        let depart = app.buttons["depart-now"]
        XCTAssertTrue(depart.waitForExistence(timeout: 6))
        depart.tap()
        XCTAssertTrue(app.staticTexts["Choose your seat"].waitForExistence(timeout: 10))

        // Front row open early, the rest of First still at Silver.
        let early = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "early upgrade seat"))
        XCTAssertGreaterThan(early.count, 0, "Expected early upgrade seats in row 1")
        let silver = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "opens at Silver status"))
        XCTAssertGreaterThan(silver.count, 0, "Expected the rest of First to stay locked")
        sleep(1)
        save("loyalty-03-seatmap-early-first")

        early.firstMatch.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Take seat"))
            .firstMatch.waitForExistence(timeout: 3))
        sleep(1)
        save("loyalty-04-seatmap-early-first-selected")
    }

    private func save(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        // Same fallback as MarketingCaptureUITests: the repo's QA/ next to this file.
        let dir = ProcessInfo.processInfo.environment["LOYALTY_CAPTURE_DIR"]
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("QA").path
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
