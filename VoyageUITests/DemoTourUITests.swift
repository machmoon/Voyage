import XCTest

/// Social demo beat sheet (~25–27s of app action). Pair with simctl recordVideo;
/// title + product + endcard land at ~30s shareable total.
///
/// Beats (approx, after launch settle):
///   0–2s   Home / brand
///   2–5s   Destination → Depart now
///   5–8s   Seat pick → Take seat
///   8–9s   Skip bags
///   9–13s  Boarding pass print linger → Tear
///  13–17s  Curtain → takeoff roll → climb window
///  17–22s  Hold climb / early cruise window
///  22–27s  Map view tease (route), brief hold
final class DemoTourUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    func testSocialDemoTour() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-VoyageShortFlights",
        ]
        app.launch()

        dismissSystemAlerts()
        pause(0.8)

        // Home / brand beat
        XCTAssertTrue(app.staticTexts["VOYAGE"].waitForExistence(timeout: 8))
        pause(1.6)

        let cards = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "destination-"))
        let card = cards.firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 4))
        card.tap()
        pause(1.0)

        let depart = app.buttons["depart-now"]
        XCTAssertTrue(depart.waitForExistence(timeout: 4))
        depart.tap()
        pause(1.0)

        // Seat selection — readable, not rushed
        // SeatSelectionView.swift:111.
        XCTAssertTrue(app.staticTexts["Choose your seat"].waitForExistence(timeout: 5))
        pause(0.6)
        let economy = app.buttons.matching(
            NSPredicate(format: "label MATCHES %@", #"Seat [A-D](1[0-2]|[3-9])"#)
        ).firstMatch
        if economy.waitForExistence(timeout: 2) {
            economy.tap()
        } else {
            app.buttons.matching(NSPredicate(format: "label MATCHES %@", #"Seat [A-D][0-9]+"#))
                .firstMatch.tap()
        }
        pause(0.7)

        let takeSeat = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Take seat")).firstMatch
        XCTAssertTrue(takeSeat.waitForExistence(timeout: 3))
        takeSeat.tap()

        // Skip bags — keep boarding moving
        // CheckBagView.swift:84. The tour packs nothing, so the button reads
        // "Skip for now"; it becomes "Check N bags" only once something is in.
        let continueWithoutBags = app.buttons["Skip for now"]
        XCTAssertTrue(continueWithoutBags.waitForExistence(timeout: 4))
        pause(0.5)
        continueWithoutBags.tap()

        let stub = app.otherElements["boarding-pass-stub"]
        XCTAssertTrue(stub.waitForExistence(timeout: 10))
        pause(2.0) // printer finish + linger on pass
        // The button reads "Tear & board"; its accessibility label is
        // "Tear and board" (BoardingPassView.swift:89), which is what the
        // accessibility tree carries. Match the label.
        let tear = app.buttons["Tear and board"]
        XCTAssertTrue(tear.waitForExistence(timeout: 5))
        tear.tap()

        // Curtain → takeoff (~3s short) → climb (through ~8s elapsed)
        pause(3.2)
        pause(4.0)

        // Map tease — second study view, then hold so the route reads
        let mapToggle = app.buttons["Map view"]
        if mapToggle.waitForExistence(timeout: 3) {
            mapToggle.tap()
            pause(4.5)
        } else {
            // Still on window — hold cruise a bit longer so the cut stays full
            pause(4.5)
        }
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    @MainActor
    private func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow While Using App", "Allow Once", "Allow", "Don’t Allow", "Don't Allow"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 1.2) {
                // Prefer Allow for location; Don't Allow for Focus share (keeps demo clean).
                if label.hasPrefix("Allow") && !label.contains("Don’t") && !label.contains("Don't") {
                    if label == "Allow" {
                        // Focus Status — dismiss without granting to skip follow-ups.
                        let dont = springboard.buttons["Don’t Allow"]
                        let dont2 = springboard.buttons["Don't Allow"]
                        if dont.waitForExistence(timeout: 0.3) { dont.tap(); return }
                        if dont2.waitForExistence(timeout: 0.3) { dont2.tap(); return }
                    }
                    button.tap()
                    return
                }
            }
        }
        // Focus Status may appear after location — second pass.
        let dontAllow = springboard.buttons["Don’t Allow"]
        if dontAllow.waitForExistence(timeout: 1.5) { dontAllow.tap(); return }
        let dontAllow2 = springboard.buttons["Don't Allow"]
        if dontAllow2.waitForExistence(timeout: 0.5) { dontAllow2.tap() }
    }
}
