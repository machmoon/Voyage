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

        for aircraft in ["Voyage Classic", "Boeing 737-800", "Airbus A320neo", "Boom Overture"] {
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
            if aircraft == "Voyage Classic" {
                try assertWingDoesNotStealTouches(app: app, cabin: cabin)
            }

            // Aft wing root, where the trailing edge passes the rows behind
            // the exits.
            cabin.swipeUp(velocity: .slow)
            sleep(1)
            save("qa-seatmap-\(slug)-aft-wing")

            cabin.swipeUp(velocity: .slow)
            cabin.swipeUp(velocity: .slow)
            sleep(1)
            save("qa-seatmap-\(slug)-tail")

            // Back to the nose before switching type.
            for _ in 0..<5 { cabin.swipeDown(velocity: .fast) }
            sleep(1)
        }
    }

    /// The wing is drawn behind the window seats and far past the screen
    /// edge. A window seat beside it must still take the tap, and a sideways
    /// swipe must not move the cabin.
    private func assertWingDoesNotStealTouches(app: XCUIApplication, cabin: XCUIElement) throws {
        let windowSeat = app.buttons
            .matching(NSPredicate(format: "label MATCHES %@", #"Seat [AF]1[0-9]"#))
            .allElementsBoundByIndex
            .first { $0.isHittable }
        let seat = try XCTUnwrap(windowSeat, "Expected an open window seat near the wing")
        let before = seat.frame
        cabin.swipeLeft()
        sleep(1)
        XCTAssertEqual(seat.frame.minX, before.minX, accuracy: 0.5, "The cabin scrolled sideways")

        seat.tap()
        let takeSeat = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Take seat")).firstMatch
        XCTAssertTrue(takeSeat.waitForExistence(timeout: 3), "The window seat beside the wing did not take the tap")
        save("qa-seatmap-wing-seat-selected")
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
