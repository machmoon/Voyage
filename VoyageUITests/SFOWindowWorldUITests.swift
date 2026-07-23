import XCTest
import UIKit

/// SFO-only visual checkpoints kept as xcresult attachments. Unlike the full
/// screenshot tour, this test never overwrites committed QA images.
final class SFOWindowWorldUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSFOTakeoffWindowCheckpoints() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-VoyageShortFlights",
            "-VoyageHomeAirport", "SFO",
            "-VoyageRealWorldTwinEnabled",
        ]
        app.launchEnvironment["VOYAGE_SHORT_FLIGHTS"] = "1"
        // CI visual checkpoints are deterministic and never require live
        // Google/Apple tiles. Network-backed imagery is profiled on device.
        app.launchEnvironment["VOYAGE_FORCE_OFFLINE_SCENERY"] = "1"
        app.launch()
        dismissSystemAlerts()

        XCTAssertTrue(app.staticTexts["VOYAGE"].waitForExistence(timeout: 10))
        // Use a concrete nonstop route instead of asking XCTest to scan the
        // full globe accessibility tree for an arbitrary first destination.
        let card = app.buttons["destination-LAX"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()

        let depart = app.buttons["depart-now"]
        XCTAssertTrue(depart.waitForExistence(timeout: 5))
        depart.tap()

        // Starboard seat: the Bay reveal is composed for the right-hand window.
        let seat = app.buttons.matching(
            NSPredicate(format: "label MATCHES %@", #"Seat [D-F][0-9]+"#)
        ).firstMatch
        XCTAssertTrue(seat.waitForExistence(timeout: 6))
        seat.tap()

        let takeSeat = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Take seat")
        ).firstMatch
        XCTAssertTrue(takeSeat.waitForExistence(timeout: 3))
        takeSeat.tap()

        let skip = app.buttons["Skip for now"]
        let alternateSkip = app.buttons["Travel light — continue"]
        if skip.waitForExistence(timeout: 4) { skip.tap() }
        else { XCTAssertTrue(alternateSkip.waitForExistence(timeout: 2)); alternateSkip.tap() }

        let stub = app.otherElements["boarding-pass-stub"]
        XCTAssertTrue(stub.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 2)
        stub.swipeDown(velocity: .slow)

        let scenery = app.otherElements["real-world-twin-scenery"]
        XCTAssertTrue(
            scenery.waitForExistence(timeout: 12),
            "The continuous real-world window must replace the boarding view"
        )

        checkpoint("sfo-runway-acceleration", element: scenery, after: 3.2)
        checkpoint("sfo-rotation", element: scenery, after: 3.1)
        checkpoint("sfo-bay-city-reveal", element: scenery, after: 3.0)
        checkpoint("sfo-cloud-entry", element: scenery, after: 3.5)
    }

    private func checkpoint(_ name: String, element: XCUIElement, after delay: TimeInterval) {
        Thread.sleep(forTimeInterval: delay)
        XCTAssertTrue(element.exists, "Scenery disappeared before \(name)")
        let sceneryScreenshot = element.screenshot()
        assertNonBlank(sceneryScreenshot, checkpoint: name)

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Catch the failure mode where a streamed provider covers the fallback
    /// with a solid empty pane. The element screenshot is downsampled into a
    /// known RGBA buffer and must contain both visible light and contrast.
    private func assertNonBlank(_ screenshot: XCUIScreenshot, checkpoint: String) {
        guard let image = UIImage(data: screenshot.pngRepresentation),
              let cgImage = image.cgImage else {
            XCTFail("Could not decode scenery checkpoint \(checkpoint)")
            return
        }

        let width = 16
        let height = 16
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let sampled = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard sampled else {
            XCTFail("Could not sample scenery checkpoint \(checkpoint)")
            return
        }

        var luminance: [Double] = []
        luminance.reserveCapacity(width * height)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let red = 0.2126 * Double(pixels[offset])
            let green = 0.7152 * Double(pixels[offset + 1])
            let blue = 0.0722 * Double(pixels[offset + 2])
            luminance.append((red + green + blue) / 255)
        }
        let average = luminance.reduce(0, +) / Double(luminance.count)
        let contrast = (luminance.max() ?? 0) - (luminance.min() ?? 0)
        XCTAssertGreaterThan(average, 0.025, "Scenery is black at \(checkpoint)")
        XCTAssertGreaterThan(contrast, 0.025, "Scenery is a blank solid pane at \(checkpoint)")
    }

    @MainActor
    private func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow While Using App", "Allow Once", "Don’t Allow", "Don't Allow"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 1.2) {
                button.tap()
                return
            }
        }
    }
}
