import AVFoundation

/// A restrained, procedural cabin soundscape.
///
/// The ambience is a pre-rendered loop instead of realtime-generated noise.
/// That keeps audio work off the render callback and avoids the crackle and
/// dropped frames the previous source-node implementation could cause. All
/// sound is generated on device; Voyage ships no recordings or audio assets.
final class CabinAudioEngine {
    enum Profile {
        case silent, boarding, taxi, takeoffRoll, climb, cruise, descent, landingRoll

        var volume: Float {
            switch self {
            case .silent: return 0
            case .boarding: return 0.035
            case .taxi: return 0.065
            case .takeoffRoll: return 0.18
            case .climb: return 0.125
            case .cruise: return 0.075
            case .descent: return 0.09
            case .landingRoll: return 0.17
            }
        }

        var cutoff: Float {
            switch self {
            case .silent, .boarding: return 480
            case .taxi: return 680
            case .takeoffRoll: return 1_500
            case .climb: return 1_050
            case .cruise: return 760
            case .descent: return 900
            case .landingRoll: return 1_750
            }
        }
    }

    static let shared = CabinAudioEngine()

    private let engine = AVAudioEngine()
    private let ambiencePlayer = AVAudioPlayerNode()
    private let ambienceFilter = AVAudioUnitEQ(numberOfBands: 1)
    private let effectsPlayer = AVAudioPlayerNode()
    /// Announcements run through their own band-limited chain so a clean studio
    /// recording arrives sounding like it came out of a ceiling speaker.
    private let announcementPlayer = AVAudioPlayerNode()
    private let paFilter = AVAudioUnitEQ(numberOfBands: 3)
    private var ambienceBuffer: AVAudioPCMBuffer?
    private var graphBuilt = false
    private var ambienceScheduled = false
    private var profile: Profile = .silent
    private var ducked = false
    private var rampGeneration = 0
    private var announcementGeneration = 0

    private init() {}

    var ambienceRunning: Bool {
        engine.isRunning && ambiencePlayer.isPlaying && profile != .silent
    }

    func startAmbience(profile: Profile) {
        guard SettingsStore.shared.ambienceEnabled else { return }
        startEngineIfNeeded()
        setProfile(profile)
    }

    func stopAmbience() {
        profile = .silent
        rampAmbience(to: 0, duration: 0.7)
    }

    func setProfile(_ profile: Profile) {
        self.profile = profile
        guard SettingsStore.shared.ambienceEnabled else {
            rampAmbience(to: 0, duration: 0.25)
            return
        }
        startEngineIfNeeded()
        ambienceFilter.bands[0].frequency = profile.cutoff
        rampAmbience(to: profile.volume * (ducked ? 0.28 : 1), duration: 0.65)
    }

    func setDucked(_ ducked: Bool) {
        self.ducked = ducked
        let target = SettingsStore.shared.ambienceEnabled
            ? profile.volume * (ducked ? 0.28 : 1)
            : 0
        rampAmbience(to: target, duration: ducked ? 0.2 : 0.55)
    }

    // MARK: Cabin PA

