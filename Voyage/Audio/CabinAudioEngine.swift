import AVFoundation

/// Procedurally generated cabin soundscape: filtered noise for engine
/// rumble (with a swell during the takeoff roll), plus synthesized cabin
/// chimes and one-shot effects. No audio assets required.
final class CabinAudioEngine {

    /// How the engine bed should sound in each part of the flight.
    enum Profile {
        case silent
        case boarding      // faint APU hum
        case taxi
        case takeoffRoll   // full-power swell
        case climb
        case cruise
        case descent
        case landingRoll   // spoilers + reversers roar

        var gain: Float {
            switch self {
            case .silent: return 0
            case .boarding: return 0.05
            case .taxi: return 0.10
            case .takeoffRoll: return 0.42
            case .climb: return 0.26
            case .cruise: return 0.16
            case .descent: return 0.20
            case .landingRoll: return 0.45
            }
        }

        /// 0...1 brightness of the noise (how much high end survives).
        var brightness: Float {
            switch self {
            case .silent: return 0.02
            case .boarding: return 0.03
            case .taxi: return 0.06
            case .takeoffRoll: return 0.30
            case .climb: return 0.16
            case .cruise: return 0.10
            case .descent: return 0.13
            case .landingRoll: return 0.45
            }
        }
    }

    static let shared = CabinAudioEngine()

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let effectsPlayer = AVAudioPlayerNode()
    private var sampleRate: Double = 44100
    private var isRunning = false

    // Parameters read by the render thread, written from the main thread.
    // Smoothing inside the render loop makes races inaudible.
    private var targetGain: Float = 0
    private var targetBrightness: Float = 0.05
    private var duckFactor: Float = 1.0

    // Render-thread state.
    private var currentGain: Float = 0
    private var currentBrightness: Float = 0.05
    private var lp1: Float = 0
    private var lp2: Float = 0
    private var rumblePhase: Float = 0

    private init() {}

    // MARK: - Lifecycle

    /// Configures the session and starts the engine if ambience is enabled.
    func startAmbience(profile: Profile) {
        guard SettingsStore.shared.ambienceEnabled else { return }
        setProfile(profile)
        startEngineIfNeeded()
    }

    func stopAmbience() {
        targetGain = 0
        // Let the tail fade before tearing the engine down.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.targetGain == 0 else { return }
            self.engine.stop()
            self.isRunning = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    func setProfile(_ profile: Profile) {
        // One-shot effects (chime, thunk) may keep the engine alive while
        // ambience is switched off — keep the bed silent in that case.
        targetGain = SettingsStore.shared.ambienceEnabled ? profile.gain : 0
        targetBrightness = profile.brightness
    }

    /// Lower the bed while the PA speaks.
    func setDucked(_ ducked: Bool) {
        duckFactor = ducked ? 0.35 : 1.0
    }

    var ambienceRunning: Bool { isRunning }

    private func startEngineIfNeeded() {
        guard !isRunning else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            if sourceNode == nil {
                buildGraph()
            }
            engine.prepare()
            try engine.start()
            isRunning = true
        } catch {
            // Audio is a garnish — never let it take the app down.
            isRunning = false
        }
    }

    private func buildGraph() {
        let output = engine.outputNode
        sampleRate = output.outputFormat(forBus: 0).sampleRate
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)

