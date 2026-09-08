import SwiftData
import XCTest
@testable import Voyage

/// Measures the cost of one share-receipt rasterisation.
///
/// `LogbookView` used to call this from a `List` row body, so the number below
/// was being paid per visible row per body evaluation. It is reported rather
/// than asserted: the value is only meaningful next to the same measurement on
/// the same machine, which is shared with other work.
@MainActor
final class FlightReceiptRenderCostTests: XCTestCase {
    func testReceiptRenderCostIsReported() {
        let entry = LogbookEntry(
            originCode: "SFO",
            destinationCode: "YYZ",
            flightNumber: "NLN 100",
            seat: "A8",
            miles: 2_200,
            focusSeconds: 4_000,
            completed: true,
            intentions: ["Finish problem set 4", "Read chapter 9"],
            intentionsCompleted: [true, false]
        )

        // Warm the SwiftUI rendering machinery so the first-call cost of
        // spinning up ImageRenderer is not attributed to the receipt itself.
        _ = FlightReceiptRenderer.pngData(entry: entry)

        let iterations = 10
        let start = Date()
        for _ in 0..<iterations {
            _ = FlightReceiptRenderer.pngData(entry: entry)
        }
        let elapsed = Date().timeIntervalSince(start)
        print("RECEIPT-COST \(iterations) renders in \(elapsed) s "
              + "(\(elapsed / Double(iterations) * 1000) ms per render)")
    }

    /// The logbook list re-evaluates a row body on every scroll frame. This
    /// pins that repeated reads of the same row's receipt rasterise once.
    func testRepeatedRowReadsRasteriseOnce() async throws {
        let container = try ModelContainer(
            for: LogbookEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let entry = LogbookEntry(
            originCode: "SFO",
            destinationCode: "YYZ",
            flightNumber: "NLN 100",
            seat: "A8",
            miles: 2_200,
            focusSeconds: 4_000,
            completed: true
        )
        context.insert(entry)

        // Warm, so the count below measures the store and not first-use setup.
        _ = await LogbookReceiptStore.shared.receipt(for: entry)
        FlightReceiptRenderer.resetRenderCount()

        // One second of scrolling at 60 Hz asking the same row for its receipt.
        for _ in 0..<60 {
            _ = await LogbookReceiptStore.shared.receipt(for: entry)
        }

        XCTAssertEqual(
            FlightReceiptRenderer.renderCount,
            0,
            "a cached receipt must not re-rasterise while the row is re-laid out"
        )
    }

    /// A distinct flight must still get its own receipt, or the list would
    /// hand every row the first flight's card.
    func testDifferentEntriesRenderTheirOwnReceipt() async throws {
        let container = try ModelContainer(
            for: LogbookEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let first = LogbookEntry(
            originCode: "SFO", destinationCode: "YYZ", flightNumber: "NLN 100",
            seat: "A8", miles: 2_200, focusSeconds: 4_000, completed: true
        )
        let second = LogbookEntry(
            originCode: "BOS", destinationCode: "LAX", flightNumber: "NLN 200",
            seat: "C4", miles: 2_600, focusSeconds: 5_000, completed: true
        )
        context.insert(first)
        context.insert(second)

        let firstReceipt = await LogbookReceiptStore.shared.receipt(for: first)
        let secondReceipt = await LogbookReceiptStore.shared.receipt(for: second)

        XCTAssertNotNil(firstReceipt)
        XCTAssertNotNil(secondReceipt)
        XCTAssertNotEqual(
            firstReceipt?.pngData,
            secondReceipt?.pngData,
            "two different flights must not share one rendered receipt"
        )
    }
}
