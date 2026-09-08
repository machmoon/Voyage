import XCTest

/// Captures the wellness cues from the running app.
///
/// Two rules, both from failures earlier tonight. Every frame comes from
/// `XCUIApplication.screenshot()`, never `XCUIScreen.main.screenshot()`,
/// which photographs the display whether or not the app is still alive and
/// will happily produce a plausible PNG over a dead process. And every capture
/// is gated behind an assertion on text that exists only on that screen, so a
/// blank or wrong frame fails the test instead of reaching disk.
final class CabinServiceScreenshotUITests: XCTestCase {

    private let outputDirectory = "/private/tmp/claude-501/-Users-patliu-Desktop-Coding-Voyage/bde4f64a-2d96-498c-b915-d0d371f1008f/scratchpad/out/screens"

    override func setUpWithError() throws {
        continueAfterFailure = false
        try FileManager.default.createDirectory(atPath: outputDirectory,
                                               withIntermediateDirectories: true)
    }

    @MainActor
    func testCapturesTheEyeRestAndStretchCues() throws {
        let app = launchIntoCruise()

        // Pass 1 is the eye rest, due six seconds into cruise under the
        // capture flag.
        let eyeRest = app.staticTexts["Something to see out of the right side."]
        XCTAssertTrue(eyeRest.waitForExistence(timeout: 30),
                      "Expected the eye-rest cue during cruise")
        capture(app, "cabin-1-eye-rest")

        // Pass 3 is the stretch. Passes 2 and 3 follow at six second spacing.
        let stretch = app.staticTexts["The seatbelt sign is off."]
        XCTAssertTrue(stretch.waitForExistence(timeout: 60),
                      "Expected the stretch cue on the third pass")
        capture(app, "cabin-2-stretch")

        // The card cropped to its own bounds, so the copy is legible.
        let card = app.otherElements["cabin-service-card"]
        XCTAssertTrue(card.exists, "Expected the card element for the crop")
        captureCropped(app, "cabin-3-card-close", to: card.frame)
    }

    /// Pins the known defect described in `InFlightView`: the cue is
    /// suppressed at accessibility text sizes because presenting it there
    /// hangs the app. This asserts the suppression, not an approval of it.
    /// Delete this test together with the gate once the layout is fixed.
    @MainActor
    func testCueIsSuppressedAtAccessibilityTextSizeUntilTheHangIsFixed() throws {
        let app = launchIntoCruise(extraArguments: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL",
        ])
        sleep(40)
        XCTAssertEqual(app.state, .runningForeground,
                       "The gate exists so the app survives; if this fails the gate is not working")
        XCTAssertFalse(app.otherElements["cabin-service-card"].exists,
                       "The cue is deliberately suppressed at accessibility sizes for now")
        capture(app, "cabin-4-accessibility-suppressed")
    }

    /// The promise the design rests on: the cue goes away by itself and the
    /// flight is unaffected. Asserted, then photographed.
    @MainActor
    func testTheCueLeavesTheScreenOnItsOwn() throws {
        let app = launchIntoCruise()

        let eyeRest = app.staticTexts["Something to see out of the right side."]
        XCTAssertTrue(eyeRest.waitForExistence(timeout: 30))

        // Never touch it. It expires 90 seconds after it appeared.
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: eyeRest)
        waitForExpectations(timeout: 180)

        // The flight is still flying, which is the whole point: ignoring a
        // cue is not a diversion and not a failure.
        XCTAssertFalse(app.staticTexts["Flight diverted"].exists)
        XCTAssertTrue(app.otherElements["in-flight-screen"].exists
                      || app.buttons["Window view"].exists
                      || app.buttons["Map view"].exists,
                      "Expected to still be in flight after ignoring the cue")
        capture(app, "cabin-5-after-ignoring")
    }

    /// Control. Boards and sits in cruise with the cue feature switched off
    /// entirely, so nothing this feature added is on screen. If this fails the
    /// same way the captures do, the in-flight screen is dying for a reason
    /// that has nothing to do with cabin service.
    @MainActor
    func testInFlightSurvivesWithoutAnyCue() throws {
        let app = launchIntoCruise(demo: false)
        sleep(40)
        XCTAssertFalse(app.otherElements["cabin-service-card"].exists,
                       "No cue should ever appear without the capture flag")
        XCTAssertEqual(app.state, .runningForeground,
                       "The app must survive a stretch of cruise")
        XCTAssertTrue(app.buttons["Window view"].exists || app.buttons["Map view"].exists,
                      "Expected to still be in flight")
    }

    /// Second control: accessibility text size, in flight, with the cue
    /// feature off. Separates "the card breaks at large text" from "the
    /// in-flight screen breaks at large text".
    @MainActor
    func testInFlightSurvivesAtAccessibilityTextSizeWithoutAnyCue() throws {
        let app = launchIntoCruise(demo: false, extraArguments: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL",
        ])
        sleep(40)
        XCTAssertEqual(app.state, .runningForeground,
                       "The in-flight screen must survive accessibility text size")
    }

    // MARK: Harness

    @MainActor
    private func launchIntoCruise(demo: Bool = true,
                                  extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-VoyageShortFlights",
            // Not cosmetic. Without this the app aborts in `AURemoteIO::Cleanup`
            // roughly 40 seconds after boarding and no in-flight frame can be
            // captured at all. See the note in `CabinAudioEngine`.
            "-VoyageSilentCabin",
        ] + (demo ? ["-VoyageCabinServiceDemo"] : []) + extraArguments
        app.launch()

        dismissLocationPromptIfPresent()
        XCTAssertTrue(app.staticTexts["VOYAGE"].waitForExistence(timeout: 15))

        let card = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "destination-")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()

        let depart = app.buttons["depart-now"]
        XCTAssertTrue(depart.waitForExistence(timeout: 8))
        depart.tap()

        let seat = app.buttons.matching(
            NSPredicate(format: "label MATCHES %@", #"Seat [A-D][0-9]+"#)).firstMatch
        XCTAssertTrue(seat.waitForExistence(timeout: 10))
        seat.tap()

        let takeSeat = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Take seat")).firstMatch
        XCTAssertTrue(takeSeat.waitForExistence(timeout: 6))
        takeSeat.tap()

        let skip = app.buttons["Travel light — skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 8))
        skip.tap()

        let tear = app.buttons["Tear and board"]
        XCTAssertTrue(tear.waitForExistence(timeout: 15), "Expected the boarding pass")
        tear.tap()

        return app
    }

    /// Scoped to the app's own window, so a dead process cannot produce a
    /// plausible looking frame.
    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        write(app.screenshot().pngRepresentation, name)
    }

    @MainActor
    private func captureCropped(_ app: XCUIApplication, _ name: String, to rect: CGRect) {
        let full = app.screenshot().image
        let scale = full.scale
        let box = CGRect(x: rect.origin.x * scale, y: rect.origin.y * scale,
                         width: rect.width * scale, height: rect.height * scale)
            .insetBy(dx: -8 * scale, dy: -8 * scale)
        guard let cgImage = full.cgImage?.cropping(to: box),
              let data = UIImage(cgImage: cgImage).pngData() else {
            return XCTFail("Could not crop the card out of the frame")
        }
        write(data, name)
    }

    private func write(_ data: Data, _ name: String) {
        let path = "\(outputDirectory)/\(name).png"
        XCTAssertGreaterThan(data.count, 20_000, "\(name) is too small to contain a screen")
        do {
            try data.write(to: URL(fileURLWithPath: path))
            print("captured \(path) (\(data.count) bytes)")
        } catch {
            XCTFail("Could not write \(path): \(error)")
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
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
