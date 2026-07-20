import AVFoundation

/// Cabin-crew and flight-deck PA announcements. Speech is synthesized
/// offline, pushed through a cabin-speaker filter (band-passed, softly
/// saturated), and played through the audio engine — so it sounds like an
/// announcement over the PA system, not a phone assistant in your ear.
/// Every announcement is preceded by a cabin chime and ducks the ambience.
final class Announcer: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = Announcer()

    // AVSpeechSynthesizer is not Sendable; Announcer is a process-wide singleton
    // always messaged from the main actor / speech callbacks.
    private nonisolated(unsafe) let synthesizer = AVSpeechSynthesizer()
    /// Buffers collected from the current offline render.
    private nonisolated(unsafe) var pendingBuffers: [AVAudioPCMBuffer] = []
    private nonisolated(unsafe) var renderGeneration = 0

    /// Best installed English voice — premium > enhanced > default, with a
    /// preference for en-US and a flight-attendant-leaning female voice.
    /// The compact default voice sounds robotic; most devices ship at least
    /// one enhanced Siri-quality voice.
    private nonisolated(unsafe) lazy var paVoice: AVSpeechSynthesisVoice? = {
        let english = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }

        func score(_ voice: AVSpeechSynthesisVoice) -> Int {
            var s = 0
            switch voice.quality {
            case .premium: s += 40
            case .enhanced: s += 20
            default: break
            }
            if voice.language == "en-US" { s += 10 }
            if voice.gender == .female { s += 5 }
            // Novelty voices make terrible cabin crew.
            if voice.identifier.contains("speech.synthesis") { s -= 100 }
            return s
        }

        return english.max { score($0) < score($1) }
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }()

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    enum Script {
        case welcomeAboard(flightNumber: String, city: String, durationText: String)
        case midpoint(city: String, altitude: Int)
        case descent(city: String, weather: String)
        case landed(city: String, localTimeText: String)
        case layover(city: String, minutes: Int)
        case finalBoardingCall(city: String)

        var text: String {
            switch self {
            case let .welcomeAboard(flightNumber, city, durationText):
                return "Ladies and gentlemen, welcome aboard Voyage Air flight \(flightNumber), with service to \(city). Our flight time today is \(durationText). Please stow your distractions, and enjoy the flight."
            case let .midpoint(city, altitude):
                return "Folks, this is your captain. We're now about halfway to \(city), cruising at \(altitude.formatted()) feet. Smooth air ahead. Keep at it back there."
            case let .descent(city, weather):
                return "Cabin crew, prepare for arrival. We've begun our descent into \(city), where the weather is \(weather). Please finish up your final items."
            case let .landed(city, localTimeText):
                return "Welcome to \(city), where the local time is \(localTimeText). On behalf of Voyage Air, thank you for flying focused."
            case let .layover(city, minutes):
                return "Welcome to \(city). This is a connection stop. Your onward flight boards in \(minutes) minutes. Stretch your legs — you've earned it."
            case let .finalBoardingCall(city):
                return "Final boarding call for your connecting flight to \(city). All passengers, please proceed to the gate immediately."
            }
        }
    }

    func announce(_ script: Script, premiumChime: Bool = false) {
        guard SettingsStore.shared.announcementsEnabled else { return }
        CabinAudioEngine.shared.playChime(premium: premiumChime)
        CabinAudioEngine.shared.setDucked(true)

        let utterance = AVSpeechUtterance(string: script.text)
        utterance.rate = 0.5
        utterance.pitchMultiplier = 0.98
        if let voice = paVoice {
            utterance.voice = voice
        }

        renderGeneration += 1
        let generation = renderGeneration
        pendingBuffers = []

        synthesizer.write(utterance) { [weak self] buffer in
            guard let self, self.renderGeneration == generation else { return }
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            if pcm.frameLength == 0 {
                // Render complete: filter and hand off, after the chime rings.
                let processed = Self.cabinFilter(self.pendingBuffers)
                self.pendingBuffers = []
                guard !processed.isEmpty else {
                    CabinAudioEngine.shared.setDucked(false)
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    guard self.renderGeneration == generation else { return }
                    CabinAudioEngine.shared.playPA(buffers: processed) {
                        CabinAudioEngine.shared.setDucked(false)
                    }
                }
            } else if let copy = Self.floatCopy(of: pcm) {
                self.pendingBuffers.append(copy)
            }
        }
    }

    func stop() {
        renderGeneration += 1
        pendingBuffers = []
        synthesizer.stopSpeaking(at: .immediate)
        CabinAudioEngine.shared.stopPA()
        CabinAudioEngine.shared.setDucked(false)
    }

    // MARK: - Cabin-speaker processing

    /// The synth's buffers are only valid inside the callback and may be
    /// int16 — copy into standalone float32 buffers.
    private static func floatCopy(of pcm: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let frames = pcm.frameLength
        guard frames > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: pcm.format.sampleRate, channels: 1),
              let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let out = copy.floatChannelData?[0] else { return nil }
        copy.frameLength = frames

        if let source = pcm.floatChannelData?[0] {
            for i in 0..<Int(frames) { out[i] = source[i] }
        } else if let source = pcm.int16ChannelData?[0] {
            for i in 0..<Int(frames) { out[i] = Float(source[i]) / 32768.0 }
        } else {
            return nil
        }
        return copy
    }

    /// Small-speaker PA: band-pass roughly 250–3200 Hz, a touch of soft
    /// saturation, filter state carried across buffers so there are no seams.
    private static func cabinFilter(_ buffers: [AVAudioPCMBuffer]) -> [AVAudioPCMBuffer] {
        guard let first = buffers.first else { return [] }
        let sr = Float(first.format.sampleRate)
        // One-pole coefficients.
        let hpAlpha = 1 / (1 + 2 * Float.pi * 250 / sr)
        let lpAlpha = (2 * Float.pi * 3200 / sr) / (1 + 2 * Float.pi * 3200 / sr)

        var hpPrevIn: Float = 0
        var hpPrevOut: Float = 0
        var lpState: Float = 0

        for buffer in buffers {
            guard let data = buffer.floatChannelData?[0] else { continue }
            for i in 0..<Int(buffer.frameLength) {
                let x = data[i]
                // High-pass strips the boomy lows.
                let hp = hpAlpha * (hpPrevOut + x - hpPrevIn)
                hpPrevIn = x
                hpPrevOut = hp
                // Low-pass rolls off the crisp synth top end.
                lpState += lpAlpha * (hp - lpState)
                // Soft saturation: a small speaker driven a little too hard.
                data[i] = tanhf(lpState * 2.4) * 0.85
            }
        }
        return buffers
    }

    // MARK: - AVSpeechSynthesizerDelegate (spoken fallback path)

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        CabinAudioEngine.shared.setDucked(false)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        CabinAudioEngine.shared.setDucked(false)
    }
}
