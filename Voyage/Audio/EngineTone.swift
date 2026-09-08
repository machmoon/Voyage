import Foundation

/// A linear parameter ramp evaluated once per sample, so a value change
/// glides instead of stepping (a step is audible as a click, "zipper noise").
///
/// This is a direct port of AudioKitEX's `ParameterRamper`
/// (`Sources/CAudioKitEX/include/ParameterRamper.h` in AudioKit/AudioKitEX).
/// The important detail borrowed from there: the render thread evaluates the
/// straight line `inverseSlope * samplesRemaining + goal` rather than
/// accumulating an increment, so a multi-second ramp lands exactly on the
/// goal instead of drifting short of it. `getAndStep()` is their combined
/// read-and-advance, which skips the multiply-add while not ramping.
struct ParameterRamp {
    private(set) var goal: Float
    private var inverseSlope: Float = 0
    private var samplesRemaining: Int = 0

    init(_ value: Float = 0) { goal = value }

    var isRamping: Bool { samplesRemaining > 0 }

    var value: Float {
        samplesRemaining > 0 ? inverseSlope * Float(samplesRemaining) + goal : goal
    }

    /// Jump straight to `value`. Only safe where the jump is inaudible.
    mutating func setImmediate(_ value: Float) {
        goal = value
        inverseSlope = 0
        samplesRemaining = 0
    }

    /// Start a new ramp from wherever the ramp currently sits. Retargeting
    /// mid-ramp is fine: the slope is measured from the live value, not from
    /// the previous ramp's origin.
    mutating func start(to newGoal: Float, samples: Int) {
        guard samples > 0 else { setImmediate(newGoal); return }
        inverseSlope = (value - newGoal) / Float(samples)
        samplesRemaining = samples
        goal = newGoal
    }

    mutating func getAndStep() -> Float {
        guard samplesRemaining > 0 else { return goal }
        let current = value
        samplesRemaining -= 1
        return current
    }
}

/// The engine-tone layer of the cabin bed: a low cluster of slightly detuned
/// sines that sits underneath `CabinAudioEngine`'s filtered noise and is keyed
/// to the flight phase. Noise alone reads as wind; the tone is what makes it
/// read as engines.
///
/// Two structural choices come from AudioKit:
///
/// - The crossfade is a per-sample linear balance `(1 - b) * A + b * B`, with
///   `b` stepped by a `ParameterRamp`. That is exactly `DryWetMixerDSP::process`
///   in `Sources/CAudioKitEX/Nodes/DryWetMixerDSP.mm` (AudioKit/AudioKitEX).
///   Linear balance is also what bounds the output: if each cluster's peak is
///   at most its own gain, the mix is at most `max(gainA, gainB)`, so a
///   crossfade cannot push the layer into clipping.
/// - Each partial keeps its own phase accumulator, advanced and wrapped into
///   `0..<2pi` per sample and never reset, as in AudioKit's
///   `Sources/AudioKit/Nodes/Generators/PlaygroundOscillator.swift`. Phases are
///   never reset here either, which is half of why nothing pops; the other half
///   is that a cluster is only ever retuned while its mix weight is exactly 0.
///
/// Threading follows the convention already in `CabinAudioEngine`: request
/// fields are written from the main thread and read by the render thread, and
/// every one of them reaches the output through a ramp, so a torn read is at
/// worst one buffer of staleness rather than an artifact.
final class EngineTone {

    // MARK: Cluster shape

    /// Partial ratios: the fundamental, two neighbours detuned far enough to
    /// beat slowly against it (the way two engines at slightly different N1 do),
    /// and a weak octave for body.
    static let detune: (Float, Float, Float, Float) = (1.0, 1.006, 0.9935, 2.01)

    /// Partial weights. These sum to exactly 1, which is what lets a cluster's
    /// peak be bounded by its own gain.
    static let weights: (Float, Float, Float, Float) = (0.42, 0.24, 0.20, 0.14)

    /// Length of a phase-change crossfade. Long enough that a thrust change
    /// reads as a thrust change rather than an edit.
    static let crossfadeSeconds: Double = 2.0

    /// Length of the enable/disable and duck ramp.
    static let gainRampSeconds: Double = 0.35

    /// The loudest any profile drives the layer. The mix cannot exceed this,
    /// which is the headroom budget the noise bed is allowed to assume.
    static let peakGain: Float = 0.08

    /// One detuned sine cluster. Phases are only advanced, never reset.
    struct Cluster {
        var fundamental: Float = 0
        var gain: Float = 0
        var phase0: Float = 0
        var phase1: Float = 0
        var phase2: Float = 0
        var phase3: Float = 0

        private static let twoPi = 2 * Float.pi

        private static func wrap(_ phase: Float) -> Float {
            var p = phase
            if p >= twoPi { p -= twoPi }
            if p < 0 { p += twoPi }
            return p
        }

        /// Render one sample and advance every partial. `|result| <= gain`,
        /// because the weights sum to 1 and each sine is bounded by 1.
        mutating func nextSample(inverseSampleRate: Float) -> Float {
            let w = EngineTone.weights
            let d = EngineTone.detune
            let sample = sinf(phase0) * w.0
                + sinf(phase1) * w.1
                + sinf(phase2) * w.2
                + sinf(phase3) * w.3

            let step = Cluster.twoPi * fundamental * inverseSampleRate
            phase0 = Cluster.wrap(phase0 + step * d.0)
            phase1 = Cluster.wrap(phase1 + step * d.1)
            phase2 = Cluster.wrap(phase2 + step * d.2)
            phase3 = Cluster.wrap(phase3 + step * d.3)

            return sample * gain
        }
    }

