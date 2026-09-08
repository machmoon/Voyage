import AVFoundation

/// The bundled studio voices, rendered by `Scripts/generate_pa_audio.py`.
///
/// Raw values persist in `SettingsStore.paVoiceIdentifier`, where they sit
/// alongside `AVSpeechSynthesisVoice` identifiers, so the prefix keeps the two
/// namespaces apart.
enum PAVoice: String, CaseIterable, Identifiable {
    case crew = "studio.crew"
    case captain = "studio.captain"

    static let `default` = PAVoice.crew

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .crew: return "Cabin Crew"
        case .captain: return "Captain"
        }
    }

    var subtitle: String {
        switch self {
        case .crew: return "Warm, reassuring"
        case .captain: return "Low, measured"
        }
    }

    /// Filename prefix. Clips are flat in the bundle because Xcode collapses
    /// resource directories into the bundle root.
    fileprivate var prefix: String {
        switch self {
        case .crew: return "crew"
        case .captain: return "captain"
        }
    }
}

/// Short spoken check-ins.
///
/// Every line ships as a pre-rendered clip, so the cabin voice stays studio
/// quality, plays in airplane mode, costs nothing at runtime, and never sends a
/// word of a focus session to a server. On-device speech remains the fallback
/// for a missing clip or a user who prefers a system voice.
final class Announcer: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = Announcer()

    // The singleton is used from the main actor and AVSpeechSynthesizer's own
    // delegate callbacks. AVSpeechSynthesizer is not Sendable.
    private nonisolated(unsafe) let synthesizer = AVSpeechSynthesizer()

    /// The studio voice to use, or `nil` when the user picked a system voice.
    private nonisolated var studioVoice: PAVoice? {
        guard let identifier = SettingsStore.shared.paVoiceIdentifier else { return .default }
        return PAVoice(rawValue: identifier)
    }

    private nonisolated var voice: AVSpeechSynthesisVoice? {
        if let identifier = SettingsStore.shared.paVoiceIdentifier,
           let selected = AVSpeechSynthesisVoice(identifier: identifier),
           !Self.isNoveltyVoice(selected) {
            return selected
        }
        return Self.bestInstalledVoice()
    }

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    enum Script {
        case welcomeAboard
        case midpoint(city: String)
        case descent(city: String)
        case landed(city: String)
        case layover(city: String)
        case finalBoardingCall(city: String)
        case beverageService

        /// Spoken wording carries no numbers. Durations and countdowns are
        /// already on screen and in the Live Activity, and leaving them out is
        /// what lets one fixed set of clips cover every flight.
        var text: String {
            switch self {
            case .welcomeAboard:
                return "Welcome aboard. The cabin doors are closed and focus mode is now on. Sit back, and enjoy your flight."
            case let .midpoint(city):
                return "We're halfway to \(city)."
            case let .descent(city):
                return "Beginning our descent into \(city). Time to wrap up."
            case let .landed(city):
                return "Welcome to \(city). Session complete."
            case let .layover(city):
                return "Welcome to \(city). Your connection boards shortly."
            case let .finalBoardingCall(city):
                return "Final boarding call for your connecting flight to \(city)."
            case .beverageService:
                return "The beverage cart is coming through. Take a moment for some water."
            }
        }

        /// The same wording marked up for delivery. A cabin PA breathes: a beat
        /// after the address, a longer one before the part you are meant to act
        /// on. No rate setting expresses that, so the pauses are written in.
        /// Only reached when no studio clip is bundled for the script.
        var ssml: String {
            func esc(_ value: String) -> String {
                value.replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "<", with: "&lt;")
                    .replacingOccurrences(of: ">", with: "&gt;")
            }
            let body: String
            switch self {
            case .welcomeAboard:
                body = """
                Welcome aboard. <break time="400ms"/> The cabin doors are closed \
                and focus mode is now on. <break time="500ms"/> \
                <prosody rate="95%">Sit back, <break time="250ms"/> \
                and enjoy your flight.</prosody>
                """
            case let .midpoint(city):
                body = "We're halfway to \(esc(city))."
            case let .descent(city):
                body = """
                Beginning our descent into \(esc(city)). <break time="450ms"/> \
                <emphasis level="moderate">Time to wrap up.</emphasis>
                """
            case let .landed(city):
                body = """
                Welcome to \(esc(city)). <break time="400ms"/> Session complete.
                """
            case let .layover(city):
                body = """
                Welcome to \(esc(city)). <break time="400ms"/> \
                Your connection boards shortly.
                """
            case let .finalBoardingCall(city):
                body = """
                <emphasis level="strong">Final boarding call</emphasis> \
                for your connecting flight to \(esc(city)).
                """
            case .beverageService:
                body = """
                The beverage cart is coming through. <break time="450ms"/> \
                Take a moment for some water.
                """
            }
            return "<speak>\(body)</speak>"
        }

        /// Bundled clip name, without the voice prefix or extension.
        var clip: String {
            switch self {
            case .welcomeAboard: return "welcome"
            case .beverageService: return "beverage"
            case let .midpoint(city): return "midpoint_\(Announcer.slug(city))"
            case let .descent(city): return "descent_\(Announcer.slug(city))"
            case let .landed(city): return "landed_\(Announcer.slug(city))"
            case let .layover(city): return "layover_\(Announcer.slug(city))"
            case let .finalBoardingCall(city): return "finalcall_\(Announcer.slug(city))"
            }
        }
    }

    func announce(_ script: Script, premiumChime: Bool = false) {
        guard SettingsStore.shared.announcementsEnabled else { return }

        // A newer state update is more useful than a queue of stale prompts.
        stop()

        CabinAudioEngine.shared.playChime(premium: premiumChime)
        play(script)
    }

    func previewSelectedVoice() {
        stop()
        let preview = "Welcome aboard. This is your cabin crew. Your focus time is yours."
        if let voice = studioVoice, playClip(named: "preview", voice: voice) { return }
        speak(preview)
    }

    /// Studio clip when one exists, on-device speech otherwise.
    private func play(_ script: Script) {
        if let voice = studioVoice, playClip(named: script.clip, voice: voice) { return }
        speak(script.text, ssml: script.ssml)
    }

    private func playClip(named clip: String, voice: PAVoice) -> Bool {
        guard let url = Bundle.main.url(forResource: "\(voice.prefix)_\(clip)",
                                        withExtension: "m4a") else { return false }
        return CabinAudioEngine.shared.playAnnouncement(url: url) {}
    }

    /// `ssml` carries the pauses. An older parser or a malformed body falls back
    /// to the plain wording rather than going silent.
    private func speak(_ text: String, ssml: String? = nil) {
        let utterance = ssml.flatMap { AVSpeechUtterance(ssmlRepresentation: $0) }
            ?? AVSpeechUtterance(string: text)
        utterance.voice = voice
        // Cabin announcements are unhurried — a PA that races sounds like a
        // notification, not a crew member.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.80
        utterance.pitchMultiplier = 0.98
        utterance.volume = 0.82
        utterance.preUtteranceDelay = 0.12
        utterance.postUtteranceDelay = 0.08
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        CabinAudioEngine.shared.stopPA()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        CabinAudioEngine.shared.setDucked(true)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        CabinAudioEngine.shared.setDucked(false)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        CabinAudioEngine.shared.setDucked(false)
    }

    // MARK: - Clip naming

    /// Mirror of `slug()` in Scripts/generate_pa_audio.py — keep both in step.
    /// City names carry en dashes and spaces that cannot appear in a filename.
    nonisolated static func slug(_ city: String) -> String {
        var slug = ""
        var pendingSeparator = false
        for character in city.lowercased() {
            if character.isASCII, character.isLetter || character.isNumber {
                if pendingSeparator, !slug.isEmpty { slug.append("-") }
                pendingSeparator = false
                slug.append(character)
            } else {
                pendingSeparator = true
            }
        }
        return slug
    }

    // MARK: - Voice selection

    nonisolated static func isSiriVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
        let identifier = voice.identifier.lowercased()
        return identifier.contains("ttsbundle.siri")
            || identifier.contains("voice.custom.siri")
            || identifier.contains("siri_female")
            || identifier.contains("siri_male")
            || identifier.contains(".siri.")
            || voice.name.lowercased().contains("siri")
    }

    nonisolated static func isNoveltyVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
        let identifier = voice.identifier.lowercased()
        return identifier.contains("speech.synthesis")
            || identifier.contains("eloquence")
    }

    nonisolated static func isHighFidelityVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
        voice.quality == .premium || voice.quality == .enhanced
    }

    nonisolated static func voiceScore(_ voice: AVSpeechSynthesisVoice) -> Int {
        guard !isNoveltyVoice(voice) else { return .min }

        var score = 0
        switch voice.quality {
        case .premium: score += 300
        case .enhanced: score += 200
        // `.default` is the compact voice the system ships with. It reads like
        // a satnav, so it loses to anything the user has downloaded.
        default: score -= 30
        }
        if voice.language == "en-US" { score += 50 }
        else if voice.language.hasPrefix("en") { score += 20 }

        let identifier = voice.identifier.lowercased()
        if identifier.contains("super-compact") { score -= 120 }
        else if identifier.contains("compact") { score -= 70 }
        return score
    }

    nonisolated static func rankedEnglishVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") && !isNoveltyVoice($0) }
            .sorted { voiceScore($0) > voiceScore($1) }
    }

    nonisolated static func bestInstalledVoice() -> AVSpeechSynthesisVoice? {
        let ranked = rankedEnglishVoices()
        if let highQualityUS = ranked.first(where: {
            $0.language == "en-US" && isHighFidelityVoice($0)
        }) {
            return highQualityUS
        }
        if let systemUS = AVSpeechSynthesisVoice(language: "en-US"),
           !isNoveltyVoice(systemUS) {
            return systemUS
        }
        return ranked.first
    }
}
