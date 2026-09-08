import XCTest
@testable import Voyage

/// Unit tests for the WS5 engine-tone layer. Everything here runs on the DSP
/// value types directly, so no audio hardware, no `AVAudioEngine`, and no real
/// time is involved: `EngineTone.nextSample()` is the same code the render
/// thread runs, driven a sample at a time from the test.
final class EngineToneTests: XCTestCase {

    private let sampleRate: Double = 48_000

    /// The largest legitimate sample-to-sample step this layer can produce:
    /// the slope of its fastest partial at full amplitude, with room to spare.
    /// A pop would be a step of roughly the signal amplitude (~0.08), forty
    /// times this, so the threshold separates the two cleanly.
    private let maxContinuousDelta: Float = 0.002

    private func makeTone() -> EngineTone {
        let tone = EngineTone()
        tone.setSampleRate(sampleRate)
        return tone
    }

    /// Renders `seconds` of audio in 512-frame buffers, the way the render
    /// callback does, optionally running `midway` at the halfway point.
    @discardableResult
    private func render(_ tone: EngineTone,
                        seconds: Double,
                        midway: (() -> Void)? = nil) -> [Float] {
        let total = Int(seconds * sampleRate)
        var out: [Float] = []
        out.reserveCapacity(total)
        var fired = false
        var frame = 0
        while frame < total {
            if let midway, !fired, frame >= total / 2 {
                midway()
                fired = true
            }
            tone.beginBuffer()
            for _ in 0..<min(512, total - frame) {
                out.append(tone.nextSample())
            }
            frame += 512
        }
        return out
    }

    private func peak(_ samples: [Float]) -> Float {
        samples.reduce(0) { max($0, abs($1)) }
    }

    private func maxDelta(_ samples: [Float]) -> Float {
        guard samples.count > 1 else { return 0 }
        var worst: Float = 0
        for i in 1..<samples.count {
            worst = max(worst, abs(samples[i] - samples[i - 1]))
        }
        return worst
    }

    // MARK: - Cluster shape

    func testPartialWeightsSumToOne() {
        let w = EngineTone.weights
        // This is the whole no-clipping argument: weights summing to 1 bound a
        // cluster's peak by its own gain.
        XCTAssertEqual(w.0 + w.1 + w.2 + w.3, 1.0, accuracy: 1e-6)
    }

    func testDetuneRatiosAreDistinctSoThePartialsBeat() {
        let d = EngineTone.detune
        let ratios = [d.0, d.1, d.2, d.3]
        XCTAssertEqual(Set(ratios).count, 4)
        // The two neighbours must be close enough to beat slowly rather than
        // read as separate pitches.
        XCTAssertLessThan(abs(d.1 - 1), 0.02)
        XCTAssertLessThan(abs(d.2 - 1), 0.02)
    }

    func testClusterPeakNeverExceedsItsGain() {
        var cluster = EngineTone.Cluster()
        cluster.fundamental = 112
        cluster.gain = 0.08
        let inverse = Float(1 / sampleRate)
        var worst: Float = 0
        for _ in 0..<Int(sampleRate * 4) {
            worst = max(worst, abs(cluster.nextSample(inverseSampleRate: inverse)))
        }
        XCTAssertLessThanOrEqual(worst, 0.08 + 1e-6)
        // ...and it should actually get close, or the cluster is inaudibly quiet.
        XCTAssertGreaterThan(worst, 0.05)
    }

    func testEveryProfileStaysInsideTheHeadroomBudget() {
        let profiles: [CabinAudioEngine.Profile] = [
            .silent, .boarding, .taxi, .takeoffRoll, .climb, .cruise, .descent, .landingRoll
        ]
        for profile in profiles {
            XCTAssertLessThanOrEqual(profile.toneGain, EngineTone.peakGain,
                                     "\(profile) exceeds the engine-tone headroom budget")
            XCTAssertGreaterThanOrEqual(profile.toneGain, 0)
            // Low register only: the tone is the rumble, not the turbine whine.
            XCTAssertLessThanOrEqual(profile.toneFundamental, 130)
        }
        XCTAssertEqual(CabinAudioEngine.Profile.silent.toneGain, 0)
        XCTAssertEqual(CabinAudioEngine.Profile.silent.toneFundamental, 0)
    }

    // MARK: - Acceptance: no clipping at max volume

    func testLoudestProfileDoesNotClip() {
        let tone = makeTone()
        tone.setProfile(.landingRoll)
        tone.setEnabled(true)
        let samples = render(tone, seconds: 4)
        XCTAssertLessThanOrEqual(peak(samples), EngineTone.peakGain + 1e-6)
        XCTAssertLessThan(peak(samples), 1)
        XCTAssertGreaterThan(peak(samples), 0.04, "the layer should be audible, not a whisper")
    }

    func testCrossfadeBetweenTheTwoLoudestProfilesDoesNotClip() {
        let tone = makeTone()
        tone.setProfile(.takeoffRoll)
        tone.setEnabled(true)
        let samples = render(tone, seconds: 8) { tone.setProfile(.landingRoll) }
        // Linear balance, so the mix can never exceed the louder of the two.
        XCTAssertLessThanOrEqual(peak(samples), EngineTone.peakGain + 1e-6)
    }

