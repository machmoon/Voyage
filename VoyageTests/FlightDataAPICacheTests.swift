import CoreLocation
import XCTest
@testable import Voyage

/// Guards the replay hot path.
///
/// `FlightReplayView` reads `replaySnapshot(for:progress:)` from its view body,
/// and that body is invalidated by a `CADisplayLink` at 60-120 Hz. Each call
/// walks `validatedArchivedTrajectory`, which JSON-decodes the persisted
/// archive and then validates every sample. A two-leg flight archives
/// 2 x 192 samples of eight `Double`s each, so without a memo the replay screen
/// decodes and validates roughly 120 KB of JSON a hundred times a second on the
/// main thread.
///
/// These tests pin the decode count rather than the wall clock, so they stay
/// meaningful on a loaded machine.
final class FlightDataAPICacheTests: XCTestCase {
    private let api = FlightDataAPI.shared

    /// One second of display-link frames at 120 Hz, times the two reads
    /// `FlightReplayView` performs per body evaluation.
    private static let frameCallCount = 240

    // MARK: Realistic fixtures

    /// A two-leg archive at the density `FlightSession` actually persists
    /// (`replaySamples(count: 192, ...)` per leg).
    private func makeRealisticEntry() -> LogbookEntry {
        let sfo = Airport.byCode("SFO")
        let yyz = Airport.byCode("YYZ")
        let yqr = Airport.byCode("YQR")
        return LogbookEntry(
            originCode: "SFO",
            destinationCode: "YQR",
            connectionCode: "YYZ",
            flightNumber: "NLN 740",
            seat: "A8",
            miles: 1_500,
            focusSeconds: 8_000,
            completed: true,
            worldRevision: FlightVisualEngine.trajectoryRevision,
            trajectoryLegSamples: [
                denseLeg(from: sfo, to: yyz, duration: 4_000, count: 192),
                denseLeg(from: yyz, to: yqr, duration: 4_000, count: 192),
            ]
        )
    }

    private func denseLeg(
        from origin: Airport,
        to destination: Airport,
        duration: TimeInterval,
        count: Int
    ) -> [FlightTrajectorySample] {
        (0..<count).map { index in
            let progress = Double(index) / Double(count - 1)
            let coordinate = GreatCircle.point(
                from: origin.coordinate,
                to: destination.coordinate,
                fraction: progress
            )
            return FlightTrajectorySample(
                elapsed: duration * progress,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                altitudeMeters: progress == 0 || progress == 1 ? 0 : 10_000,
                courseDegrees: GreatCircle.bearing(
                    from: origin.coordinate,
                    to: destination.coordinate
                ),
                pitchDegrees: 0,
                bankDegrees: 0,
                routeProgress: progress
            )
        }
    }

    // MARK: Cache behaviour

    func testReplayFramesDecodeTheArchiveOnce() {
        let entry = makeRealisticEntry()
        api.resetArchiveDecodeCount()

        for index in 0..<Self.frameCallCount {
            _ = api.replaySnapshot(for: entry, progress: Double(index) / Double(Self.frameCallCount))
        }

        XCTAssertEqual(
            api.archiveDecodeCount,
            1,
            "\(Self.frameCallCount) replay frames must decode the archive once, not once per frame"
        )
    }

    func testCachedArchiveStillReturnsTheSameSnapshots() {
        let entry = makeRealisticEntry()
        let progresses = [0.0, 0.13, 0.25, 0.5, 0.75, 0.99, 1.0]

        let first = progresses.map { api.replaySnapshot(for: entry, progress: $0) }
        let second = progresses.map { api.replaySnapshot(for: entry, progress: $0) }

        for (index, progress) in progresses.enumerated() {
            XCTAssertEqual(
                first[index].coordinate.latitude,
                second[index].coordinate.latitude,
                accuracy: 0.000_000_1,
                "latitude drifted at progress \(progress)"
            )
            XCTAssertEqual(
                first[index].coordinate.longitude,
                second[index].coordinate.longitude,
                accuracy: 0.000_000_1,
                "longitude drifted at progress \(progress)"
            )
            XCTAssertEqual(first[index].legIndex, second[index].legIndex)
            XCTAssertEqual(
                first[index].legProgress,
                second[index].legProgress,
                accuracy: 0.000_000_1
            )
        }
    }

    /// The memo keys on object identity, so it must also verify the blob. A
    /// stale trajectory replayed over a rewritten archive would put the
    /// aircraft on the wrong route with no visible error.
    func testRewritingTheArchiveInvalidatesTheCachedTrajectory() throws {
        let sfo = Airport.byCode("SFO")
        let yyz = Airport.byCode("YYZ")
        let lax = Airport.byCode("LAX")

        let entry = LogbookEntry(
            originCode: "SFO",
            destinationCode: "YYZ",
            flightNumber: "NLN 100",
            seat: "A8",
            miles: 2_200,
            focusSeconds: 4_000,
            completed: true,
            worldRevision: FlightVisualEngine.trajectoryRevision,
            trajectoryLegSamples: [denseLeg(from: sfo, to: yyz, duration: 4_000, count: 192)]
        )
        let before = api.replaySnapshot(for: entry, progress: 1)
        XCTAssertEqual(before.coordinate.latitude, yyz.coordinate.latitude, accuracy: 0.01)

        // Rewrite the archive in place, exactly as a future migration or
        // re-render would, and read the same entry object again.
        entry.trajectorySamplesData = try JSONEncoder().encode(
            [denseLeg(from: sfo, to: lax, duration: 4_000, count: 192)]
        )
        entry.destinationCode = "LAX"

        let after = api.replaySnapshot(for: entry, progress: 1)
        XCTAssertEqual(
            after.coordinate.latitude,
            lax.coordinate.latitude,
            accuracy: 0.01,
            "the memo served a stale trajectory after the archive was rewritten"
        )
    }

    // MARK: Timing

    /// Reports the cost of one second of replay at 120 Hz. Not an assertion:
    /// the number is only meaningful next to the same measurement taken
    /// before the memo was added, and the machine running it is shared.
    func testReplayFrameCostIsReported() {
        let entry = makeRealisticEntry()
        // Warm any one-time work that is not the decode itself.
        _ = api.replaySnapshot(for: entry, progress: 0)

        let start = Date()
        for index in 0..<Self.frameCallCount {
            let progress = Double(index) / Double(Self.frameCallCount)
            _ = api.replaySnapshot(for: entry, progress: progress)
        }
        let elapsed = Date().timeIntervalSince(start)
        print("REPLAY-COST \(Self.frameCallCount) calls in \(elapsed) s "
              + "(\(elapsed / Double(Self.frameCallCount) * 1000) ms per call)")
    }
}
