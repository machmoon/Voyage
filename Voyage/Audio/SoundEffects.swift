import AVFoundation
import AudioToolbox

/// Short, fixed one-shots — the seat latch, the tear tick, the printer, the
/// chimes, the gear thunk — play through System Sound Services rather than
/// through `CabinAudioEngine`'s render graph.
///
/// **Why they are not on the graph.** Touching `AVAudioEngine.outputNode` or
/// `mainMixerNode` for the first time is a synchronous RPC to the audio
/// server, and AudioToolbox answers a timeout by calling `abort()` rather than
/// by returning an error. That is not catchable, and it is not thread-local:
/// it takes the process down from whatever thread made the call. Twenty-five
/// SIGABRTs on 2026-09-08 all came through that path
/// (`_ReportRPCTimeout` → `AURemoteIO::Cleanup()` →
/// `AVAudioIONodeImpl::GetOutputFormat` → `-[AVAudioEngine outputNode]`), and
/// the entry point was a cue fired from a tap or a drag. Since the call cannot
/// be made safe, the only lever is to make fewer of them. A click does not
/// need a render graph, so it does not get one.
///
/// `AudioServicesPlaySystemSound` builds no graph, attaches no node and never
/// reads either aborting property; playback happens in the system sound
/// server, out of our process entirely.
///
/// **Structure.** Register a `SystemSoundID` per cue once, keep it for the life
/// of the process, and play by id. That is
/// `IceCubesApp/Packages/Env/Sources/Env/SoundEffectManager.swift`
/// (`registerSounds()` / `register(url:for:)` / `playSound(_:)`) — a shipping
/// Mastodon client whose UI sounds sit alongside its media playback for exactly
/// this reason.
///
/// **Where Voyage deviates, and why.** IceCubes registers bundled `.wav`
/// files. Voyage ships no audio assets for these cues: they are generated from
/// a formula, which is what makes them feel like part of the app rather than a
/// sound pack. So the first time a cue is asked for it is rendered to a CAF in
/// the caches directory and that file is registered. The render is arithmetic
/// and a file write; it touches no audio unit and cannot reach the aborting
/// RPC. Caches are wiped at startup so a change to a waveform can never be
/// masked by a stale file.
///
/// **Known cost.** System sounds play at the system sound volume and cannot be
/// mixed, ducked or faded. Nothing here needed that: a click is a click. They
/// follow the ring/silent switch, which matches the cabin bed — Voyage's
/// session is `.ambient` (`CabinAudioEngine.startEngineIfNeeded`), so the whole
/// app already goes quiet on silent. The levels in each cue's formula are
/// unchanged, but they now land against the system sound volume rather than the
/// bed's mixer, so the balance between a click and the cabin is worth an ears
/// check on a device.
///
/// Main thread only.
final class SoundEffects {

    static let shared = SoundEffects()

    static let sampleRate: Double = 44_100

    private let directory: URL
    private var soundIDs: [String: SystemSoundID] = [:]
    /// Keys whose render or registration failed. Retried never: a device that
    /// cannot write a 20 KB file will not do better on the next tap.
    private var failed: Set<String> = []
    /// Number of cues actually rendered, so the cache can be asserted on.
    private(set) var renderCount = 0

    /// - Parameter directory: where rendered cues are written. Tests pass their
    ///   own so they never share state with the running app.
    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SoundEffects", isDirectory: true)
        self.directory = base
        try? FileManager.default.removeItem(at: base)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    deinit {
        for id in soundIDs.values { AudioServicesDisposeSystemSoundID(id) }
    }

    /// Renders the cue if this is the first time it has been asked for, then
    /// plays it. Never blocks on the audio server and never builds a graph.
    ///
    /// - Parameters:
    ///   - key: identifies the waveform. Two calls with the same key must
    ///     describe the same sound, because the second one reuses the first
    ///     one's file.
    ///   - duration: seconds, must be positive and (System Sound Services)
    ///     under 30.
    ///   - build: `(frame index, time in seconds, sample rate) -> sample`,
    ///     the same shape the engine's buffer builder used.
    func play(_ key: String, duration: Double, build: (Int, Double, Double) -> Float) {
        guard let id = prepare(key, duration: duration, build: build) else { return }
        guard Self.playbackIsAvailable else { return }
        AudioServicesPlaySystemSound(id)
    }

    /// Renders and registers without playing, for cues a screen knows it is
    /// about to need. Returns the id, or nil if the cue cannot be produced.
    @discardableResult
    func prepare(_ key: String, duration: Double, build: (Int, Double, Double) -> Float) -> SystemSoundID? {
        if let existing = soundIDs[key] { return existing }
        guard !failed.contains(key) else { return nil }
        guard duration > 0, duration < 30 else {
            failed.insert(key)
            return nil
        }
        guard let url = render(key: key, duration: duration, build: build) else {
            failed.insert(key)
            return nil
        }
        var id: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(url as CFURL, &id) == kAudioServicesNoError else {
            failed.insert(key)
            return nil
        }
        soundIDs[key] = id
        return id
    }

    /// Drops every registration. Tests only.
    func reset() {
        for id in soundIDs.values { AudioServicesDisposeSystemSoundID(id) }
        soundIDs.removeAll()
        failed.removeAll()
        renderCount = 0
    }

    func fileURL(forKey key: String) -> URL {
        directory.appendingPathComponent(Self.fileName(for: key))
    }

    // MARK: - Rendering

    private func render(key: String, duration: Double, build: (Int, Double, Double) -> Float) -> URL? {
        let rate = Self.sampleRate
        let frames = AVAudioFrameCount(max(1, duration * rate))
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            // Clamped because the file is 16-bit integer: an overshoot would
            // wrap into a click rather than clip.
            samples[i] = min(1, max(-1, build(i, Double(i) / rate, rate)))
        }

        let url = fileURL(forKey: key)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        do {
            let file = try AVAudioFile(forWriting: url, settings: settings)
            try file.write(from: buffer)
        } catch {
            return nil
        }
        renderCount += 1
        return url
    }

    /// A readable prefix so the caches directory can be understood by eye,
    /// plus a hash so any key at all is a legal file name.
    static func fileName(for key: String) -> String {
        let readable = String(key.prefix(24).map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "-" })
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in key.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        return "\(readable)-\(String(hash, radix: 16)).caf"
    }

    /// Under XCTest nothing should make noise, and the host's sound server is
    /// routinely starved by parallel simulators. Same guard, and the same
    /// reasoning, as `WeatherService.reading(for:)` and
    /// `CabinAudioEngine.audioIsAvailable`. Rendering and registration still
    /// run, so the tests cover everything except the final call.
    private static var playbackIsAvailable: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }
}
