import AVFoundation
import XCTest
@testable import Voyage

/// The one-shot cues do not go through `AVAudioEngine`, because building that
/// graph can `abort()` the process. These cover what can be covered without
/// hardware: that a cue really is rendered to a playable file, that it is
/// rendered once, and that asking for one never starts the render graph.
final class SoundEffectsTests: XCTestCase {

    private var directory: URL!
    private var effects: SoundEffects!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SoundEffectsTests-\(UUID().uuidString)", isDirectory: true)
        effects = SoundEffects(directory: directory)
    }

    override func tearDown() {
        effects.reset()
        effects = nil
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        super.tearDown()
    }

    /// A 220 Hz tone at half amplitude, the shape every cue's formula has.
    private func tone(_ i: Int, _ t: Double, _ rate: Double) -> Float {
        Float(sin(2 * .pi * 220 * t)) * 0.5
    }

    func testACueIsRenderedToAPlayableFile() throws {
        let id = effects.prepare("tone", duration: 0.25, build: tone)
        XCTAssertNotNil(id)

        let url = effects.fileURL(forKey: "tone")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.fileFormat.sampleRate, SoundEffects.sampleRate)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
        XCTAssertEqual(Double(file.length) / file.fileFormat.sampleRate, 0.25, accuracy: 0.01)
    }

    func testTheRenderedFileCarriesTheWaveform() throws {
        effects.prepare("tone", duration: 0.25, build: tone)
        let file = try AVAudioFile(forReading: effects.fileURL(forKey: "tone"))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                    frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        var peak: Float = 0
        for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(samples[i])) }
        // 0.5 out, 0.5 back, allowing for the 16-bit quantization on the way.
        XCTAssertEqual(peak, 0.5, accuracy: 0.01)
    }

    func testSilenceStaysSilent() throws {
        effects.prepare("silence", duration: 0.1) { _, _, _ in 0 }
        let file = try AVAudioFile(forReading: effects.fileURL(forKey: "silence"))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                    frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for i in 0..<Int(buffer.frameLength) { XCTAssertEqual(samples[i], 0, accuracy: 0.0001) }
    }

    func testAKeyIsRenderedOnceHoweverOftenItIsPlayed() {
        for _ in 0..<20 {
            effects.play("tear-tick", duration: 0.045, build: tone)
        }
        XCTAssertEqual(effects.renderCount, 1,
                       "A cue fired repeatedly from a drag must not re-render on every tick")
    }

    func testDifferentKeysGetTheirOwnSound() {
        let a = effects.prepare("chime", duration: 0.2, build: tone)
        let b = effects.prepare("chime-premium", duration: 0.2, build: tone)
        XCTAssertNotNil(a)
        XCTAssertNotNil(b)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(effects.renderCount, 2)
        XCTAssertNotEqual(effects.fileURL(forKey: "chime"), effects.fileURL(forKey: "chime-premium"))
    }

    /// System Sound Services will not take a clip of zero length or over 30 s.
    func testAnImpossibleDurationIsRefusedRatherThanRendered() {
        XCTAssertNil(effects.prepare("empty", duration: 0, build: tone))
        XCTAssertNil(effects.prepare("epic", duration: 45, build: tone))
        XCTAssertEqual(effects.renderCount, 0)
    }

    func testAFailedCueIsNotRetriedOnEveryTap() {
        for _ in 0..<5 { effects.play("empty", duration: 0, build: tone) }
        XCTAssertEqual(effects.renderCount, 0)
    }

    /// Any key at all has to become a legal file name, including the printer's,
    /// which is built from a schedule digest.
    func testEveryKeyBecomesALegalFileName() {
        let name = SoundEffects.fileName(for: "printer/../../etc:passwd 3f")
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains(":"))
        XCTAssertTrue(name.hasSuffix(".caf"))
        XCTAssertNotEqual(SoundEffects.fileName(for: "printer-a"),
                          SoundEffects.fileName(for: "printer-b"))
    }
}

/// The regression guard for the crash itself: a one-shot must never be the
/// thing that constructs the render graph.
@MainActor
final class OneShotsStayOffTheGraphTests: XCTestCase {

    override func setUp() {
        super.setUp()
        SettingsStore.shared.ambienceEnabled = false
        SettingsStore.shared.announcementsEnabled = false
        // The cues are gated on this one, so it has to be on or the test
        // proves only that the guard works.
        SettingsStore.shared.soundEffectsEnabled = true
    }

    override func tearDown() {
        SettingsStore.shared.soundEffectsEnabled = false
        super.tearDown()
    }

    func testFiringEveryOneShotDoesNotStartTheEngine() {
        let engine = CabinAudioEngine.shared
        engine.playSeatLatch()
        engine.playScanBeep()
        engine.playTearTick()
        engine.playRip()
        engine.playPrinter(feedSchedule: [0.18, 0.16, 0.15, 0.14])
        engine.playChime()
        engine.playChime(premium: true)
        engine.playSeatbeltSign()
        engine.playThunk()
        engine.playTouchdown()
        engine.playTakeoffSpool()
        engine.playDivertTone()
        XCTAssertFalse(engine.ambienceRunning)
    }
}