    /// Plays a pre-rendered announcement through the PA chain.
    ///
    /// Returns `false` when the clip cannot be played, which is the caller's
    /// signal to fall back to on-device speech. Announcements are never
    /// synthesized over the network during a flight.
    func playAnnouncement(url: URL, completion: @escaping () -> Void) -> Bool {
        startEngineIfNeeded()
        guard engine.isRunning,
              let file = try? AVAudioFile(forReading: url),
              file.processingFormat.sampleRate == 44_100,
              file.processingFormat.channelCount == 1,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil,
              buffer.frameLength > 0
        else { return false }

        announcementGeneration += 1
        let generation = announcementGeneration
        announcementPlayer.stop()
        announcementPlayer.play()
        setDucked(true)
        announcementPlayer.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                // A newer announcement already took the speaker; leave its ducking alone.
                guard let self, self.announcementGeneration == generation else { return }
                self.setDucked(false)
                completion()
            }
        }
        return true
    }

    func stopPA() {
        announcementGeneration += 1
        announcementPlayer.stop()
        setDucked(false)
    }

    // MARK: Direct-manipulation and flight cues

    func playChime(premium: Bool = false) {
        guard soundEffectsEnabled else { return }
        let notes: [(Double, Double)] = premium
            ? [(784, 0), (659, 0.28), (523, 0.56)]
            : [(659, 0), (523, 0.34)]
        play(duration: premium ? 1.45 : 1.2) { _, t, _ in
            notes.reduce(0) { sample, note in
                let local = t - note.1
                guard local >= 0 else { return sample }
                let envelope = (1 - exp(-70 * local)) * exp(-3.1 * local)
                return sample
                    + Float(sin(2 * .pi * note.0 * local) * envelope * 0.095)
                    + Float(sin(2 * .pi * note.0 * 2.01 * local) * envelope * 0.018)
            }
        }
    }

    func playRip() {
        guard soundEffectsEnabled else { return }
        var previous: Float = 0
        play(duration: 0.38) { i, t, _ in
            let progress = Float(t / 0.38)
            let noise = Self.noise(i &* 19 &+ 31)
            let high = noise - previous * 0.84
            previous = noise
            let zipper = 0.45 + 0.55 * abs(sin(Float(t) * (260 + 520 * progress)))
            return high * zipper * pow(1 - progress, 0.75) * 0.24
        }
    }

    func playPrinter(feedSchedule: [Double]) {
        guard soundEffectsEnabled else { return }
        var starts: [Double] = []
        var cursor = 0.0
        for gap in feedSchedule {
            starts.append(cursor)
            cursor += gap
        }
        let completion = cursor + 0.12
        play(duration: completion + 0.42) { i, t, _ in
            var sample: Float = t < cursor ? Float(sin(2 * .pi * 92 * t)) * 0.012 : 0
            for start in starts {
                let local = t - start
                if local >= 0, local < 0.065 {
                    let envelope = Float(sin(.pi * local / 0.065))
                    sample += Self.noise(i &+ Int(start * 10_000)) * envelope * 0.045
                    sample += Float(sin(2 * .pi * 145 * local)) * envelope * 0.025
                }
            }
            for start in [completion, completion + 0.18] {
                let local = t - start
                if local >= 0, local < 0.09 {
                    sample += Float(sin(2 * .pi * 1_180 * local)) * Float(sin(.pi * local / 0.09)) * 0.045
                }
            }
            return sample
        }
    }

    func playTearTick() {
        guard soundEffectsEnabled else { return }
        play(duration: 0.045) { i, t, _ in
            Self.noise(i &* 7 &+ 13) * Float(exp(-85 * t)) * 0.11
        }
    }

    func playTakeoffSpool() {
        guard soundEffectsEnabled else { return }
        play(duration: 2.8) { _, t, _ in
            let progress = Float(t / 2.8)
            let envelope = min(1, Float(t) / 0.55) * min(1, Float((2.8 - t) / 0.5))
            let phase = 2 * Double.pi * (125 * t + 52 * t * t)
            let turbine = Float(sin(phase)) * 0.032 + Float(sin(phase * 2.01)) * 0.009
            let body = Float(sin(2 * .pi * 39 * t)) * progress * 0.022
            return (turbine + body) * envelope
        }
    }

    func playTouchdown() {
        guard soundEffectsEnabled else { return }
        play(duration: 1.25) { i, t, _ in
            var sample: Float = 0
            for (start, gain) in [(0.0, Float(0.34)), (0.42, Float(0.21))] {
                let local = t - start
                if local >= 0 {
                    sample += Float(sin(2 * .pi * 47 * local)) * Float(exp(-12 * local)) * gain
                    if local < 0.035 { sample += Self.noise(i &+ Int(start * 1_000)) * gain * 0.18 }
                }
            }
            if t < 0.18 { sample += Self.noise(i &* 3) * Float(exp(-18 * t)) * 0.07 }
            return sample
        }
    }

    func playThunk() {
        guard soundEffectsEnabled else { return }
        play(duration: 0.42) { i, t, _ in
            let body = Float(sin(2 * .pi * 54 * t)) * Float(exp(-13 * t)) * 0.28
            let latch = t < 0.018 ? Self.noise(i &* 11) * 0.08 : 0
            return body + latch
        }
    }

    /// The seatbelt sign: two hollow, bell-like bongs. Deliberately lower and
    /// longer than `playChime` so the two never read as the same event.
    func playSeatbeltSign() {
        guard soundEffectsEnabled else { return }
        // Inharmonic partials are what separate a struck bell from a sine beep.
        let partials: [(Double, Float)] = [(1, 0.085), (2.02, 0.03), (2.76, 0.014), (5.1, 0.005)]
        play(duration: 2.6) { _, t, _ in
            [0.0, 0.62].reduce(0) { sample, start in
                let local = t - start
                guard local >= 0 else { return sample }
                let strike = (1 - exp(-260 * local))
                return sample + partials.reduce(0) { voice, partial in
                    let decay = exp(-1.55 * local * Double(partial.0))
                    return voice + Float(sin(2 * .pi * 392 * partial.0 * local) * decay) * partial.1 * Float(strike)
                }
            }
        }
    }

    /// Seat selection: the click of a latch with a little cushion behind it.
    func playSeatLatch() {
        guard soundEffectsEnabled else { return }
        play(duration: 0.16) { i, t, _ in
            let click = t < 0.006 ? Self.noise(i &* 23 &+ 5) * 0.16 : 0
            let body = Float(sin(2 * .pi * 148 * t)) * Float(exp(-34 * t)) * 0.09
            return click + body
        }
    }

    /// The single clean beep of a gate scanner reading a barcode.
    func playScanBeep() {
        guard soundEffectsEnabled else { return }
        play(duration: 0.13) { _, t, _ in
            // Flat body with fast edges reads as electronic rather than musical.
            let envelope = min(1, Float(t) / 0.004) * min(1, Float((0.1 - t) / 0.012))
            guard envelope > 0 else { return 0 }
            return (Float(sin(2 * .pi * 2_093 * t)) * 0.075
                + Float(sin(2 * .pi * 4_186 * t)) * 0.012) * envelope
        }
    }

    /// Diversion: a muted descending pair. Soft attacks and a flattened
    /// interval make it land as disappointment rather than alarm.
    func playDivertTone() {
        guard soundEffectsEnabled else { return }
        let notes: [(Double, Double)] = [(415, 0), (311, 0.34)]
        play(duration: 1.5) { _, t, _ in
            notes.reduce(0) { sample, note in
                let local = t - note.1
                guard local >= 0 else { return sample }
                let envelope = (1 - exp(-14 * local)) * exp(-2.4 * local)
                return sample + Float(sin(2 * .pi * note.0 * local) * envelope * 0.075)
            }
        }
    }

    // MARK: Audio graph

    private var soundEffectsEnabled: Bool {
        SettingsStore.shared.soundEffectsEnabled
    }

    private func startEngineIfNeeded() {
        if !graphBuilt { buildGraph() }
        guard graphBuilt else { return }

        if !engine.isRunning {
            do {
                let session = AVAudioSession.sharedInstance()
                // Ambient respects the Ring/Silent switch and coexists with a
                // passenger's music instead of taking ownership of the device.
                try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
                try session.setActive(true)
                engine.prepare()
                try engine.start()
            } catch {
                return // Sound is enhancement, never a reason to block a flight.
            }
        }

        if !ambienceScheduled, let ambienceBuffer {
            ambiencePlayer.scheduleBuffer(ambienceBuffer, at: nil, options: .loops)
            ambienceScheduled = true
        }
        if !ambiencePlayer.isPlaying { ambiencePlayer.play() }
        if !effectsPlayer.isPlaying { effectsPlayer.play() }
    }

    /// A ceiling speaker is a small, band-limited driver in a hard-trimmed
    /// cabin. Rolling off the chest and the air, then lifting presence, is what
    /// turns a clean studio read into a public-address announcement.
    private func configurePAFilter() {
        let bands = paFilter.bands
        bands[0].filterType = .highPass
        bands[0].frequency = 240
        bands[0].bypass = false
        bands[1].filterType = .parametric
        bands[1].frequency = 2_400
        bands[1].bandwidth = 1.1
        bands[1].gain = 4.5
        bands[1].bypass = false
        bands[2].filterType = .lowPass
        bands[2].frequency = 5_000
        bands[2].bypass = false
        paFilter.globalGain = 1.5
    }

    private func buildGraph() {
        let rate = 44_100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let loop = makeAmbienceLoop(format: format) else { return }

        ambienceFilter.bands[0].filterType = .lowPass
        ambienceFilter.bands[0].frequency = Profile.boarding.cutoff
        ambienceFilter.bands[0].bandwidth = 0.6
        ambienceFilter.bands[0].bypass = false
        ambiencePlayer.volume = 0

        configurePAFilter()

        engine.attach(ambiencePlayer)
        engine.attach(ambienceFilter)
        engine.attach(effectsPlayer)
        engine.attach(announcementPlayer)
        engine.attach(paFilter)
        engine.connect(ambiencePlayer, to: ambienceFilter, format: format)
        engine.connect(ambienceFilter, to: engine.mainMixerNode, format: format)
        engine.connect(effectsPlayer, to: engine.mainMixerNode, format: format)
        engine.connect(announcementPlayer, to: paFilter, format: format)
        engine.connect(paFilter, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.86
        ambienceBuffer = loop
        graphBuilt = true
    }

    private func rampAmbience(to target: Float, duration: Double) {
        rampGeneration += 1
        let generation = rampGeneration
        let start = ambiencePlayer.volume
        let steps = max(1, Int(duration * 30))
        for step in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration * Double(step) / Double(steps)) { [weak self] in
                guard let self, self.rampGeneration == generation else { return }
                let x = Float(step) / Float(steps)
                let eased = x * x * (3 - 2 * x)
                self.ambiencePlayer.volume = start + (target - start) * eased
            }
        }
    }

    private func play(duration: Double, build: (Int, Double, Double) -> Float) {
        startEngineIfNeeded()
        guard engine.isRunning,
              let buffer = makeBuffer(duration: duration, build: build) else { return }
        effectsPlayer.scheduleBuffer(buffer)
        if !effectsPlayer.isPlaying { effectsPlayer.play() }
    }

    private func makeBuffer(duration: Double, build: (Int, Double, Double) -> Float) -> AVAudioPCMBuffer? {
        let rate = 44_100.0
        let frames = AVAudioFrameCount(max(1, duration * rate))
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) { samples[i] = build(i, Double(i) / rate, rate) }
        return buffer
    }

    private func makeAmbienceLoop(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let duration = 7.0
        let count = Int(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(count)

        var low: Float = 0
        var lower: Float = 0
        for i in 0..<count {
            let white = Self.noise(i)
            low += 0.11 * (white - low)
            lower += 0.025 * (low - lower)
            let t = Double(i) / format.sampleRate
            let engines = Float(sin(2 * .pi * 43 * t)) * 0.11
                + Float(sin(2 * .pi * 86 * t + 0.7)) * 0.035
            let breathe = 0.92 + Float(sin(2 * .pi * t / duration)) * 0.08
            samples[i] = (lower * 1.8 + low * 0.28 + engines) * breathe
        }

        // Crossfade the tail into the head so `.loops` has no audible seam.
        let fade = Int(format.sampleRate * 0.32)
        for i in 0..<fade {
            let x = Float(i) / Float(fade)
            let tailIndex = count - fade + i
            samples[tailIndex] = samples[tailIndex] * (1 - x) + samples[i] * x
        }
        return buffer
    }

    /// Fast deterministic noise: reproducible, allocation-free, and never
    /// evaluated on AVAudioEngine's realtime render thread.
    private static func noise(_ index: Int) -> Float {
        var x = UInt32(truncatingIfNeeded: index) &+ 0x9E37_79B9
        x ^= x >> 16
        x &*= 0x7FEB_352D
        x ^= x >> 15
        x &*= 0x846C_A68B
        x ^= x >> 16
        return Float(x) / Float(UInt32.max) * 2 - 1
    }
}