    // MARK: State

    /// Render-thread state.
    private var front = Cluster()
    private var back = Cluster()
    /// 0 = front only, 1 = back only.
    private var balance = ParameterRamp(0)
    /// Enable/disable and ducking, folded into one ramp.
    private var master = ParameterRamp(0)
    private var appliedRequest: Int = 0
    private var inverseSampleRate: Float = 1.0 / 44_100

    /// Written from the main thread.
    private var requestedFundamental: Float = 0
    private var requestedGain: Float = 0
    private var requestCounter: Int = 0
    private var enabled = false
    private var ducked = false
    private var sampleRate: Double = 44_100

    /// A phase change queued while a crossfade was still running. Only one is
    /// kept; phase changes are seconds apart and the fade is two seconds long,
    /// so the queue never needs to be deeper than that.
    private var deferredRequest: Int?

    // MARK: Main-thread control

    func setSampleRate(_ rate: Double) {
        guard rate > 0 else { return }
        sampleRate = rate
        inverseSampleRate = Float(1.0 / rate)
    }

    /// Key the tone to a flight phase. Takes effect as a crossfade.
    func setProfile(_ profile: CabinAudioEngine.Profile) {
        requestedFundamental = profile.toneFundamental
        requestedGain = profile.toneGain
        requestCounter &+= 1
    }

    /// Fade the layer in or out. Ramped, so it is safe to call mid-phase.
    func setEnabled(_ on: Bool) { enabled = on }

    /// Pull the layer down while the PA speaks.
    func setDucked(_ on: Bool) { ducked = on }

    // MARK: Render thread

    /// Pick up main-thread requests. Call once per buffer, before the sample
    /// loop, the way AudioKitEX's `dezipperCheck` runs ahead of `process`.
    func beginBuffer() {
        let snapshot = requestCounter
        if snapshot != appliedRequest {
            appliedRequest = snapshot
            deferredRequest = snapshot
        }
        applyDeferredRequestIfIdle()

        let goal: Float = enabled ? (ducked ? 0.35 : 1.0) : 0
        if goal != master.goal {
            master.start(to: goal, samples: Int(Self.gainRampSeconds * sampleRate))
        }
    }

    /// A slot may only be retuned while its mix weight is exactly 0, otherwise
    /// the retune is a step change in an audible signal. So a request that
    /// lands mid-crossfade waits for the fade to finish.
    private func applyDeferredRequestIfIdle() {
        guard deferredRequest != nil else { return }
        guard !balance.isRamping, balance.value == 0 else { return }
        deferredRequest = nil

        // Nothing audible yet: retune the front slot directly rather than
        // burning a two-second fade up from silence.
        if front.gain == 0 || (master.value == 0 && !master.isRamping) {
            front.fundamental = requestedFundamental
            front.gain = requestedGain
            return
        }
        guard requestedFundamental != front.fundamental || requestedGain != front.gain else { return }

        back.fundamental = requestedFundamental
        back.gain = requestedGain
        balance.start(to: 1, samples: Int(Self.crossfadeSeconds * sampleRate))
    }

    /// Render one sample of the layer. Render thread only.
    func nextSample() -> Float {
        var b = balance.getAndStep()
        if b >= 1 && !balance.isRamping {
            // The fade is over and the back slot is the entire output, so
            // adopting it wholesale (phases included) is bit-identical. This
            // frees the back slot for the next phase change.
            front = back
            balance.setImmediate(0)
            b = 0
        }

        var sample: Float = 0
        if b < 1 {
            sample += (1 - b) * front.nextSample(inverseSampleRate: inverseSampleRate)
        }
        if b > 0 {
            // While b is 0 the back slot is inaudible, so leaving its phases
            // parked costs nothing and saves four sines per sample in the
            // steady state.
            sample += b * back.nextSample(inverseSampleRate: inverseSampleRate)
        }
        return sample * master.getAndStep()
    }
}

extension CabinAudioEngine.Profile {

    /// Fundamental of the engine-tone cluster, in Hz. Low: the blade-passing
    /// register you feel through the seat, not the turbine whine.
    var toneFundamental: Float {
        switch self {
        case .silent: return 0
        case .boarding: return 78      // APU only
        case .taxi: return 84
        case .takeoffRoll: return 108
        case .climb: return 100
        case .cruise: return 92
        case .descent: return 88
        case .landingRoll: return 112  // reversers
        }
    }

    /// Peak amplitude of the engine-tone cluster. Sits under the noise bed's
    /// gain at every phase; the maximum is `EngineTone.peakGain`.
    var toneGain: Float {
        switch self {
        case .silent: return 0
        case .boarding: return 0.020
        case .taxi: return 0.030
        case .takeoffRoll: return 0.075
        case .climb: return 0.055
        case .cruise: return 0.038
        case .descent: return 0.042
        case .landingRoll: return 0.080
        }
    }
}
