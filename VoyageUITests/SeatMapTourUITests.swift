import XCTest

/// Captures the cabin of every aircraft, forward and aft, so the airframe and
/// the seat grid can be reviewed without flying each route by hand.
/// Artifacts land in `/Users/patliu/Desktop/Coding/Voyage/QA/`.
final class SeatMapTourUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSeatMapPerAircraft() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-VoyageShortFlights",
        ]
        app.launch()

        let card = app.buttons["destination-LAX"]
        XCTAssertTrue(card.waitForExistence(timeout: 12))
        card.tap()

        let depart = app.buttons["depart-now"]
        XCTAssertTrue(depart.waitForExistence(timeout: 6))
        depart.tap()

        XCTAssertTrue(app.staticTexts["Choose your seat"].waitForExistence(timeout: 8))

        for aircraft in ["Voyage Classic", "Boeing 737-800", "Airbus A320neo"] {
            try select(aircraft: aircraft, in: app)
            let slug = aircraft.lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .replacingOccurrences(of: "—", with: "-")

            save("qa-seatmap-\(slug)-forward")

            // Far enough aft to bring the wing box and the tailplane into view.
            let cabin = app.scrollViews.firstMatch
            XCTAssertTrue(cabin.exists, "Expected a scrollable cabin")
            cabin.swipeUp(velocity: .slow)
            sleep(1)
            save("qa-seatmap-\(slug)-wing")

            cabin.swipeUp(velocity: .slow)
            cabin.swipeUp(velocity: .slow)
            sleep(1)
            save("qa-seatmap-\(slug)-tail")

            // Back to the nose before switching type.
            cabin.swipeDown(velocity: .fast)
            cabin.swipeDown(velocity: .fast)
            cabin.swipeDown(velocity: .fast)
            cabin.swipeDown(velocity: .fast)
            sleep(1)
        }
    }

    private func select(aircraft: String, in app: XCUIApplication) throws {
        let picker = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Aircraft model"))
            .firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Expected the aircraft picker")
        picker.tap()

        // SwiftUI surfaces a Menu's Picker rows as buttons on some runtimes and
        // as menu items on others.
        let option = app.buttons[aircraft]
        if option.waitForExistence(timeout: 3) {
            option.tap()
        } else {
            let item = app.menuItems[aircraft]
            XCTAssertTrue(item.waitForExistence(timeout: 3), "No option for \(aircraft)")
            item.tap()
        }
        sleep(1)
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
}
