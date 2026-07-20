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

    /// One-shots keep the engine alive until this deadline so `stopAmbience`
    /// cannot tear the graph down mid-buffer (rip → depart race).
    private var oneShotHoldUntil: Date = .distantPast
    private var teardownWorkItem: DispatchWorkItem?

    private init() {}

    // MARK: - Lifecycle

    /// Configures the session and starts the engine if ambience is enabled.
    func startAmbience(profile: Profile) {
        cancelPendingTeardown()
        guard SettingsStore.shared.ambienceEnabled else { return }
        setProfile(profile)
        startEngineIfNeeded()
    }

    func stopAmbience() {
        targetGain = 0
        // Let the bed (and any in-flight one-shot) finish before teardown.
        scheduleTeardown(after: 0.6)
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
            if !effectsPlayer.isPlaying {
                effectsPlayer.play()
            }
            isRunning = true
        } catch {
            // Audio is a garnish — never let it take the app down.
            isRunning = false
        }
    }

    private func buildGraph() {
        let output = engine.outputNode
        let hwRate = output.outputFormat(forBus: 0).sampleRate
        sampleRate = hwRate > 0 ? hwRate : 44_100
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            return
        }

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
                    guard let data = buffer.mData else { continue }
                    data.assumingMemoryBound(to: Float.self)[frame] = sample
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

    private func cancelPendingTeardown() {
        teardownWorkItem?.cancel()
        teardownWorkItem = nil
    }

    private func holdEngine(for duration: TimeInterval) {
        let until = Date().addingTimeInterval(duration)
        if until > oneShotHoldUntil {
            oneShotHoldUntil = until
        }
        cancelPendingTeardown()
    }

    private func scheduleTeardown(after delay: TimeInterval) {
        cancelPendingTeardown()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.targetGain == 0 else { return }
            let remaining = self.oneShotHoldUntil.timeIntervalSinceNow
            if remaining > 0.01 {
                self.scheduleTeardown(after: remaining)
                return
            }
            self.effectsPlayer.stop()
            self.engine.stop()
            self.isRunning = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            self.teardownWorkItem = nil
        }
        teardownWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.05, delay), execute: work)
    }

    // MARK: - One-shot effects

    /// Two-tone cabin chime ("bing-bong"). Platinum flyers get a richer triple chime.
    func playChime(premium: Bool = false) {
        guard SettingsStore.shared.ambienceEnabled || SettingsStore.shared.announcementsEnabled else { return }
        cancelPendingTeardown()
        startEngineIfNeeded()
        let notes: [(Double, Double)] = premium
            ? [(830.6, 0.0), (659.3, 0.35), (554.4, 0.70)]   // G#5, E5, C#5
            : [(659.3, 0.0), (523.3, 0.4)]                    // E5, C5
        guard let last = notes.last,
              let buffer = makeBuffer(duration: last.1 + 1.8, build: { i, t, sr in
            var sample: Float = 0
            for (freq, start) in notes {
                let local = t - start
                if local >= 0 {
                    // Soft mallet attack into a long, warm decay; a barely
                    // detuned pair beats gently like a real cabin chime bar.
                    let attack = 1 - expf(-90 * Float(local))
                    let env = attack * expf(-2.4 * Float(local))
                    let f = Float(freq)
                    sample += sinf(2 * .pi * f * Float(local)) * env * 0.13
                    sample += sinf(2 * .pi * f * 1.003 * Float(local)) * env * 0.05
                    sample += sinf(4 * .pi * f * Float(local)) * env * 0.02
                }
            }
            _ = i; _ = sr
            return sample
        }) else { return }
        holdEngine(for: last.1 + 2.0)
        schedule(buffer)
    }

    /// Paper-tear "zipper" for the boarding-pass rip: bright crackle whose
    /// fiber-snap rate accelerates through the tear, then dies off.
    func playRip() {
        guard SettingsStore.shared.ambienceEnabled || SettingsStore.shared.announcementsEnabled else { return }
        cancelPendingTeardown()
        startEngineIfNeeded()
        holdEngine(for: 0.8)
        guard let buffer = makeBuffer(duration: 0.55, build: { i, t, sr in
            let progress = Float(t / 0.55)
            let env = powf(1 - progress, 1.4)
            // Perforations popping: the snap rate speeds up as the tear runs.
            let zipRate = 60.0 + 220.0 * Double(progress)
            let zip = 0.35 + 0.65 * abs(sinf(Float(2 * .pi * zipRate * t)))
            // High-passed crackle: difference of consecutive white samples.
            let white = Float.random(in: -1...1)
            let crackle = white - (i % 2 == 0 ? 0.5 : -0.5) * Float.random(in: 0...1)
            _ = sr
            return crackle * zip * env * 0.5
        }) else { return }
        schedule(buffer)
    }

    /// Dot-matrix gate printer chattering out the boarding pass: gated
    /// print-head buzz over a soft feed-motor hum, with a paper-advance
    /// click each line.
    func playPrinter(duration: Double) {
        guard SettingsStore.shared.ambienceEnabled || SettingsStore.shared.announcementsEnabled else { return }
        cancelPendingTeardown()
        startEngineIfNeeded()
        holdEngine(for: duration + 0.3)
        guard let buffer = makeBuffer(duration: duration, build: { _, t, _ in
            let progress = Float(t / duration)
            let env = min(1, Float(t) / 0.08) * min(1, (1 - progress) / 0.12 + 0.001)
            // Print head: noise gated at line rate.
            let gate: Float = sinf(Float(2 * .pi * 24 * t)) > -0.1 ? 1 : 0.05
            let head = Float.random(in: -1...1) * 0.10 * gate
            // Head whine + feed motor.
            let whine = sinf(Float(2 * .pi * 880 * t)) * 0.020 * gate
            let motor = sinf(Float(2 * .pi * 118 * t)) * 0.035
            // Paper-advance click every line.
            let line = t.truncatingRemainder(dividingBy: 1.0 / 24 * 6)
            let click: Float = line < 0.004 ? Float.random(in: -0.25...0.25) : 0
            return (head + whine + motor + click) * min(1, env)
        }) else { return }
        schedule(buffer)
    }

    /// One perforation fiber snapping — played per ratchet step while the
    /// stub is pulled, so the tear is heard as it happens.
    func playTearTick() {
        guard SettingsStore.shared.ambienceEnabled || SettingsStore.shared.announcementsEnabled else { return }
        cancelPendingTeardown()
        startEngineIfNeeded()
        holdEngine(for: 0.15)
        guard let buffer = makeBuffer(duration: 0.06, build: { i, t, _ in
            let env = expf(-70 * Float(t))
            let white = Float.random(in: -1...1)
            let crackle = white - (i % 2 == 0 ? 0.5 : -0.5) * Float.random(in: 0...1)
            return crackle * env * 0.22
        }) else { return }
        schedule(buffer)
    }

    /// Engines spooling to takeoff power: a rising turbine whine over the
    /// swelling ambience bed.
    func playTakeoffSpool() {
        guard SettingsStore.shared.ambienceEnabled else { return }
        cancelPendingTeardown()
        startEngineIfNeeded()
        holdEngine(for: 3.2)
        guard let buffer = makeBuffer(duration: 3.0, build: { _, t, _ in
            let progress = Float(t / 3.0)
            // Fade in, hold, release into the (now louder) engine bed.
            let env = min(1, Float(t) / 0.8) * (t > 2.4 ? Float((3.0 - t) / 0.6) : 1)
            // Turbine whine sweeping up as N1 rises.
            let freq = 140.0 + 420.0 * Double(progress * progress)
            let phase = 2 * .pi * (140.0 * t + 210.0 * t * t * t / 9.0)
            let whine = sinf(Float(phase)) * 0.05 + sinf(Float(phase * 2.01)) * 0.02
            _ = freq
            // Low shove underneath.
            let rumble = sinf(Float(2 * .pi * 38 * t)) * 0.06 * progress
            return (whine + rumble) * env
        }) else { return }
        schedule(buffer)
    }

    /// Touchdown: main-gear thump, nose-gear thump, and a short tire chirp.
    func playTouchdown() {
        guard SettingsStore.shared.ambienceEnabled else { return }
        cancelPendingTeardown()
        startEngineIfNeeded()
        holdEngine(for: 1.6)
        guard let buffer = makeBuffer(duration: 1.4, build: { _, t, _ in
            var sample: Float = 0
            // Two gear thumps: mains at 0, nose at 0.55s.
            for (start, gain) in [(0.0, Float(0.7)), (0.55, Float(0.45))] {
                let local = t - start
                if local >= 0 {
                    let env = expf(-11 * Float(local))
                    sample += sinf(2 * .pi * 46 * Float(local)) * env * gain
                    if local < 0.02 { sample += Float.random(in: -0.35...0.35) * gain }
                }
            }
            // Tire chirp right at the mains.
            if t < 0.22 {
                let env = expf(-16 * Float(t))
                sample += Float.random(in: -1...1) * env * 0.18
            }
            return sample
        }) else { return }
        schedule(buffer)
    }

    /// Low mechanical thunk for landing gear.
    func playThunk() {
        cancelPendingTeardown()
        startEngineIfNeeded()
        holdEngine(for: 0.7)
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
        let sr = sampleRate > 0 ? sampleRate : 44_100
        let frames = AVAudioFrameCount(max(1, duration * sr))
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
        guard isRunning, engine.isRunning else { return }
        effectsPlayer.scheduleBuffer(buffer, at: nil, options: [])
        if !effectsPlayer.isPlaying {
            effectsPlayer.play()
        }
    }
}
