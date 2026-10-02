import Foundation

// Customs by voice: three recall questions written from the traveler's own
// study material, and one kind line back after each spoken answer.
//
// Built exactly the way the flight briefing is (FlightBriefing.swift), and
// for the same reasons: a service protocol with no availability requirement,
// one Foundation Models conformer behind `#if canImport` and iOS 26
// (FoundationModelsCustomsService.swift), a factory that answers `nil`
// whenever the answer should be "customs as it was", the traveler's words
// only ever in the prompt, never in the instructions, and code-side rules
// that throw away any model text breaking them.
//
// The model is trusted with wording only. It never grades: retrieval
// practice works without feedback at all (Roediger & Karpicke 2006), so the
// feedback line exists to encourage, and a line that reads like a mark is
// dropped for a fixed kind one.

// MARK: - Service

protocol CustomsCoachService: Sendable {
    func prewarm()
    /// Up to three questions, raw. `CustomsRules.questions` decides what stays.
    func questions(for context: StudyContext) async throws -> [String]
    /// One line of feedback on one spoken answer, raw.
    func feedback(question: String, answer: String, context: StudyContext) async throws -> String
}

// MARK: - Prompts

enum CustomsPrompts {
    static let questionInstructions = """
    A student just finished a study session. Below is a list of what they \
    were studying, in their own words. Write three short questions that ask \
    the student to recall something from that material out loud, from \
    memory. Each question names a topic from the list, using the list's own \
    words. Ask about ideas, reasons and examples, not about the list itself. \
    Keep each question under eighteen words and end it with a question mark. \
    Never add page numbers, chapter numbers, dates or other numbers that are \
    not in the list. Do not answer the questions.
    """

    static func questionPrompt(for context: StudyContext) -> String {
        "Studied:\n\(context.promptLines)"
    }

    static let feedbackInstructions = """
    You are a friendly customs officer at an airport who also tutors \
    students. A student answered one recall question out loud; the answer is \
    a speech transcript, so ignore filler words and small transcription \
    mistakes. Reply with one short, warm sentence of under twenty words. If \
    the answer gets the idea, say what was good, and you may name one more \
    point from the study list they could add. If it is incomplete or off, \
    gently remind them of one key point, starting with "Close." Never say \
    the answer is wrong, never give a score, grade or percentage, and do not \
    use numbers, exclamation marks or emoji.
    """

    static func feedbackPrompt(question: String, answer: String, context: StudyContext) -> String {
        """
        Studied:
        \(context.promptLines)
        Question: \(question)
        Student's answer: \(answer)
        """
    }
}

// MARK: - Rules

enum CustomsRules {
    /// The questions customs asked before it had a voice, and what it still
    /// asks whenever the model is not there or says nothing usable.
    static let fallbackQuestions = [
        "One idea you can now explain without your notes",
        "An example or detail that goes with it",
        "One question you'd test yourself on next time",
    ]

    static let questionCount = 3
    static let maximumQuestionLength = 140
    static let maximumFeedbackLength = 160

    /// Words that make a line read like a mark rather than encouragement.
    static let gradingWords = ["wrong", "incorrect", "score", "grade", "percent", "fail", "out of"]

    /// Model questions that pass every rule, then the fallback questions to
    /// make three. A question survives when it is one tidy line, has no
    /// number the material does not have, and names something from the
    /// material, the same grounding the captain's note must pass.
    static func questions(from raw: [String], context: StudyContext) -> [String] {
        var kept: [String] = []
        var seen = Set<String>()
        for line in raw {
            let question = BriefingRules.tidy(line)
            guard !question.isEmpty,
                  question.count <= maximumQuestionLength,
                  !BriefingRules.containsEmoji(question),
                  BriefingRules.numbersAreGrounded(question, in: context.texts),
                  BriefingRules.mentionsABag(question, bags: context.texts),
                  seen.insert(question.lowercased()).inserted
            else { continue }
            kept.append(question)
            if kept.count == questionCount { break }
        }
        // Fill by position: the fixed questions are a chain ("an example
        // that goes with it" follows an idea), so slot two of the fallback
        // follows whatever idea slot one asked for.
        while kept.count < questionCount {
            kept.append(fallbackQuestions[kept.count])
        }
        return kept
    }

    /// The model's line, or `nil` when it breaks a rule. At most two
    /// sentences, nothing that grades, no invented numbers.
    static func feedback(_ raw: String, answer: String, context: StudyContext) -> String? {
        let sentences = BriefingRules.sentences(in: raw)
            .filter { !BriefingRules.containsEmoji($0) }
            .prefix(2)
        let line = sentences.joined(separator: " ")
        let lowered = line.lowercased()
        guard !line.isEmpty,
              line.count <= maximumFeedbackLength,
              !gradingWords.contains(where: lowered.contains),
              BriefingRules.numbersAreGrounded(line, in: context.texts + [answer])
        else { return nil }
        return line
    }

    /// What the officer says when there is no model line. Kind, short, and
    /// about the act of recalling, since without a model nothing can judge
    /// the content. Chosen by question so the three answers do not all hear
    /// the same sentence.
    static func fallbackFeedback(forQuestion index: Int) -> String {
        let lines = [
            "Thank you. Saying it out loud is what makes it stick.",
            "Good. A detail like that is what you'll remember later.",
            "Noted. That one is worth asking yourself again tomorrow.",
        ]
        return lines[((index % lines.count) + lines.count) % lines.count]
    }
}

// MARK: - Factory

/// The only way production gets a coach. `nil` means fixed questions and
/// fixed kind lines, which is customs exactly as it worked before.
enum CustomsCoachFactory {
    static func make(settings: SettingsStore = .shared,
                     processInfo: ProcessInfo = .processInfo) -> CustomsCoachService? {
        guard processInfo.environment["XCTestConfigurationFilePath"] == nil else { return nil }
        #if DEBUG
        if processInfo.arguments.contains("-VoyageCustomsDemo") { return DemoCustomsCoach() }
        #endif
        guard settings.onDeviceIntelligenceEnabled else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), IntelligenceAvailability.current == .available {
            return FoundationModelsCustomsService()
        }
        #endif
        return nil
    }
}

#if DEBUG
/// Canned answers for `-VoyageCustomsDemo`, built from the context so a
/// capture shows real input going through the real rules.
struct DemoCustomsCoach: CustomsCoachService {
    func prewarm() {}

    func questions(for context: StudyContext) async throws -> [String] {
        try await Task.sleep(for: .milliseconds(500))
        return context.snippets.prefix(3).map { "What is the main idea behind \($0.title.lowercased())?" }
    }

    func feedback(question: String, answer: String, context: StudyContext) async throws -> String {
        try await Task.sleep(for: .milliseconds(400))
        return "Nice, that's the core of it. You could also connect it to \(context.snippets.last?.title ?? "your notes")."
    }
}
#endif
