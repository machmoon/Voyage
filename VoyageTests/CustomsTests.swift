import XCTest
@testable import Voyage

/// Customs by voice, end to end against fakes: no microphone, no speech
/// recogniser, no calendar and no model. `CustomsCoachFactory` refuses to hand
/// out the real model under XCTest, the way `BriefingServiceFactory` does.
@MainActor
final class CustomsTests: XCTestCase {

    private let flight = DateInterval(start: Date(timeIntervalSince1970: 1_700_000_000), duration: 2 * 3600)

    override func setUp() async throws {
        SettingsStore.shared.ambienceEnabled = false
        SettingsStore.shared.announcementsEnabled = false
        SettingsStore.shared.customsVoiceIntroSeen = true
    }

    // MARK: Fakes

    private struct FakeCalendar: CalendarEventStore {
        var canRead = true
        var events: [CalendarEvent] = []
        func events(in interval: DateInterval) -> [CalendarEvent] {
            events.filter { $0.end >= interval.start && $0.start <= interval.end }
        }
    }

    private struct FakeCoach: CustomsCoachService {
        var questions: Result<[String], Error> = .success([])
        var feedback: Result<String, Error> = .success("")
        func prewarm() {}
        func questions(for context: StudyContext) async throws -> [String] { try questions.get() }
        func feedback(question: String, answer: String, context: StudyContext) async throws -> String {
            try feedback.get()
        }
    }

    private struct Failure: Error {}

    /// Speaks into a list and answers each `listen` from a script. An answer
    /// of `nil` waits until `stopListening()` or cancellation, like a
    /// traveler mid-sentence.
    private final class FakeVoice: CustomsVoiceIO {
        var access: VoiceAccess
        var grantOnRequest = true
        var script: [String?]
        var partial = "partial words"
        var listenError: Error?
        private(set) var spoken: [String] = []
        private(set) var ended = 0
        private var waiting: CheckedContinuation<String, Error>?

        init(access: VoiceAccess = .granted, script: [String?] = []) {
            self.access = access
            self.script = script
        }

        func requestAccess() async -> VoiceAccess {
            if access == .notDetermined { access = grantOnRequest ? .granted : .denied }
            return access
        }

        func speak(_ text: String) async { spoken.append(text) }

        func listen(hints: [String], onPartial: @escaping @MainActor (String) -> Void) async throws -> String {
            if let listenError { onPartial(partial); throw listenError }
            let next = script.isEmpty ? "" : script.removeFirst()
            if let next {
                onPartial(String(next.prefix(4)))
                return next
            }
            onPartial(partial)
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { waiting = $0 }
            } onCancel: {
                Task { @MainActor in self.stopListening() }
            }
        }

        func stopListening() {
            waiting?.resume(returning: partial)
            waiting = nil
        }

