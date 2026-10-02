import XCTest
@testable import Voyage

final class LandingPhrasesTests: XCTestCase {
    private var allPools: [String: [String]] {
        ["landed": LandingPhrases.landed,
         "descent": LandingPhrases.descent,
         "landing": LandingPhrases.landing]
    }

    private func freshDefaults() -> UserDefaults {
        let suite = "LandingPhrasesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// Seeded, so a failure reproduces.
    private struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    func testEveryPhraseFitsTheLimit() {
        for (name, pool) in allPools {
            for line in pool {
                XCTAssertLessThanOrEqual(line.count, LandingPhrases.maxLength,
                                         "\(name): \"\(line)\" is \(line.count) characters")
            }
        }
    }

    func testCopyIsCleanAndUnique() {
        XCTAssertGreaterThanOrEqual(LandingPhrases.landed.count, 40)
        for (name, pool) in allPools {
            XCTAssertEqual(Set(pool).count, pool.count, "\(name) has a duplicate line")
            for line in pool {
                XCTAssertFalse(line.isEmpty)
                XCTAssertFalse(line.contains("\u{2014}"), "em-dash in \(line)")
                // No emoji: every scalar is plain text, not a pictograph.
                XCTAssertFalse(line.unicodeScalars.contains { $0.properties.isEmojiPresentation },
                               "emoji in \(line)")
            }
        }
    }

    /// The phases still open on the captions they always had.
    func testApproachPoolsKeepTheOriginalCaptions() {
        XCTAssertEqual(LandingPhrases.descent.first, "Descending · start wrapping up")
        XCTAssertEqual(LandingPhrases.landing.first, "Landing")
    }

    func testRotationNeverRepeatsTheLastThree() {
        for (name, pool) in allPools {
            var generator = SplitMix64(state: 42)
            var rotation = PhraseRotation(pool: pool, memory: 3)
            let window = min(3, pool.count - 1)
            var history: [String] = []
            for _ in 0..<2_000 {
                let line = rotation.next(using: &generator)
                XCTAssertFalse(history.suffix(window).contains(line),
                               "\(name): \"\(line)\" repeated within the last \(window)")
                history.append(line)
            }
            XCTAssertEqual(Set(history), Set(pool), "\(name): some line never appeared")
        }
    }

    func testRememberedLineIsNotPickedNext() {
        var generator = SplitMix64(state: 7)
        var rotation = PhraseRotation(pool: LandingPhrases.descent)
        rotation.remember(LandingPhrases.descent[0])
        for _ in 0..<3 {
            XCTAssertNotEqual(rotation.next(using: &generator), LandingPhrases.descent[0])
        }
    }

    /// The landed line remembers the last three flights across launches.
    func testLandedLineNeverRepeatsTheLastThreeFlights() {
        let defaults = freshDefaults()
        var generator = SplitMix64(state: 2026)
        var history: [String] = []
        for _ in 0..<1_000 {
            let line = LandingPhrases.nextLanded(defaults: defaults, using: &generator)
            XCTAssertFalse(history.suffix(3).contains(line), "\"\(line)\" repeated within three flights")
            history.append(line)
        }
        XCTAssertEqual(Set(history), Set(LandingPhrases.landed))
    }

    func testStaleRememberedLinesAreIgnored() {
        let rotation = PhraseRotation(pool: ["a", "b"], memory: 3, recent: ["gone", "a"])
        XCTAssertEqual(rotation.recent, ["a"])
        XCTAssertEqual(rotation.memory, 1)
    }
}
