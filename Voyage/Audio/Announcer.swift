import AVFoundation

/// Cabin-crew and flight-deck PA announcements via speech synthesis.
/// Every announcement is preceded by a cabin chime and ducks the ambience bed.
final class Announcer: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = Announcer()

    private let synthesizer = AVSpeechSynthesizer()

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
        utterance.preUtteranceDelay = 1.1   // let the chime ring first
        utterance.rate = 0.48
        utterance.pitchMultiplier = 0.92
        utterance.volume = 0.9
        if let voice = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = voice
        }
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        CabinAudioEngine.shared.setDucked(false)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        CabinAudioEngine.shared.setDucked(false)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        CabinAudioEngine.shared.setDucked(false)
    }
}
