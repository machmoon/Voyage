import Foundation
import Observation

/// The customs officer's side of the declaration: write the questions, ask
/// each one aloud, listen, say one kind line, move on. The card on screen
/// (`CustomsDeclarationView`) stays the form it always was; this fills it in.
///
/// Every exit is the keyboard. Voice unavailable, permission denied, the
/// recogniser failing mid-answer, or the traveler tapping "Type instead"
/// all end in `.typing` with whatever was already heard left in the fields
/// to edit, so nothing said is lost and nothing blocks the stamp.
@MainActor
@Observable
final class CustomsInterview {
    enum Phase: Equatable {
        /// Gathering the study context and writing the questions.
        case preparing
        /// First customs: what voice customs is, before any system prompt.
        case intro
        /// Voice is ready; the officer waits for "Answer out loud".
        case ready
        case asking(Int)
        case listening(Int)
        /// Writing the feedback line for an answer.
        case thinking(Int)
        case feedback(Int, String)
        /// All questions asked by voice.
        case finished
        case typing
    }

    /// The longest the traveler waits for the model before the fixed
    /// questions or the fixed kind line are used instead.
    static let questionBudget: Duration = .seconds(8)
    static let feedbackBudget: Duration = .seconds(5)

    private(set) var phase: Phase = .preparing
    private(set) var questions = CustomsRules.fallbackQuestions
    /// Bound to the card's three fields. Speech writes here as it is heard.
    var answers = ["", "", ""]
    /// One plain sentence when voice is not available, saying why.
    private(set) var notice: String?
    /// The field the card should focus, bumped by `typeInstead()`.
    private(set) var focusRequest: FocusRequest?
    /// Whether the voice path can be offered at all on this device right now.
    var canUseVoice: Bool { voice.access == .granted }

    struct FocusRequest: Equatable {
        let index: Int
        let serial: Int
    }

    private let coach: CustomsCoachService?
    private let voice: CustomsVoiceIO
    private let settings: SettingsStore
    private let loadContext: () async -> StudyContext
    private let requestCalendar: () async -> Bool

    private var context = StudyContext.empty
    private var run: Task<Void, Never>?
    private var skipped: Int?

    init(coach: CustomsCoachService?,
         voice: CustomsVoiceIO,
         settings: SettingsStore = .shared,
         loadContext: @escaping () async -> StudyContext,
         requestCalendar: @escaping () async -> Bool) {
        self.coach = coach
        self.voice = voice
        self.settings = settings
        self.loadContext = loadContext
        self.requestCalendar = requestCalendar
    }

    /// The question being worked on, for the card's highlight.
    var activeIndex: Int? {
        switch phase {
        case let .asking(index), let .listening(index), let .thinking(index), let .feedback(index, _):
            return index
        default:
            return nil
        }
    }

    var isRunning: Bool { activeIndex != nil }

    // MARK: Entry

    /// Called when the customs screen appears.
    func prepare() async {
        guard phase == .preparing else { return }
        coach?.prewarm()
        if voice.access == .notDetermined, !settings.customsVoiceIntroSeen {
            phase = .intro
            return
        }
        await writeQuestions()
        settle()
        #if DEBUG
        // A capture asked for a held stage: go straight to it.
        if let demo = voice as? CustomsDemo, let hold = demo.hold {
            if hold == .typing { typeInstead() } else if hold != .intro { start() }
        }
        #endif
    }

    /// "Use voice" on the intro: ask for the calendar, then the microphone
    /// and speech, then begin. Each system prompt follows Voyage's own
    /// sentence about it, never arrives cold.
    func acceptIntro() async {
        guard phase == .intro else { return }
        settings.customsVoiceIntroSeen = true
        phase = .preparing
        _ = await requestCalendar()
        _ = await voice.requestAccess()
        await writeQuestions()
        if canUseVoice { start() } else { settle() }
    }

    /// "Type instead" on the intro. Nothing is asked for.
    func declineIntro() async {
        guard phase == .intro else { return }
        settings.customsVoiceIntroSeen = true
        phase = .preparing
        await writeQuestions()
        typeInstead()
    }

    // MARK: Controls

    /// "Answer out loud": from the first question without an answer.
    func start() {
        guard canUseVoice, !isRunning else { return }
        guard let first = answers.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
        else { return }
        notice = nil
        run = Task { await interview(from: first) }
    }

    /// Moves on from the current question. A half-heard answer is dropped;
    /// an answer already heard keeps its place while its feedback is cut.
    func skip() {
        guard let index = activeIndex else { return }
        skipped = index
        if case .feedback = phase {} else if case .thinking = phase {} else { answers[index] = "" }
        voice.stopSpeaking()
        voice.stopListening()
    }

    /// Stops the officer and hands over the keyboard at the first empty field.
    func typeInstead(notice: String? = nil) {
        stop()
        self.notice = notice
        phase = .typing
        let index = answers.firstIndex { $0.trimmingCharacters(in: .whitespaces).isEmpty } ?? 0
        focusRequest = FocusRequest(index: index, serial: (focusRequest?.serial ?? 0) + 1)
    }

    /// Leaving customs, by either channel or by the screen going away.
    func stop() {
        run?.cancel()
        run = nil
        voice.end()
    }

    /// Waits for a running interview to end. For tests, which drive the
    /// whole loop through a scripted `CustomsVoiceIO`.
    func waitUntilIdle() async {
        await run?.value
    }

    // MARK: The interview

