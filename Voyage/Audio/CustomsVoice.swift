import AVFoundation
import Speech
import os

// The customs officer's voice and ears. Speech recognition runs on this
// iPhone only (`requiresOnDeviceRecognition`); a device that cannot do that
// gets the keyboard rather than a server.
//
// The listening loop follows two open-source implementations:
// - Point-Free's SpeechRecognition example (pointfreeco/
//   swift-composable-architecture, Examples/SpeechRecognition/
//   SpeechRecognition/SpeechClient/Live.swift at 5e4baf5, MIT), which is
//   Apple's "Recognizing speech in live audio" (SpokenWord) sample in async
//   form: a `.record`/`.measurement` session, one `AVAudioEngine`, a
//   1024-frame tap on the input node feeding an
//   `SFSpeechAudioBufferRecognitionRequest` with partial results, and on
//   termination engine stop, `removeTap(onBus: 0)`, task finish.
// - Vocable (willowtreeapps/vocable-ios, Vocable/Features/Voice/
//   SpeechRecognitionController.swift at 526d520, MIT) for ending an
//   utterance on silence: a timer restarted on every hypothesis, and on
//   timeout `endAudio()` then `finish()`. Vocable waits 1.2 s; customs waits
//   2 s, because a recall answer has thinking pauses a command does not.
//
// Deviations, each for a stated reason: the session is `.playAndRecord`
// with `.defaultToSpeaker` rather than `.record`, because the officer speaks
// between answers and `.record` silences playback; and a recogniser error
// with nothing heard is an empty answer rather than a failure, since "no
// speech detected" is the common case of a traveler who said nothing.

// MARK: - Seam

/// Microphone plus speech recognition, as one answer.
enum VoiceAccess: Equatable {
    case granted
    case notDetermined
    case denied
    /// This device cannot recognise speech on device for this language.
    case unsupported
}

enum CustomsVoiceError: Error, Equatable {
    case unavailable
    case audioEngine
}

/// Everything the interview needs from audio. Production has one conformer,
/// `LiveCustomsVoice`; tests use a scripted fake and never open a microphone.
@MainActor
protocol CustomsVoiceIO: AnyObject {
    var access: VoiceAccess { get }
    func requestAccess() async -> VoiceAccess
    /// Returns when the line has been spoken or `stopSpeaking()` cut it off.
    func speak(_ text: String) async
    /// Listens until the traveler goes quiet, then returns what was heard
    /// ("" for nothing). `hints` are words likely to be said.
    func listen(hints: [String], onPartial: @escaping @MainActor (String) -> Void) async throws -> String
    /// Ends a `listen` early; it returns what it heard so far.
    func stopListening()
    func stopSpeaking()
    /// Releases the microphone and hands audio back to the cabin.
    func end()
}

// MARK: - Live

@MainActor
final class LiveCustomsVoice: NSObject, CustomsVoiceIO, AVSpeechSynthesizerDelegate {
    /// Quiet after the last word that ends an answer.
    static let silenceTimeout: Duration = .seconds(2)
    /// Quiet before the first word, after which the answer is "nothing".
    static let openingTimeout: Duration = .seconds(8)
    /// No answer runs longer than this.
    static let maximumAnswer: Duration = .seconds(45)
    /// After `endAudio()`, how long to wait for the final transcript before
    /// keeping the last partial one.
    static let finalGrace: Duration = .milliseconds(800)

    private static let logger = Logger(subsystem: "com.patrickliu.voyage", category: "customs-voice")

    private let synthesizer = AVSpeechSynthesizer()
    private var speechContinuation: CheckedContinuation<Void, Never>?

    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var listenContinuation: CheckedContinuation<String, Error>?
    private var heard = ""
    /// Set once audio has stopped feeding; the silence clock no longer runs.
    private var ending = false
    private var timer: Task<Void, Never>?
    private var capTimer: Task<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    private var recognizer: SFSpeechRecognizer? {
        SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    // MARK: Access

    var access: VoiceAccess {
        guard recognizer?.supportsOnDeviceRecognition == true else { return .unsupported }
        let speech = SFSpeechRecognizer.authorizationStatus()
        let mic = AVAudioApplication.shared.recordPermission
        if speech == .denied || speech == .restricted || mic == .denied { return .denied }
        if speech == .notDetermined || mic == .undetermined { return .notDetermined }
        return .granted
    }

    func requestAccess() async -> VoiceAccess {
        guard access == .notDetermined else { return access }
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            _ = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
        }
        if AVAudioApplication.shared.recordPermission == .undetermined {
            _ = await AVAudioApplication.requestRecordPermission()
        }
        return access
    }

    // MARK: Speaking

