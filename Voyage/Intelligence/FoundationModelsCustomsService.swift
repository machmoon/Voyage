#if canImport(FoundationModels)
import Foundation
import FoundationModels

// The customs half of the app's Foundation Models use. Same shape as
// FoundationModelsBriefingService.swift (itself after Apple's
// FoundationModelsTripPlanner sample): `@Generable` output with a `.count`
// guide, a fresh session per single-turn request, instructions that hold the
// rules and a prompt that holds only the traveler's material. Availability
// and error mapping are the briefing service's, reused rather than copied.

@available(iOS 26.0, *)
@Generable(description: "Recall questions about what a student studied.")
struct GeneratedCustomsQuestions {
    @Guide(description: "Three short recall questions, each naming a topic from the list.", .count(3))
    var questions: [String]
}

@available(iOS 26.0, *)
final class FoundationModelsCustomsService: CustomsCoachService, @unchecked Sendable {
    // `@unchecked` for the same reason as the briefing service: the one piece
    // of state, the prewarmed session, is guarded by `lock`.
    private let lock = NSLock()
    private var warmQuestionSession: LanguageModelSession?
    private let model = SystemLanguageModel.default

    /// Greedy for the questions: the same material asks the same thing.
    private static let questionOptions = GenerationOptions(sampling: .greedy)
    /// A little warmth for the reply, capped so a lecture cannot come back.
    private static let feedbackOptions = GenerationOptions(temperature: 0.4, maximumResponseTokens: 60)

    func prewarm() {
        let session = LanguageModelSession(model: model, instructions: CustomsPrompts.questionInstructions)
        session.prewarm()
        lock.withLock { warmQuestionSession = session }
    }

    func questions(for context: StudyContext) async throws -> [String] {
        let session = lock.withLock { () -> LanguageModelSession in
            defer { warmQuestionSession = nil }
            return warmQuestionSession
                ?? LanguageModelSession(model: model, instructions: CustomsPrompts.questionInstructions)
        }
        let response = try await session.respond(
            to: CustomsPrompts.questionPrompt(for: context),
            generating: GeneratedCustomsQuestions.self,
            options: Self.questionOptions
        )
        return response.content.questions
    }

    func feedback(question: String, answer: String, context: StudyContext) async throws -> String {
        let session = LanguageModelSession(model: model, instructions: CustomsPrompts.feedbackInstructions)
        let response = try await session.respond(
            to: CustomsPrompts.feedbackPrompt(question: question, answer: answer, context: context),
            options: Self.feedbackOptions
        )
        return response.content
    }
}
#endif