        func stopSpeaking() {}
        func end() { ended += 1 }
    }

    private func interview(coach: CustomsCoachService? = nil,
                           voice: FakeVoice,
                           tasks: [String] = ["Read chapter 9 on mitochondria"],
                           calendarRequests: (() -> Void)? = nil) -> CustomsInterview {
        CustomsInterview(coach: coach, voice: voice,
                         loadContext: { StudyContext(snippets: tasks.map { StudySnippet(origin: .bagTag, title: $0, detail: nil) }) },
                         requestCalendar: { calendarRequests?(); return true })
    }

    // MARK: Study context

    func testContextPutsTheFlightsBagsFirstThenNearestCalendarEvents() async {
        let calendar = FakeCalendar(events: [
            CalendarEvent(title: "Gym", notes: nil,
                          start: flight.end.addingTimeInterval(30 * 3600), end: flight.end.addingTimeInterval(31 * 3600)),
            CalendarEvent(title: "BIO 101 lecture", notes: "Cell respiration https://zoom.us/j/123 bring notes",
                          start: flight.start.addingTimeInterval(-2 * 3600), end: flight.start.addingTimeInterval(-3600)),
            CalendarEvent(title: "Study group", notes: nil,
                          start: flight.start.addingTimeInterval(600), end: flight.start.addingTimeInterval(1200)),
            CalendarEvent(title: "Next month", notes: nil,
                          start: flight.end.addingTimeInterval(30 * 86400), end: flight.end.addingTimeInterval(30 * 86400 + 60)),
            CalendarEvent(title: "   ", notes: "no title", start: flight.start, end: flight.end),
        ])
        let context = await StudyContext.assemble(
            tasks: ["Finish problem set 4", "  "],
            window: flight,
            sources: [CalendarStudySource(store: calendar)]
        )
        XCTAssertEqual(context.snippets.map(\.title),
                       ["Finish problem set 4", "Study group", "BIO 101 lecture", "Gym"],
                       "bags first; overlapping before near; out-of-window and untitled events dropped")
        XCTAssertEqual(context.snippets[2].detail, "Cell respiration bring notes", "links are stripped from notes")
        XCTAssertEqual(context.snippets[0].origin, .bagTag)
        XCTAssertEqual(context.snippets[1].origin, .calendar)
    }

    func testCalendarWithoutAccessAddsNothing() async {
        let calendar = FakeCalendar(canRead: false, events: [
            CalendarEvent(title: "BIO 101", notes: nil, start: flight.start, end: flight.end),
        ])
        let context = await StudyContext.assemble(tasks: ["Read chapter 9"], window: flight,
                                                  sources: [CalendarStudySource(store: calendar)])
        XCTAssertEqual(context.snippets.map(\.title), ["Read chapter 9"])
    }

    func testContextDropsDuplicatesTrimsAndCapsForTheModelsWindow() {
        let long = String(repeating: "word ", count: 100)
        let snippets = [StudySnippet(origin: .bagTag, title: "Essay", detail: nil),
                        StudySnippet(origin: .calendar, title: "essay", detail: nil),
                        StudySnippet(origin: .calendar, title: long, detail: long)]
            + (1...20).map { StudySnippet(origin: .calendar, title: "Event \($0)", detail: nil) }
        let context = StudyContext(snippets: snippets)
        XCTAssertEqual(context.snippets.count, StudyContext.maximumSnippets)
        XCTAssertEqual(context.snippets.filter { $0.title.lowercased() == "essay" }.count, 1)
        XCTAssertLessThanOrEqual(context.snippets[1].title.count, StudyContext.maximumTitleLength)
        XCTAssertLessThanOrEqual(context.snippets[1].detail?.count ?? 0, StudyContext.maximumDetailLength)
    }

    func testPromptCarriesTheMaterialOnlyAsData() {
        let context = StudyContext(snippets: [StudySnippet(origin: .bagTag, title: "Read chapter 9", detail: nil),
                                              StudySnippet(origin: .calendar, title: "BIO 101", detail: "Krebs cycle")])
        XCTAssertEqual(CustomsPrompts.questionPrompt(for: context),
                       "Studied:\n1. Task: Read chapter 9\n2. Calendar: BIO 101 (Krebs cycle)")
        XCTAssertFalse(CustomsPrompts.questionInstructions.contains("chapter 9"))
        XCTAssertFalse(CustomsPrompts.feedbackInstructions.contains("chapter 9"))
    }

    // MARK: Questions

    func testNoModelMeansTheOriginalCustomsQuestions() async {
        XCTAssertNil(CustomsCoachFactory.make(), "no real model under XCTest")
        let interview = interview(voice: FakeVoice())
        await interview.prepare()
        XCTAssertEqual(interview.questions, CustomsRules.fallbackQuestions)
        XCTAssertEqual(interview.questions, [
            "One idea you can now explain without your notes",
            "An example or detail that goes with it",
            "One question you'd test yourself on next time",
        ])
        XCTAssertEqual(interview.phase, .ready)
    }

    func testAFailingModelFallsBackToTheOriginalQuestions() async {
        let interview = interview(coach: FakeCoach(questions: .failure(Failure())), voice: FakeVoice())
        await interview.prepare()
        XCTAssertEqual(interview.questions, CustomsRules.fallbackQuestions)
    }

    func testModelQuestionsAreKeptOnlyWhenGroundedThenPaddedWithTheOriginals() {
        let context = StudyContext(snippets: [StudySnippet(origin: .bagTag, title: "Read chapter 9 on mitochondria", detail: nil)])
        let raw = [
            "Why do mitochondria have their own DNA?",
            "What does chapter 12 say about mitochondria?",   // invented number
            "What is your favourite colour?",                  // about nothing studied
            "  Why do mitochondria have their own DNA? ",      // duplicate
        ]
        XCTAssertEqual(CustomsRules.questions(from: raw, context: context), [
            "Why do mitochondria have their own DNA?",
            "An example or detail that goes with it",
            "One question you'd test yourself on next time",
        ])
    }

    // MARK: Transcript to feedback

    func testSpokenAnswersFillTheCardAndEachGetsAKindLine() async {
        let voice = FakeVoice(script: ["They make ATP", "", "Krebs cycle"])
        let coach = FakeCoach(questions: .success(["Why are mitochondria called the powerhouse?",
                                                   "What happens inside mitochondria?",
                                                   "Where does chapter 9 start the story?"]),
                              feedback: .success("Nice, you also covered the energy part."))
        let interview = interview(coach: coach, voice: voice)
        await interview.prepare()
        XCTAssertEqual(interview.phase, .ready)
        interview.start()
        await interview.waitUntilIdle()

        XCTAssertEqual(interview.answers, ["They make ATP", "", "Krebs cycle"])
        XCTAssertEqual(interview.phase, .finished)
        XCTAssertEqual(voice.spoken, [
            "Why are mitochondria called the powerhouse?",
            "Nice, you also covered the energy part.",
            "What happens inside mitochondria?",
            // Silence is not an answer: no feedback for question two.
            "Where does chapter 9 start the story?",
            "Nice, you also covered the energy part.",
        ])
        XCTAssertGreaterThan(voice.ended, 0, "the microphone is released at the end")
    }

    func testFeedbackThatGradesIsReplacedWithAKindFixedLine() async {
        let voice = FakeVoice(script: ["They make ATP", "x", "y"])
        let coach = FakeCoach(feedback: .success("Wrong. That is 2 out of 10."))
        let interview = interview(coach: coach, voice: voice)
        await interview.prepare()
        interview.start()
        await interview.waitUntilIdle()
        XCTAssertEqual(voice.spoken[1], CustomsRules.fallbackFeedback(forQuestion: 0))
        XCTAssertFalse(voice.spoken.contains { $0.contains("Wrong") })
    }

    func testFeedbackRulesKeepTwoSentencesAndRefuseInventedNumbers() {
        let context = StudyContext(snippets: [StudySnippet(origin: .bagTag, title: "Read chapter 9", detail: nil)])
        XCTAssertEqual(CustomsRules.feedback("Close. Remember chapter 9 starts with glycolysis. Great work! Keep going.",
                                             answer: "glucose", context: context),
                       "Close. Remember chapter 9 starts with glycolysis.")
        XCTAssertNil(CustomsRules.feedback("You got 80 percent of it.", answer: "glucose", context: context))
        XCTAssertNil(CustomsRules.feedback("Chapter 12 covers that.", answer: "glucose", context: context))
    }

    // MARK: Exits to typing

    func testTypeInsteadKeepsWhatWasHeardAndFocusesTheField() async {
        let voice = FakeVoice(script: [nil])
        voice.partial = "Spaced repetition"
        let interview = interview(voice: voice)
        await interview.prepare()
        interview.start()
        while interview.phase != .listening(0) { await Task.yield() }
        interview.typeInstead()
        await interview.waitUntilIdle()
        XCTAssertEqual(interview.phase, .typing)
        XCTAssertEqual(interview.answers[0], "Spaced repetition")
        XCTAssertEqual(interview.focusRequest?.index, 1, "the keyboard opens on the first empty field")
    }

    func testSkipDropsAHalfHeardAnswerAndMovesOn() async {
        let voice = FakeVoice(script: [nil, "Second", "Third"])
        let interview = interview(voice: voice)
        await interview.prepare()
        interview.start()
        while interview.phase != .listening(0) { await Task.yield() }
        interview.skip()
        await interview.waitUntilIdle()
        XCTAssertEqual(interview.answers, ["", "Second", "Third"])
        XCTAssertEqual(interview.phase, .finished)
    }

    func testARecogniserFailureFallsBackToTypingWithoutLosingWords() async {
        let voice = FakeVoice()
        voice.listenError = CustomsVoiceError.audioEngine
        voice.partial = "Mitochondria"
        let interview = interview(voice: voice)
        await interview.prepare()
        interview.start()
        await interview.waitUntilIdle()
        XCTAssertEqual(interview.phase, .typing)
        XCTAssertEqual(interview.answers[0], "Mitochondria")
        XCTAssertNotNil(interview.notice)
    }

    func testDeniedVoiceIsTypingWithASentenceSayingWhy() async {
        let interview = interview(voice: FakeVoice(access: .denied))
        await interview.prepare()
        XCTAssertEqual(interview.phase, .typing)
        XCTAssertTrue(interview.notice?.contains("Settings") == true)
        XCTAssertFalse(interview.canUseVoice)
    }

    func testUnsupportedDeviceIsQuietlyTyping() async {
        let interview = interview(voice: FakeVoice(access: .unsupported))
        await interview.prepare()
        XCTAssertEqual(interview.phase, .typing)
        XCTAssertNil(interview.notice)
    }

    // MARK: First customs

    func testFirstCustomsExplainsBeforeAnySystemPrompt() async {
        SettingsStore.shared.customsVoiceIntroSeen = false
        defer { SettingsStore.shared.customsVoiceIntroSeen = true }
        var calendarAsked = 0
        let voice = FakeVoice(access: .notDetermined, script: ["a", "b", "c"])
        let interview = interview(voice: voice, calendarRequests: { calendarAsked += 1 })
        await interview.prepare()
        XCTAssertEqual(interview.phase, .intro)
        XCTAssertEqual(calendarAsked, 0, "nothing is requested before the traveler chooses")
        XCTAssertEqual(voice.access, .notDetermined)

        await interview.acceptIntro()
        await interview.waitUntilIdle()
        XCTAssertEqual(calendarAsked, 1)
        XCTAssertTrue(SettingsStore.shared.customsVoiceIntroSeen)
        XCTAssertEqual(interview.answers, ["a", "b", "c"], "accepting starts the interview")
    }

    func testDecliningTheIntroAsksForNothingAndTypes() async {
        SettingsStore.shared.customsVoiceIntroSeen = false
        defer { SettingsStore.shared.customsVoiceIntroSeen = true }
        var calendarAsked = 0
        let voice = FakeVoice(access: .notDetermined)
        let interview = interview(voice: voice, calendarRequests: { calendarAsked += 1 })
        await interview.prepare()
        await interview.declineIntro()
        XCTAssertEqual(interview.phase, .typing)
        XCTAssertEqual(calendarAsked, 0)
        XCTAssertEqual(voice.access, .notDetermined, "no microphone prompt either")
        XCTAssertEqual(interview.focusRequest?.index, 0)
    }

    // MARK: The setting

    func testCustomsOffGoesStraightFromWelcomeToTheStamp() {
        XCTAssertEqual(ArrivalFlowView.Step.afterWelcome(customsEnabled: true), .declaration)
        XCTAssertEqual(ArrivalFlowView.Step.afterWelcome(customsEnabled: false), .stamp)
    }

    func testCustomsSettingPersists() {
        let settings = SettingsStore.shared
        let original = settings.customsEnabled
        defer { settings.customsEnabled = original }
        settings.customsEnabled = false
        XCTAssertEqual(UserDefaults.standard.object(forKey: "customsEnabled") as? Bool, false)
        settings.customsEnabled = true
        XCTAssertEqual(UserDefaults.standard.object(forKey: "customsEnabled") as? Bool, true)
    }
}
