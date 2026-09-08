import AVFoundation

/// A restrained, procedural cabin soundscape.
///
/// The ambience is two layers. A broadband noise bed carries the hiss of the
/// turbulent boundary layer over the fuselage, and beneath it an engine tone
/// layer carries the low-frequency rumble that engine vibration couples into
/// the cabin, keyed to the flight phase and crossfaded when the phase changes.
///
/// Both layers are pre-rendered loops driven by player nodes rather than
/// realtime-generated. That keeps audio work off the render callback and avoids
/// the crackle and dropped frames the previous source-node implementation could
/// cause, which is why a new layer is a new loop and not a new source node.
///
/// All sound is generated on device. The one exception is the PA: recorded crew
/// and captain lines ship in `Voyage/Resources/PA/*.m4a`, and `Announcer`
/// synthesizes only when the traveler picks a device voice instead.
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

        /// Fundamental of the engine tone layer, in Hz.
        ///
        /// Engine vibration couples through the fuselage as low-frequency
        /// content in roughly the 30-120 Hz band, and the fundamental tracks
        /// fan speed: highest at takeoff thrust, lowest at flight idle on the
        /// way down. Boarding and taxi sit below the band because what carries
        /// then is the APU and cabin systems, not the fans.
        var toneFundamental: Double {
            switch self {
            case .silent: return 0
            case .boarding: return 24
            case .taxi: return 27
            case .takeoffRoll: return 52
            case .climb: return 48
            case .cruise: return 43
            case .descent: return 31
            case .landingRoll: return 45
            }
        }

        /// Level of the tone layer, kept under `volume` so the tone sits
        /// beneath the noise bed rather than replacing it.
        var toneVolume: Float {
            switch self {
            case .silent: return 0
            case .boarding: return 0.020
            case .taxi: return 0.045
            case .takeoffRoll: return 0.155
            case .climb: return 0.115
            case .cruise: return 0.075
            case .descent: return 0.055
            case .landingRoll: return 0.135
            }
        }
    }

    static let shared = CabinAudioEngine()

    private let engine = AVAudioEngine()
    private let ambiencePlayer = AVAudioPlayerNode()
    private let ambienceFilter = AVAudioUnitEQ(numberOfBands: 1)
    /// The engine tone rides two players so a phase change can crossfade one
    /// fundamental into the next. A single player would have to stop before it
    /// could take a new loop, which is a hole in the layer rather than a fade.
    private let tonePlayerA = AVAudioPlayerNode()
    private let tonePlayerB = AVAudioPlayerNode()
    private let toneMixer = AVAudioMixerNode()
    private let toneFilter = AVAudioUnitEQ(numberOfBands: 1)
    /// Announcements run through their own band-limited chain so a clean studio
    /// recording arrives sounding like it came out of a ceiling speaker.
    private let announcementPlayer = AVAudioPlayerNode()
    private let paFilter = AVAudioUnitEQ(numberOfBands: 3)
    private var ambienceBuffer: AVAudioPCMBuffer?
    private var graphBuilt = false
    private var ambienceScheduled = false
    private var profile: Profile = .silent
    private var ducked = false
    private var announcementGeneration = 0
    /// One ramp generation per node, so a fade on the tone layer cannot cancel
    /// a fade already running on the bed.
    private var rampGenerations: [ObjectIdentifier: Int] = [:]
    /// Tone loops keyed by fundamental, built once and reused. A flight revisits
    /// phases (climb after a level-off, descent then landing) and rebuilding the
    /// buffer each time would burn the same work again.
    private var toneBuffers: [Double: AVAudioPCMBuffer] = [:]
    private var toneFormat: AVAudioFormat?
    private var liveTonePlayer: AVAudioPlayerNode?
    private var liveToneFundamental: Double = 0
    private var toneBuildGeneration = 0

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
        setToneLayer(for: .silent, duration: 0.7)
    }

    func setProfile(_ profile: Profile) {
        self.profile = profile
        guard SettingsStore.shared.ambienceEnabled else {
            rampAmbience(to: 0, duration: 0.25)
            setToneLayer(for: .silent, duration: 0.25)
            return
        }
        startEngineIfNeeded()
        ambienceFilter.bands[0].frequency = profile.cutoff
        rampAmbience(to: profile.volume * (ducked ? 0.28 : 1), duration: 0.65)
        setToneLayer(for: profile, duration: 0.65)
    }

    func setDucked(_ ducked: Bool) {
        self.ducked = ducked
        let enabled = SettingsStore.shared.ambienceEnabled
        let duration = ducked ? 0.2 : 0.55
        rampAmbience(to: enabled ? profile.volume * duckFactor : 0, duration: duration)
        setToneLayer(for: enabled ? profile : .silent, duration: duration)
    }

    private var duckFactor: Float { ducked ? 0.28 : 1 }

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
        play(premium ? "chime-premium" : "chime", duration: premium ? 1.45 : 1.2) { _, t, _ in
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
        play("rip", duration: 0.38) { i, t, _ in
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
        play("printer-\(Self.digest(feedSchedule))", duration: completion + 0.42) { i, t, _ in
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
        play("tear-tick", duration: 0.045) { i, t, _ in
            Self.noise(i &* 7 &+ 13) * Float(exp(-85 * t)) * 0.11
        }
    }

    func playTakeoffSpool() {
        guard soundEffectsEnabled else { return }
        play("takeoff-spool", duration: 2.8) { _, t, _ in
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
        play("touchdown", duration: 1.25) { i, t, _ in
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
        play("thunk", duration: 0.42) { i, t, _ in
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
        play("seatbelt-sign", duration: 2.6) { _, t, _ in
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
        play("seat-latch", duration: 0.16) { i, t, _ in
            let click = t < 0.006 ? Self.noise(i &* 23 &+ 5) * 0.16 : 0
            let body = Float(sin(2 * .pi * 148 * t)) * Float(exp(-34 * t)) * 0.09
            return click + body
        }
    }

    /// The single clean beep of a gate scanner reading a barcode.
    func playScanBeep() {
        guard soundEffectsEnabled else { return }
        play("scan-beep", duration: 0.13) { _, t, _ in
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
        play("divert-tone", duration: 1.5) { _, t, _ in
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

    /// Whether we may touch `AVAudioEngine` at all.
    ///
    /// Building the graph reads `AVAudioEngine.outputNode` and
    /// `mainMixerNode`, each a synchronous RPC to the audio server that
    /// AudioToolbox answers with `abort()` on timeout. No `do/catch` and no
    /// choice of thread survives that, so the only lever is to make fewer of
    /// the calls. Under XCTest there is nothing to hear and the host's audio
    /// server is routinely starved by parallel simulators — same guard, same
    /// reasoning as `WeatherService.reading(for:)`.
    private static var audioIsAvailable: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }

    /// Builds the graph ahead of the first cue that needs it, away from any
    /// tap or drag. `BoardingFlowView.onAppear` calls it on entry to the
    /// ritual.
    ///
    /// Not at app launch, deliberately: an abort during boarding costs one
    /// session and the traveler can start again, while an abort at launch
    /// makes the app look permanently broken. A rarer but unrecoverable
    /// failure is the worse trade. Moving this call is one line.
    ///
    /// This does not make the construction call safe — nothing can. It moves
    /// it off the interaction path and out of the departure beat, and the
    /// one-shots no longer reach it at all (see `play(_:duration:build:)`).
    func prewarm() {
        guard SettingsStore.shared.ambienceEnabled || SettingsStore.shared.announcementsEnabled else { return }
        startEngineIfNeeded()
    }

    private func startEngineIfNeeded() {
        guard Self.audioIsAvailable else { return }

        if !engine.isRunning {
            do {
                let session = AVAudioSession.sharedInstance()
                // Ambient respects the Ring/Silent switch and coexists with a
                // passenger's music instead of taking ownership of the device.
                try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
                try session.setActive(true)
                // The session comes up before the graph, deliberately. Building
                // a graph against an inactive session gives the audio server
                // more to do at exactly the moment a slow answer is fatal.
                if !graphBuilt { buildGraph() }
                guard graphBuilt else { return }
                engine.prepare()
                try engine.start()
            } catch {
                return // Sound is enhancement, never a reason to block a flight.
            }
            // A stopped engine drops whatever the tone players had scheduled.
            // Forget which loop was live so the next profile re-schedules it
            // instead of ramping a player that is no longer playing.
            liveTonePlayer = nil
            liveToneFundamental = 0
            tonePlayerA.volume = 0
            tonePlayerB.volume = 0
        }

        if !ambienceScheduled, let ambienceBuffer {
            ambiencePlayer.scheduleBuffer(ambienceBuffer, at: nil, options: .loops)
            ambienceScheduled = true
        }
        if !ambiencePlayer.isPlaying { ambiencePlayer.play() }
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

        // The tone layer is its own source group: two players into a mixer,
        // then one shared filter. Rolling off above the fundamental's harmonics
        // keeps the cluster felt rather than heard as a pitch.
        toneFilter.bands[0].filterType = .lowPass
        toneFilter.bands[0].frequency = 220
        toneFilter.bands[0].bandwidth = 0.8
        toneFilter.bands[0].bypass = false
        tonePlayerA.volume = 0
        tonePlayerB.volume = 0

        engine.attach(ambiencePlayer)
        engine.attach(ambienceFilter)
        engine.attach(tonePlayerA)
        engine.attach(tonePlayerB)
        engine.attach(toneMixer)
        engine.attach(toneFilter)
        engine.attach(announcementPlayer)
        engine.attach(paFilter)
        engine.connect(ambiencePlayer, to: ambienceFilter, format: format)
        engine.connect(ambienceFilter, to: engine.mainMixerNode, format: format)
        engine.connect(tonePlayerA, to: toneMixer, format: format)
        engine.connect(tonePlayerB, to: toneMixer, format: format)
        engine.connect(toneMixer, to: toneFilter, format: format)
        engine.connect(toneFilter, to: engine.mainMixerNode, format: format)
        engine.connect(announcementPlayer, to: paFilter, format: format)
        engine.connect(paFilter, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.86
        ambienceBuffer = loop
        toneFormat = format
        graphBuilt = true
    }

    private func rampAmbience(to target: Float, duration: Double) {
        ramp(ambiencePlayer, to: target, duration: duration)
    }

    private func ramp(_ node: AVAudioPlayerNode, to target: Float, duration: Double) {
        let key = ObjectIdentifier(node)
        let generation = (rampGenerations[key] ?? 0) + 1
        rampGenerations[key] = generation
        let start = node.volume
        let steps = max(1, Int(duration * 30))
        for step in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration * Double(step) / Double(steps)) { [weak self] in
                guard let self, self.rampGenerations[key] == generation else { return }
                let x = Float(step) / Float(steps)
                let eased = x * x * (3 - 2 * x)
                node.volume = start + (target - start) * eased
            }
        }
    }

    // MARK: Engine tone layer

    /// Crossfades the tone layer to the phase's fundamental.
    ///
    /// When the fundamental is unchanged this is just a level move. When it
    /// changes, the incoming loop starts silent on the idle player and the two
    /// players trade level over the same window, so the layer never drops out
    /// and the swap is inaudible.
    private func setToneLayer(for profile: Profile, duration: Double) {
        let target = profile.toneVolume * duckFactor
        let fundamental = profile.toneFundamental

        guard SettingsStore.shared.ambienceEnabled, target > 0, fundamental > 0 else {
            toneBuildGeneration += 1 // Abandon any build still in flight.
            if let live = liveTonePlayer { ramp(live, to: 0, duration: duration) }
            liveToneFundamental = 0
            return
        }

        startEngineIfNeeded()
        guard graphBuilt else { return }

        if fundamental == liveToneFundamental, let live = liveTonePlayer {
            ramp(live, to: target, duration: duration)
            return
        }

        toneBuildGeneration += 1
        let generation = toneBuildGeneration
        loadToneBuffer(fundamental: fundamental) { [weak self] buffer in
            guard let self, self.toneBuildGeneration == generation, let buffer else { return }
            let outgoing = self.liveTonePlayer
            let incoming = (outgoing === self.tonePlayerA) ? self.tonePlayerB : self.tonePlayerA

            // Safe to stop: the incoming player is either idle or already faded
            // out, so nothing audible is cut.
            incoming.stop()
            incoming.volume = 0
            incoming.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
            incoming.play()

            self.liveTonePlayer = incoming
            self.liveToneFundamental = fundamental
            self.ramp(incoming, to: target, duration: duration)
            if let outgoing { self.ramp(outgoing, to: 0, duration: duration) }
        }
    }

    /// Builds the loop off the main thread. Generating one is a few hundred
    /// thousand `sin` evaluations, which is a visible hitch if it lands on the
    /// main queue during a phase transition. Arriving a moment late is
    /// inaudible under the noise bed.
    private func loadToneBuffer(fundamental: Double,
                                completion: @escaping (AVAudioPCMBuffer?) -> Void) {
        if let cached = toneBuffers[fundamental] {
            completion(cached)
            return
        }
        guard let format = toneFormat else {
            completion(nil)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let buffer = Self.makeToneLoop(fundamental: fundamental, format: format)
            DispatchQueue.main.async {
                guard let self else { return }
                if let buffer { self.toneBuffers[fundamental] = buffer }
                completion(buffer)
            }
        }
    }

    /// Loop length for the tone layer. Every partial is snapped to a whole
    /// number of cycles across this window, so the buffer meets itself exactly
    /// at the wrap and needs no crossfade to loop cleanly. Four seconds puts
    /// the frequency grid at 0.25 Hz, fine enough to place the detune beats.
    private static let toneLoopDuration = 4.0

    private static func makeToneLoop(fundamental: Double,
                                     format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let duration = toneLoopDuration
        let count = Int(format.sampleRate * duration)
        guard fundamental > 0, count > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(count)),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(count)

        // Partial multiples of the fundamental, each with a detune offset in Hz.
        // Two voices a fraction of a hertz apart beat against one another, and
        // that slow throb is what separates an engine from a test tone. The
        // offsets give beat periods of 2s on the fundamental and 1.3s on the
        // octave, which read as breathing rather than wobble.
        let partials: [(multiple: Double, detune: Double, gain: Double)] = [
            (1, 0, 1.00),
            (1, 0.50, 0.85),
            (2, 0, 0.34),
            (2, -0.75, 0.28),
            (3, 0.25, 0.10),
        ]

        let grid = 1.0 / duration
        var peak: Float = 0
        for i in 0..<count {
            let t = Double(i) / format.sampleRate
            var sample = 0.0
            for partial in partials {
                let cycles = ((fundamental * partial.multiple + partial.detune) / grid).rounded()
                guard cycles > 0 else { continue }
                sample += sin(2 * .pi * cycles * grid * t) * partial.gain
            }
            let value = Float(sample)
            samples[i] = value
            peak = max(peak, abs(value))
        }

        // Normalize to a peak of 1 so `toneVolume` is the only thing setting
        // level. Without this, changing the partial list would quietly change
        // how loud every phase is, and the takeoff profile is close enough to
        // the ceiling that it would clip.
        guard peak > 0 else { return nil }
        let scale = 1 / peak
        for i in 0..<count { samples[i] *= scale }
        return buffer
    }

    /// Every one-shot goes through here, and here does not touch the engine.
    ///
    /// The cue is rendered once to a file and played by System Sound Services,
    /// which builds no graph and never reads `outputNode` or `mainMixerNode`.
    /// Those two properties are a synchronous RPC to the audio server that
    /// `abort()`s the process on timeout, and a one-shot fired from a tap or a
    /// drag was the entry point in every crash report from 2026-09-08. See
    /// `SoundEffects` for the full reasoning and the prior art.
    ///
    /// `key` names the waveform: same key, same sound, because the second call
    /// replays the first call's file.
    private func play(_ key: String, duration: Double, build: (Int, Double, Double) -> Float) {
        SoundEffects.shared.play(key, duration: duration, build: build)
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
            // The 43 Hz and 86 Hz hum that used to be baked in here now lives in
            // the tone layer. Left in both places it would double up, and a
            // fixed pitch under a phase-keyed one beats against it.
            let breathe = 0.92 + Float(sin(2 * .pi * t / duration)) * 0.08
            samples[i] = (lower * 1.8 + low * 0.28) * breathe
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
    /// Names a printer cue by the line-feed schedule that shapes it, so two
    /// passes with different schedules do not share a rendered file.
    private static func digest(_ schedule: [Double]) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for gap in schedule {
            withUnsafeBytes(of: gap.bitPattern) { bytes in
                for byte in bytes {
                    hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
                }
            }
        }
        return String(hash, radix: 16)
    }

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