    /// The traveler's chosen device voice when they picked one, otherwise the
    /// best installed English voice, by the same ranking the PA uses. The
    /// recorded Voyage Air voices cannot say arbitrary questions.
    private var voice: AVSpeechSynthesisVoice? {
        if let identifier = SettingsStore.shared.paVoiceIdentifier,
           PAVoice(rawValue: identifier) == nil,
           let chosen = AVSpeechSynthesisVoice(identifier: identifier),
           !Announcer.isNoveltyVoice(chosen) {
            return chosen
        }
        return Announcer.bestInstalledVoice()
    }

    func speak(_ text: String) async {
        stopSpeaking()
        activateSession()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        // Unhurried, like the PA, but a conversation rather than an announcement.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        utterance.postUtteranceDelay = 0.15
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                speechContinuation = continuation
                synthesizer.speak(utterance)
            }
        } onCancel: {
            Task { @MainActor in self.stopSpeaking() }
        }
    }

    func stopSpeaking() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        resumeSpeech()
    }

    private func resumeSpeech() {
        speechContinuation?.resume()
        speechContinuation = nil
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.resumeSpeech() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.resumeSpeech() }
    }

    // MARK: Listening

    func listen(hints: [String], onPartial: @escaping @MainActor (String) -> Void) async throws -> String {
        finishListening(with: nil)
        guard access == .granted, let recognizer, recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else { throw CustomsVoiceError.unavailable }
        activateSession()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation
        request.contextualStrings = Array(hints.prefix(50))

        let engine = AVAudioEngine()
        let input = engine.inputNode
        Self.feed(request, from: input)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            Self.logger.info("audio engine failed: \(error.localizedDescription, privacy: .public)")
            throw CustomsVoiceError.audioEngine
        }
        self.engine = engine
        self.request = request
        heard = ""
        ending = false

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                listenContinuation = continuation
                restartTimer(after: Self.openingTimeout)
                capTimer = Task { [weak self] in
                    try? await Task.sleep(for: Self.maximumAnswer)
                    guard !Task.isCancelled else { return }
                    self?.stopListening()
                }
                task = Self.recognize(request, with: recognizer) { [weak self] text, ended in
                    Task { @MainActor in
                        guard let self, self.listenContinuation != nil else { return }
                        if let text {
                            self.heard = text
                            onPartial(text)
                            // Vocable's rule: every new hypothesis restarts the clock.
                            if !self.ending { self.restartTimer(after: Self.silenceTimeout) }
                        }
                        if ended { self.finishListening(with: self.heard) }
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in self.finishListening(with: nil) }
        }
    }

    // The tap and the result handler run on audio and recogniser queues, so
    // both closures are made outside the main actor; a closure formed inside
    // it would carry main-actor isolation onto those queues.

    private nonisolated static func feed(_ request: SFSpeechAudioBufferRecognitionRequest,
                                         from input: AVAudioInputNode) {
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
    }

    /// `handler` gets the best transcript so far (or nil) and whether the
    /// task has ended, by a final result or an error.
    private nonisolated static func recognize(
        _ request: SFSpeechAudioBufferRecognitionRequest,
        with recognizer: SFSpeechRecognizer,
        handler: @escaping @Sendable (String?, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            handler(result?.bestTranscription.formattedString, (result?.isFinal ?? false) || error != nil)
        }
    }

    /// Silence: stop feeding audio, and keep the final transcript if it
    /// arrives within `finalGrace`, else the last partial one.
    func stopListening() {
        guard listenContinuation != nil, !ending else { return }
        ending = true
        request?.endAudio()
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(for: Self.finalGrace)
            guard !Task.isCancelled, let self else { return }
            self.finishListening(with: self.heard)
        }
    }

    private func restartTimer(after delay: Duration) {
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.stopListening()
        }
    }

    /// Tears the recogniser down and answers the waiting `listen` exactly
    /// once. `nil` means cancelled, which answers "".
    private func finishListening(with text: String?) {
        timer?.cancel()
        timer = nil
        capTimer?.cancel()
        capTimer = nil
        if let engine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        engine = nil
        request?.endAudio()
        request = nil
        task?.finish()
        task = nil
        let continuation = listenContinuation
        listenContinuation = nil
        continuation?.resume(returning: (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: Session

    private var sessionActive = false

    private func activateSession() {
        guard !sessionActive else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            sessionActive = true
        } catch {
            Self.logger.info("audio session failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func end() {
        stopSpeaking()
        finishListening(with: nil)
        guard sessionActive else { return }
        sessionActive = false
        // Back to the category `CabinAudioEngine` runs under, so the stamp's
        // thunk and the next flight's ambience behave as before customs.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
    }
}
