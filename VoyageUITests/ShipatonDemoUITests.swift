import XCTest

/// The Shipaton video beat, end to end against RevenueCat's Test Store:
/// a locked First seat → the upgrade offer (earn it, or fly First) → the
/// dashboard paywall → the Test Store purchase alert → the seat unlocks →
/// Settings shows Voyage First Active.
///
/// CI (`.github/workflows/ci.yml`, job `demo`) records the simulator screen
/// with `xcrun simctl io … recordVideo` while this runs. PNGs land in
/// `SHIPATON_CAPTURE_DIR` (pass `TEST_RUNNER_SHIPATON_CAPTURE_DIR` to
/// xcodebuild), else the repo's `QA/` directory.
///
/// The purchase alert is RevenueCat's own (purchases-ios 5.91.0,
/// `Sources/Purchasing/SimulatedStore/SimulatedStorePurchaseUI.swift`:
/// title "Test Store Purchase", action "Test valid purchase"), tapped the way
/// RevenueCat's rc-maestro flow does
/// (`Examples/rc-maestro/maestro/utils/confirm_purchase.yaml`).
final class ShipatonDemoUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLockedSeatToVoyageFirstActive() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-VoyageHomeAirport", "SFO",
            "-VoyageLoyaltyStarter",
            "-VoyageSkipOnboarding",
            "-ambienceEnabled", "<false/>",
            "-announcementsEnabled", "<false/>",
        ]
        app.launch()
        dismissLocationPromptIfPresent()

        // Home: the miles card, then book the open regional hop.
        let lax = app.buttons["destination-LAX"]
        XCTAssertTrue(lax.waitForExistence(timeout: 25))
        pause(2)
        save("shipaton-00-home")
        lax.tap()
        let depart = app.buttons["depart-now"]
        XCTAssertTrue(depart.waitForExistence(timeout: 8))
        pause(1)
        depart.tap()
        XCTAssertTrue(app.staticTexts["Choose your seat"].waitForExistence(timeout: 12))
        pause(1.5)
        save("shipaton-01-seatmap-locked")

        // 1. Tap a First seat that only Silver opens.
        let locked = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "opens at Silver status"))
        XCTAssertGreaterThan(locked.count, 0, "Expected locked First seats")
        let target = locked.firstMatch
        let seatID = seatName(from: target.label)
        target.tap()

        // 2. The upgrade offer: both ways to the front.
        let offer = app.staticTexts["upgrade-offer-title"]
        XCTAssertTrue(offer.waitForExistence(timeout: 6), "Expected the upgrade offer")
        pause(3)
        save("shipaton-02-upgrade-offer")

        // 3. RevenueCat's dashboard paywall.
        let see = app.buttons["upgrade-see-voyage-first"]
        XCTAssertTrue(see.waitForExistence(timeout: 4))
        XCTAssertTrue(see.isEnabled, "The build under test must carry the Test Store key (Debug)")
        see.tap()
        let buy = purchaseButton(in: app)
        XCTAssertTrue(buy.waitForExistence(timeout: 30), "Expected RevenueCat's paywall with a purchase button")
        pause(3)
        save("shipaton-03-paywall")
        buy.tap()

        // 4. Test Store: simulated purchase.
        let alert = app.alerts["Test Store Purchase"].exists ? app.alerts["Test Store Purchase"] : app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 20), "Expected the Test Store purchase alert")
        pause(2)
        save("shipaton-04-test-store-purchase")
        let valid = alert.buttons["Test valid purchase"]
        XCTAssertTrue(valid.waitForExistence(timeout: 3))
        valid.tap()

        // 5. The seat unlocks, with the burst and the chime.
        let unlocked = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@", "Take seat \(seatID)")).firstMatch
        XCTAssertTrue(unlocked.waitForExistence(timeout: 30), "Expected \(seatID) selected after the purchase")
        pause(0.6)
        save("shipaton-05-seat-unlocked")
        pause(2.5)
        save("shipaton-06-first-open")

        // 6. Settings: Voyage First Active, with Customer Center.
        app.buttons["Cancel booking"].tap()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let status = app.descendants(matching: .any)["settings-first-class-status"]
        for _ in 0..<8 where !(status.exists && status.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(status.waitForExistence(timeout: 6))
        XCTAssertTrue(status.label.contains("Active"), "Settings should say Active, got \(status.label)")
        pause(2)
        save("shipaton-07-settings-active")

        let manage = app.buttons["settings-customer-center"]
        if manage.waitForExistence(timeout: 3) {
            manage.tap()
            pause(4)
            save("shipaton-08-customer-center")
        }
    }

    // MARK: Helpers

    /// "First class seat B2, locked, opens at Silver status" → "B2".
    private func seatName(from label: String) -> String {
        let afterSeat = label.components(separatedBy: "seat ").dropFirst().first ?? ""
        return afterSeat.components(separatedBy: ",").first ?? ""
    }

    /// The paywall's purchase button. Its title is whatever the dashboard
    /// paywall says, so match the common ones, the spec's two, and RevenueCat's
    /// default ("Continue", which rc-maestro taps).
    private func purchaseButton(in app: XCUIApplication) -> XCUIElement {
        let words = ["Start 7-day free trial", "Fly First", "Continue", "Subscribe", "Purchase",
                     "Start", "Try"]
        let format = words.map { _ in "label BEGINSWITH[c] %@" }.joined(separator: " OR ")
        return app.buttons.matching(NSPredicate(format: format, argumentArray: words)).firstMatch
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

    /// CI grants location up front (`simctl privacy … grant location`), so
    /// this only matters on a local simulator. It never taps a button it has
    /// not just seen hittable: the prompt can vanish between the query and
    /// the tap, and a failed tap would fail the whole recording.
    @MainActor
    private func dismissLocationPromptIfPresent() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons.matching(NSPredicate(
            format: "label IN %@", ["Allow While Using App", "Allow Once"])).firstMatch
        guard allow.waitForExistence(timeout: 3), allow.isHittable else { return }
        allow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
}