    private func interview(from start: Int) async {
        for index in start..<questions.count {
            guard !Task.isCancelled else { return }
            skipped = nil
            phase = .asking(index)
            await voice.speak(questions[index])
            guard !Task.isCancelled else { return }
            if skipped == index { continue }

            phase = .listening(index)
            let heard: String
            do {
                heard = try await voice.listen(hints: hints) { [weak self] partial in
                    guard let self, self.phase == .listening(index) else { return }
                    self.answers[index] = partial
                }
            } catch {
                typeInstead(notice: "Voice stopped. Type the rest below.")
                return
            }
            guard !Task.isCancelled else { return }
            if skipped == index { answers[index] = ""; continue }
            answers[index] = heard
            // Silence is not an answer and gets no feedback; the field stays
            // open for typing later.
            guard !heard.isEmpty else { continue }

            phase = .thinking(index)
            let line = await feedback(for: index, answer: heard)
            guard !Task.isCancelled else { return }
            if skipped == index { continue }
            phase = .feedback(index, line)
            await voice.speak(line)
            guard !Task.isCancelled, skipped != index else { continue }
            try? await Task.sleep(for: .milliseconds(500))
        }
        guard !Task.isCancelled else { return }
        voice.end()
        phase = .finished
    }

    /// Topic words from the context, to help recognition hear them.
    private var hints: [String] {
        context.snippets.flatMap { BriefingRules.words(in: $0.title) }
    }

    private func feedback(for index: Int, answer: String) async -> String {
        let fallback = CustomsRules.fallbackFeedback(forQuestion: index)
        guard let coach else { return fallback }
        let question = questions[index]
        let context = context
        let raw = await Self.withBudget(Self.feedbackBudget) {
            try await coach.feedback(question: question, answer: answer, context: context)
        }
        return raw.flatMap { CustomsRules.feedback($0, answer: answer, context: context) } ?? fallback
    }

    // MARK: Questions

    private func writeQuestions() async {
        context = await loadContext()
        guard let coach, !context.isEmpty else { return }
        let context = context
        let raw = await Self.withBudget(Self.questionBudget) {
            try await coach.questions(for: context)
        }
        // Never swap the questions under an answer already written.
        guard let raw, answers.allSatisfy({ $0.isEmpty }) else { return }
        questions = CustomsRules.questions(from: raw, context: context)
    }

    /// After the questions are written: voice if it can run, else the keyboard
    /// with a sentence saying why when the reason is one the traveler can fix.
    private func settle() {
        switch voice.access {
        case .granted:
            phase = .ready
        case .denied:
            phase = .typing
            notice = "Microphone or speech is off for Voyage in Settings. Typing works the same."
        case .unsupported, .notDetermined:
            phase = .typing
        }
    }

    /// The operation's value, or nil when it throws or outlasts `budget`.
    static func withBudget<T: Sendable>(_ budget: Duration,
                                        _ operation: @escaping @Sendable () async throws -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { try? await operation() }
            group.addTask {
                try? await Task.sleep(for: budget)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

extension CustomsInterview {
    /// Production wiring for one arrival: the session's bags and flight window,
    /// the calendar, Apple Intelligence when it can run, the live microphone.
    static func live(for session: FlightSession) -> CustomsInterview {
        let tasks = session.intentions
        let start = session.departedAt ?? session.bookedAt
        let window = DateInterval(start: start, end: max(start, session.now))
        #if DEBUG
        if let demo = CustomsDemo.fromLaunchArguments() {
            return CustomsInterview(coach: CustomsCoachFactory.make(), voice: demo,
                                    loadContext: { await StudyContext.assemble(tasks: tasks, window: window, sources: []) },
                                    requestCalendar: { false })
        }
        #endif
        return CustomsInterview(
            coach: CustomsCoachFactory.make(),
            voice: LiveCustomsVoice(),
            loadContext: {
                await StudyContext.assemble(tasks: tasks, window: window, sources: StudyContextSources.live())
            },
            requestCalendar: { await EventKitCalendarStore.requestAccess() }
        )
    }
}

#if DEBUG
/// `-VoyageCustomsDemo [intro|asking|listening|feedback|typing]`: a scripted officer for
/// simulator captures, where on-device recognition is not available. With a
/// stage named, the demo holds on that stage of the first question.
@MainActor
final class CustomsDemo: CustomsVoiceIO {
    enum Hold: String { case intro, asking, listening, feedback, typing }

    let hold: Hold?
    private var spoken = 0

    init(hold: Hold?) { self.hold = hold }

    static func fromLaunchArguments() -> CustomsDemo? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-VoyageCustomsDemo") else { return nil }
        let hold = arguments.indices.contains(flag + 1) ? Hold(rawValue: arguments[flag + 1]) : nil
        return CustomsDemo(hold: hold)
    }

    private var granted = false
    var access: VoiceAccess { hold == .intro && !granted ? .notDetermined : .granted }
    func requestAccess() async -> VoiceAccess { granted = true; return .granted }

    func speak(_ text: String) async {
        spoken += 1
        let holdHere = (hold == .asking && spoken == 1) || (hold == .feedback && spoken == 2)
        try? await Task.sleep(for: holdHere ? .seconds(3600) : .seconds(1.5))
    }

    func listen(hints: [String], onPartial: @escaping @MainActor (String) -> Void) async throws -> String {
        let words = "Spaced repetition beats cramming because each review".split(separator: " ")
        var said = ""
        for word in words {
            try? await Task.sleep(for: .milliseconds(250))
            said += (said.isEmpty ? "" : " ") + word
            onPartial(said)
        }
        if hold == .listening { try? await Task.sleep(for: .seconds(3600)) }
        return said + " comes just before you forget"
    }

    func stopListening() {}
    func stopSpeaking() {}
    func end() {}
}
#endif
