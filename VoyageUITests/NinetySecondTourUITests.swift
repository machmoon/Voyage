import XCTest

/// A ~90s guided tour of everything important, built to run unchanged against
/// several builds of the app: every beat is optional. If a feature does not
/// exist in the build under test the beat is skipped and its time is spent
/// holding the previous screen, so the recording stays full-length either way.
///
/// Beat sheet (approx):
///   0–10s   Launch, home, seed a returning-traveler logbook via Settings
///  10–17s   Home with streak / tier / globe
///  17–25s   Logbook → Passport stamps
///  25–34s   Weekly trip replay, playing
///  34–42s   Departure board (schedule)
///  42–50s   Pick destination → Depart now
///  50–58s   Seat map → take seat
///  58–66s   Bags → boarding pass prints → tear to board
///  66–76s   Takeoff roll → climb through the window
///  76–86s   Map view: route → satellite → follow
///  86–90s   Back to the window at cruise
final class NinetySecondTourUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    func testNinetySecondFeatureTour() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-VoyageShortFlights",
        ]
        app.launch()

        _ = app.staticTexts["VOYAGE"].waitForExistence(timeout: 10)
        // The location prompt arrives after the globe, not before it.
        dismissSystemAlerts()
        pause(1.0)

        seedDemoHistory(in: app)      // through ~10s
        holdHome(in: app)             // through ~17s
        tourPassport(in: app)         // through ~25s
        tourReplay(in: app)           // through ~34s
        tourSchedule(in: app)         // through ~42s
        bookAndBoard(in: app)         // through ~66s
        tourInFlight(in: app)         // through ~90s
    }

    // MARK: - Beats

    /// Fills the logbook so the home screen reads as a lived-in account.
    @MainActor
    private func seedDemoHistory(in app: XCUIApplication) {
        // The gear sits in the home header overlay; tap by position when the
        // accessibility query does not resolve it as hittable.
        if !tap(app.buttons["Settings"], timeout: 2) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.055)).tap()
        }
        pause(1.5)
        let seed = app.buttons["Load demo history"]
        if seed.waitForExistence(timeout: 3) {
            // Test-mode seeder lives near the bottom of Settings.
            app.swipeUp(velocity: .fast)
            pause(0.4)
            if seed.exists && seed.isHittable { seed.tap() } else { seed.tap() }
            pause(1.5)
        } else {
            pause(1.5)
        }
        dismissSheet(in: app)
        pause(1.0)
    }

    @MainActor
    private func holdHome(in app: XCUIApplication) {
        // Let the globe idle-rotate and the streak / tier chrome read.
        pause(3.0)
        app.swipeUp(velocity: .slow)
        pause(1.2)
        app.swipeDown(velocity: .slow)
        pause(1.0)
    }

    @MainActor
    private func tourPassport(in app: XCUIApplication) {
        if !tap(app.buttons["Open logbook"], timeout: 2) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.84, dy: 0.055)).tap()
        }
        pause(2.0)
        if tap(app.segmentedControls.buttons["Passport"], timeout: 2) {
            pause(2.5)
            app.swipeUp(velocity: .slow)
            pause(1.5)
        } else {
            app.swipeUp(velocity: .slow)
            pause(2.0)
        }
        pause(0.5)
    }

    @MainActor
    private func tourReplay(in app: XCUIApplication) {
        // Back to the flights tab, where the weekly replay card lives.
        _ = tap(app.segmentedControls.buttons["Flights"], timeout: 1.5)
        pause(0.8)
        let replay = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Replay")).firstMatch
        if tap(replay, timeout: 2) {
            pause(6.0)   // replay autoplays; let the route draw
            _ = tap(app.buttons["Pause trip replay"], timeout: 1)
            pause(0.8)
            dismissSheet(in: app)
        } else {
            pause(6.0)
        }
        pause(0.5)
        dismissSheet(in: app)   // leave logbook
        pause(1.0)
    }

    @MainActor
    private func tourSchedule(in app: XCUIApplication) {
        guard tap(app.buttons["Schedule"], timeout: 2) else { pause(6); return }
        pause(3.0)
        app.swipeUp(velocity: .slow)
        pause(1.5)
        dismissSheet(in: app)
        pause(1.0)
    }

    @MainActor
    private func bookAndBoard(in app: XCUIApplication) {
        let cards = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "destination-"))
        if tap(cards.firstMatch, timeout: 4) { pause(1.8) }
        if tap(app.buttons["depart-now"], timeout: 4) { pause(1.2) }

        // Seat selection — let the cabin map read before choosing.
        // SeatSelectionView.swift:111.
        _ = app.staticTexts["Choose your seat"].waitForExistence(timeout: 5)
        pause(1.5)
        app.swipeUp(velocity: .slow)
        pause(1.2)
        // Prefer an over-wing window seat (rows 11–17, A/F columns) so the
        // wing is actually in shot; fall back to any free seat.
        let overWing = app.buttons.matching(
            NSPredicate(format: "label MATCHES %@", #"Seat [AF]1[1-7]"#)).firstMatch
        if overWing.waitForExistence(timeout: 2) {
            overWing.tap()
        } else {
            let seat = app.buttons.matching(
                NSPredicate(format: "label MATCHES %@", #"Seat [A-F][0-9]+"#)).firstMatch
            if seat.waitForExistence(timeout: 2) { seat.tap() }
        }
        pause(1.2)
        _ = tap(app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Take seat")).firstMatch, timeout: 3)
        pause(0.5)

        // Bags.
        // CheckBagView.swift:84: "Skip for now" until something is packed,
        // "Check N bags" after. The tour packs nothing.
        if !tap(app.buttons["Skip for now"], timeout: 4) {
            _ = tap(app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Check ")).firstMatch, timeout: 2)
        }
        pause(0.8)

        // Boarding pass prints, then the stub tear commits to the flight.
        // Designs differ across builds: the current pass pulls the stub down,
        // The cut runs sideways: BoardingPassView.swift:380 discards a
        // mostly-vertical drag, so the swipeDown this used to lead with was
        // always a no-op and only the fallbacks ever tore the pass. Drive the
        // button, whose accessibility label is "Tear and board" (:89) rather
        // than the "Tear & board" its text reads, and keep the sideways swipe
        // as the fallback.
        let stub = app.otherElements["boarding-pass-stub"]
        if stub.waitForExistence(timeout: 10) {
            pause(2.5)          // watch it print
            if !tap(app.buttons["Tear and board"], timeout: 4) {
                let stubAgain = app.otherElements["boarding-pass-stub"]
                if stubAgain.exists && stubAgain.isHittable {
                    stubAgain.swipeRight(velocity: .slow)
                }
            }
        } else {
            pause(3.5)
        }
    }

    @MainActor
    private func tourInFlight(in app: XCUIApplication) {
        // Curtain → takeoff roll → climb, compressed by -VoyageShortFlights.
        pause(10.0)

        if tap(app.buttons["Map view"], timeout: 4) {
            pause(3.5)
            _ = tap(app.buttons["Satellite"], timeout: 2)
            pause(3.0)
            _ = tap(app.buttons["Follow"], timeout: 2)
            pause(3.5)
            _ = tap(app.buttons["Window view"], timeout: 2)
            pause(4.0)
        } else {
            pause(14.0)
        }
    }

    // MARK: - Helpers

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Taps an element if it shows up in time. Returns whether it did, so a
    /// caller can spend the beat's time elsewhere when a feature is absent.
    @MainActor
    private func tap(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        guard element.waitForExistence(timeout: timeout), element.isHittable else { return false }
        element.tap()
        return true
    }

    /// Closes a presented sheet by its own button when there is one, otherwise
    /// by the swipe-down dismiss gesture.
    @MainActor
    private func dismissSheet(in app: XCUIApplication) {
        for label in ["Done", "Close", "Back"] {
            let button = app.buttons[label]
            if button.exists && button.isHittable { button.tap(); return }
        }
        app.swipeDown(velocity: .fast)
    }

    @MainActor
    private func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow While Using App", "Allow Once", "Allow", "Don’t Allow", "Don't Allow"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 1.2) {
                if label.hasPrefix("Allow") {
                    button.tap()
                    break
                }
                button.tap()
                break
            }
        }
        // A second prompt (Focus status) can follow the location one.
        for label in ["Don’t Allow", "Don't Allow"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 1.5) { button.tap(); return }
        }
    }
}
