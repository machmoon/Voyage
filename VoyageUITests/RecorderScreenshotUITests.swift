import XCTest

/// Captures the flight data recorder from the running app on a simulator.
///
/// Two rules this test follows, both learned the hard way tonight.
///
/// First, it never photographs the display. `XCUIScreen.main.screenshot()`
/// returns whatever is on screen whether or not the app is alive, so a dead
/// app still produces a plausible-looking PNG and a passing test. Every
/// capture here goes through `XCUIApplication.screenshot()`, which is scoped
/// to the app's own window.
///
/// Second, it proves the screen is up before it captures. Each capture is
/// preceded by an assertion on text that only exists on that screen, so a
/// blank or wrong frame fails the test instead of being written to disk.
final class RecorderScreenshotUITests: XCTestCase {

    /// Deliberately not `QA/`: another lane owns that directory tonight.
    private let outputDirectory = URL(fileURLWithPath:
        "/private/tmp/claude-501/-Users-patliu-Desktop-Coding-Voyage/bde4f64a-2d96-498c-b915-d0d371f1008f/scratchpad/out/screens")

    override func setUpWithError() throws {
        continueAfterFailure = false
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    // MARK: Harness

    private func launch(demoLogbook: Bool,
                        contentSize: String? = nil,
                        style: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        // Either a seeded demo logbook or a guaranteed-empty one; never the
        // simulator's real store, which other tours fill with flights.
        app.launchArguments.append(demoLogbook ? "-VoyageRecorderDemo" : "-VoyageEmptyLogbook")
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        if let style {
            app.launchArguments += ["-UIUserInterfaceStyle", style]
        }
        app.launch()
        dismissLocationPromptIfPresent()
        return app
    }

    private func dismissLocationPromptIfPresent() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow While Using App", "Allow Once", "Don’t Allow", "Don't Allow"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 2) {
                button.tap()
                return
            }
        }
    }

    private func openRecorder(in app: XCUIApplication) {
        let logbook = app.buttons["open-logbook"]
        XCTAssertTrue(logbook.waitForExistence(timeout: 20), "Home never appeared")
        logbook.tap()

        let recorder = app.buttons["open-recorder"]
        XCTAssertTrue(recorder.waitForExistence(timeout: 10), "Logbook never showed the recorder row")
        recorder.tap()

        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "From ", "Your logbook is empty")).firstMatch.waitForExistence(timeout: 10),
                      "The recorder screen never appeared")
    }

    /// Scrolls until a piece of text is on screen, so a capture never depends
    /// on a fixed number of swipes.
    @discardableResult
    private func scroll(_ app: XCUIApplication, until fragment: String) -> Bool {
        let target = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
        for _ in 0..<8 {
            if target.exists && target.isHittable { return true }
            app.swipeUp()
        }
        return target.exists
    }

    /// Captures the app's own window, never the display, and fails rather
    /// than writing a frame that is obviously empty.
    ///
    /// `cropping` takes a rect in the app's own point coordinates and trims
    /// the capture to it, so a close view is a crop of the real frame rather
    /// than a separately staged picture.
    private func capture(_ app: XCUIApplication, named name: String, cropping rect: CGRect? = nil) {
        var data = app.screenshot().pngRepresentation

        if let rect, let cropped = Self.crop(pngData: data, to: rect, appWidth: app.frame.width) {
            data = cropped
        } else if rect != nil {
            XCTFail("Could not crop \(name)")
        }

        XCTAssertGreaterThan(data.count, 20_000, "\(name) looks empty at \(data.count) bytes")
        let url = outputDirectory.appendingPathComponent("\(name).png")
        try? data.write(to: url)
        print("captured \(url.path) (\(data.count) bytes)")
    }

    private static func crop(pngData: Data, to rect: CGRect, appWidth: CGFloat) -> Data? {
        guard let source = UIImage(data: pngData)?.cgImage, appWidth > 0 else { return nil }
        let scale = CGFloat(source.width) / appWidth
        let pixels = CGRect(x: rect.minX * scale, y: rect.minY * scale,
                            width: rect.width * scale, height: rect.height * scale)
            .integral
            .intersection(CGRect(x: 0, y: 0, width: source.width, height: source.height))
        guard !pixels.isEmpty, let cropped = source.cropping(to: pixels) else { return nil }
        return UIImage(cgImage: cropped).pngData()
    }

    /// The bounding box of a card, from its strap line down to the last row
    /// under it, padded so the capture does not clip the panel edge.
    private func cardRect(in app: XCUIApplication, from topLabel: String, to bottomLabel: String) -> CGRect? {
        let top = app.staticTexts[topLabel]
        let bottom = app.staticTexts[bottomLabel]
        guard top.exists, bottom.exists else { return nil }
        let topFrame = top.frame
        let bottomFrame = bottom.frame
        return CGRect(x: 0,
                      y: topFrame.minY - 26,
                      width: app.frame.width,
                      height: bottomFrame.maxY - topFrame.minY + 52)
    }

    // MARK: Captures

    /// The silent state: a real logbook that is simply too small to speak.
    /// No demo data, so this is a first-launch logbook.
    func testCaptureRecordingState() throws {
        let app = launch(demoLogbook: false)
        openRecorder(in: app)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(
            format: "label CONTAINS %@", "needs 12 flights")).firstMatch.exists,
            "Expected the flights-until-reporting state")
        capture(app, named: "recorder-1-recording")
    }

    /// The populated report. Two frames, because the findings do not fit on
    /// one screen and the method note at the bottom is part of the argument.
    func testCaptureFindings() throws {
        let app = launch(demoLogbook: true)
        openRecorder(in: app)

        XCTAssertTrue(app.staticTexts.containing(NSPredicate(
            format: "label BEGINSWITH %@", "From 57 flights")).firstMatch.exists,
            "The demo logbook did not reach the screen")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(
            format: "label CONTAINS %@", "land more often")).firstMatch.exists,
            "Expected at least one comparative finding")
        capture(app, named: "recorder-2-findings-top")

        XCTAssertTrue(scroll(app, until: "including the things you might want to hear"),
                      "Expected the method note at the bottom of the report")
        capture(app, named: "recorder-3-findings-method")
    }

    /// The evidence rows on their own, cropped out of the real frame so the
    /// confidence bands are legible at a glance.
    ///
    /// This is the argument for the whole feature in one card. The departure
    /// card puts 38 flights, 7 flights and 6 flights side by side at
    /// different rates: the large group's interval is a narrow mark and the
    /// small groups' are wide smears, and the difference is visible without
    /// reading a single number.
    func testCaptureEvidenceRowsCloseUp() throws {
        let app = launch(demoLogbook: true)
        openRecorder(in: app)
        XCTAssertTrue(scroll(app, until: "land more often"),
                      "Expected the departure-time finding")
        XCTAssertTrue(app.staticTexts["38/44"].exists, "Expected the 44-flight group")
        XCTAssertTrue(app.staticTexts["1/7"].exists, "Expected the 7-flight group")

        let rect = cardRect(in: app, from: "Flights between 5pm and 9pm land more often.", to: "21 to 05")
        XCTAssertNotNil(rect, "Could not locate the departure-time card")
        capture(app, named: "recorder-4-evidence-bands", cropping: rect)
    }

    /// The recorder at an accessibility text size, where the evidence rows
    /// switch to a stacked layout.
    func testCaptureAtAccessibilityTextSize() throws {
        let app = launch(demoLogbook: true,
                         contentSize: "UICTContentSizeCategoryAccessibilityL")
        openRecorder(in: app)
        capture(app, named: "recorder-5-accessibility")
    }

    /// The one part of this feature that lives in light mode: the Logbook row
    /// that pushes the recorder, with its live caption.
    func testCaptureLogbookEntryPointInLightMode() throws {
        let app = launch(demoLogbook: true, style: "Light")
        let logbook = app.buttons["open-logbook"]
        XCTAssertTrue(logbook.waitForExistence(timeout: 20))
        logbook.tap()
        XCTAssertTrue(app.buttons["open-recorder"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Flight data recorder"].exists)
        capture(app, named: "recorder-6-logbook-row-light")
    }
}