    // MARK: - Acceptance: nothing pops

    func testPhaseChangeCrossfadesWithoutAStep() {
        let tone = makeTone()
        tone.setProfile(.cruise)
        tone.setEnabled(true)
        let samples = render(tone, seconds: 8) { tone.setProfile(.descent) }
        XCTAssertLessThan(maxDelta(samples), maxContinuousDelta)
    }

    func testTogglingSoundOffMidPhaseDoesNotPop() {
        let tone = makeTone()
        tone.setProfile(.climb)
        tone.setEnabled(true)
        let samples = render(tone, seconds: 4) { tone.setEnabled(false) }
        XCTAssertLessThan(maxDelta(samples), maxContinuousDelta)
        // And it must actually land on silence, not just get quiet.
        XCTAssertEqual(samples.suffix(1_000).reduce(0) { max($0, abs($1)) }, 0)
    }

    func testTogglingSoundOnMidPhaseDoesNotPop() {
        let tone = makeTone()
        tone.setProfile(.cruise)
        let samples = render(tone, seconds: 4) { tone.setEnabled(true) }
        XCTAssertLessThan(maxDelta(samples), maxContinuousDelta)
        XCTAssertEqual(peak(Array(samples.prefix(sampleIndex(0.5)))), 0)
        XCTAssertGreaterThan(peak(Array(samples.suffix(sampleIndex(0.5)))), 0.01)
    }

    func testDuckingMidPhaseDoesNotPop() {
        let tone = makeTone()
        tone.setProfile(.cruise)
        tone.setEnabled(true)
        let samples = render(tone, seconds: 4) { tone.setDucked(true) }
        XCTAssertLessThan(maxDelta(samples), maxContinuousDelta)
        let ducked = peak(Array(samples.suffix(sampleIndex(0.5))))
        let open = peak(Array(samples[sampleIndex(0.5)..<sampleIndex(1.5)]))
        XCTAssertLessThan(ducked, open)
    }

    func testAPhaseChangeArrivingMidCrossfadeIsDeferredAndStillLands() {
        let tone = makeTone()
        tone.setProfile(.boarding)
        tone.setEnabled(true)
        var samples = render(tone, seconds: 2)

        // .taxi starts a two-second fade...
        tone.setProfile(.taxi)
        samples += render(tone, seconds: 1)
        // ...and .takeoffRoll lands one second into it, so it has to wait its
        // turn rather than retuning a slot that is currently audible.
        tone.setProfile(.takeoffRoll)
        samples += render(tone, seconds: 12)

        XCTAssertLessThan(maxDelta(samples), maxContinuousDelta)
        // Once both fades have run the layer should sit at takeoff level.
        let settled = peak(Array(samples.suffix(sampleIndex(2))))
        XCTAssertEqual(settled, CabinAudioEngine.Profile.takeoffRoll.toneGain, accuracy: 0.015)
    }

    func testDisabledToneIsExactlySilent() {
        let tone = makeTone()
        tone.setProfile(.takeoffRoll)
        tone.setEnabled(false)
        let samples = render(tone, seconds: 2)
        XCTAssertEqual(peak(samples), 0)
    }

    // MARK: - ParameterRamp

    func testRampLandsExactlyOnItsGoal() {
        var ramp = ParameterRamp(0)
        ramp.start(to: 1, samples: 5_000)
        for _ in 0..<5_000 { _ = ramp.getAndStep() }
        XCTAssertFalse(ramp.isRamping)
        XCTAssertEqual(ramp.getAndStep(), 1)
    }

    func testRampIsMonotonicAndSmall_stepped() {
        var ramp = ParameterRamp(0)
        ramp.start(to: 1, samples: 1_000)
        var previous: Float = 0
        for _ in 0..<1_000 {
            let value = ramp.getAndStep()
            XCTAssertGreaterThanOrEqual(value, previous)
            XCTAssertLessThanOrEqual(value - previous, 0.002)
            previous = value
        }
    }

    func testRetargetingMidRampStartsFromTheLiveValue() {
        var ramp = ParameterRamp(0)
        ramp.start(to: 1, samples: 1_000)
        for _ in 0..<500 { _ = ramp.getAndStep() }
        let midpoint = ramp.value
        XCTAssertEqual(midpoint, 0.5, accuracy: 0.01)
        ramp.start(to: 0, samples: 1_000)
        // No jump at the retarget: the new ramp begins where the old one was.
        XCTAssertEqual(ramp.value, midpoint, accuracy: 1e-5)
    }

    func testZeroLengthRampIsImmediate() {
        var ramp = ParameterRamp(0.25)
        ramp.start(to: 0.75, samples: 0)
        XCTAssertEqual(ramp.value, 0.75)
        XCTAssertFalse(ramp.isRamping)
    }

    private func sampleIndex(_ seconds: Double) -> Int { Int(seconds * sampleRate) }
}