        let node = AVAudioSourceNode { [weak self] (_, _, frameCount, audioBufferList) -> OSStatus in
            guard let self else { return noErr }
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let gainStep: Float = 1.0 / Float(self.sampleRate * 1.2)   // ~1.2 s full swell
            let brightStep: Float = 1.0 / Float(self.sampleRate * 0.8)

            for frame in 0..<Int(frameCount) {
                // Glide toward targets so profile changes sound like thrust changes.
                let goalGain = self.targetGain * self.duckFactor
                if self.currentGain < goalGain {
                    self.currentGain = min(self.currentGain + gainStep, goalGain)
                } else {
                    self.currentGain = max(self.currentGain - gainStep, goalGain)
                }
                if self.currentBrightness < self.targetBrightness {
                    self.currentBrightness = min(self.currentBrightness + brightStep, self.targetBrightness)
                } else {
                    self.currentBrightness = max(self.currentBrightness - brightStep, self.targetBrightness)
                }

                let white = Float.random(in: -1...1)
                // Two cascaded one-pole low-passes; brightness moves the cutoff.
                let alpha = 0.02 + self.currentBrightness * 0.25
                self.lp1 += alpha * (white - self.lp1)
                self.lp2 += alpha * (self.lp1 - self.lp2)

                // Slow amplitude wobble so the rumble breathes a little.
                self.rumblePhase += 0.35 / Float(self.sampleRate)
                if self.rumblePhase > 1 { self.rumblePhase -= 1 }
                let wobble = 0.92 + 0.08 * sin(self.rumblePhase * 2 * .pi)

                let sample = self.lp2 * 3.2 * self.currentGain * wobble
                for buffer in ablPointer {
                    let buf = UnsafeMutableBufferPointer<Float>(buffer)
                    buf[frame] = sample
                }
            }
            return noErr
        }

        engine.attach(node)
        engine.attach(effectsPlayer)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.connect(effectsPlayer, to: engine.mainMixerNode, format: format)
        sourceNode = node
    }

    // MARK: - One-shot effects

    /// Two-tone cabin chime ("bing-bong"). Platinum flyers get a richer triple chime.
    func playChime(premium: Bool = false) {
        guard SettingsStore.shared.ambienceEnabled || SettingsStore.shared.announcementsEnabled else { return }
        startEngineIfNeeded()
        let notes: [(Double, Double)] = premium
            ? [(830.6, 0.0), (659.3, 0.35), (554.4, 0.70)]   // G#5, E5, C#5
            : [(659.3, 0.0), (523.3, 0.4)]                    // E5, C5
        guard let buffer = makeBuffer(duration: notes.last!.1 + 1.2, build: { i, t, sr in
            var sample: Float = 0
            for (freq, start) in notes {
                let local = t - start
                if local >= 0 {
                    let env = expf(-3.2 * Float(local))
                    sample += sinf(2 * .pi * Float(freq) * Float(local)) * env * 0.16
                    // soft second harmonic for a glockenspiel feel
                    sample += sinf(4 * .pi * Float(freq) * Float(local)) * env * 0.04
                }
            }
            return sample
        }) else { return }
        schedule(buffer)
    }

    /// Sharp paper-tear burst for the boarding-pass rip.
    func playRip() {
        startEngineIfNeeded()
        guard let buffer = makeBuffer(duration: 0.45, build: { i, t, sr in
            let progress = Float(t / 0.45)
            let env = (1 - progress) * (1 - progress)
            // High-passed crackle: difference of consecutive white samples.
            let white = Float.random(in: -1...1)
            let crackle = white - (i % 2 == 0 ? 0.5 : -0.5) * Float.random(in: 0...1)
            _ = sr
            return crackle * env * 0.5
        }) else { return }
        schedule(buffer)
    }

    /// Low mechanical thunk for landing gear.
    func playThunk() {
        startEngineIfNeeded()
        guard let buffer = makeBuffer(duration: 0.5, build: { _, t, _ in
            let env = expf(-9 * Float(t))
            let body = sinf(2 * .pi * 52 * Float(t)) * env * 0.55
            let click = t < 0.02 ? Float.random(in: -0.4...0.4) : 0
            return body + click
        }) else { return }
        schedule(buffer)
    }

    // MARK: - Buffer helpers

    private func makeBuffer(duration: Double, build: (Int, Double, Double) -> Float) -> AVAudioPCMBuffer? {
        let sr = sampleRate
        let frames = AVAudioFrameCount(duration * sr)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            channel[i] = build(i, Double(i) / sr, sr)
        }
        return buffer
    }

    private func schedule(_ buffer: AVAudioPCMBuffer) {
        guard engine.isRunning else { return }
        effectsPlayer.scheduleBuffer(buffer, at: nil, options: [])
        if !effectsPlayer.isPlaying {
            effectsPlayer.play()
        }
    }
}
