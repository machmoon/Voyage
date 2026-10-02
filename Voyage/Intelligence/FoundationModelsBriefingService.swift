#if canImport(FoundationModels)
import Foundation
import FoundationModels

// One of the two files that import FoundationModels (the other is
// FoundationModelsCustomsService.swift). Everything here is iOS 26 only; the
// deployment target stays iOS 17, and `BriefingServiceFactory` is the single
// door in.
//
// Shapes follow Apple's "Adding intelligent app features with generative
// models" sample (FoundationModelsTripPlanner):
// - Model/Itinerary/Itinerary.swift: `@Generable` structs with `@Guide`
//   descriptions and `.count`/`.range` constraints, properties in the order
//   the model should write them.
// - Model/Itinerary/ItineraryPlanner.swift: a session built from
//   instructions, greedy sampling, and the user's content only in the prompt.
// - Views/Itinerary/TripPlanningView.swift: a switch over
//   `SystemLanguageModel.default.availability` with a sentence for each
//   unavailable reason and a `default` fallback.
//
// No tools. Everything the model needs fits in the prompt, and TN3193
// ("Managing the on-device foundation model's context window") counts every
// tool definition against the same 4,096 tokens.

@available(iOS 26.0, *)
@Generable(description: "One study task split into smaller parts.")
struct GeneratedTaskParts {
    @Guide(description: "Two or three different parts of the task, in the order to do them.", .count(2...3))
    var parts: [GeneratedPart]
}

@available(iOS 26.0, *)
@Generable(description: "One part of the task.")
struct GeneratedPart {
    @Guide(description: "A concrete action using the task's own words, under eight words.")
    var action: String
    @Guide(description: "Minutes this part needs.", .range(5...180))
    var minutes: Int
}

// The captain's note is plain text. A regex `@Guide` with no digits was tried
// (the model kept writing "30,000 feet") and threw at runtime on the iOS 26.5
// simulator, so invented numbers are caught by `BriefingRules.captainLine`
// instead, and a rejected note leaves the recorded PA alone.

@available(iOS 26.0, *)
final class FoundationModelsBriefingService: FlightBriefingService, @unchecked Sendable {
    // `@unchecked` because the one piece of state, the prewarmed session, is
    // guarded by `lock`. `LanguageModelSession` is itself `@unchecked Sendable`.
    private let lock = NSLock()
    private var warmPlanSession: LanguageModelSession?

    private let model = SystemLanguageModel.default

    /// Greedy sampling, as the trip planner sample uses for its itinerary:
    /// the same bags give the same plan, which is what a traveler expects
    /// from something that looks like a schedule.
    private static let planOptions = GenerationOptions(sampling: .greedy)
    /// A little variety for the captain, but not much, and a token cap so a
    /// full cruise announcement cannot come back in place of a note.
    private static let captainOptions = GenerationOptions(temperature: 0.4, maximumResponseTokens: 80)

    static var availability: IntelligenceAvailability {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return model.supportsLocale() ? .available : .unsupportedLanguage
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            return .appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable:
            // `UnavailableReason` is not frozen; a future reason lands here.
            return .unavailable
        }
    }

    func prewarm() {
        let session = LanguageModelSession(model: model, instructions: BriefingPrompts.planInstructions)
        session.prewarm()
        lock.withLock { warmPlanSession = session }
    }

    func draftPlan(for request: BriefingRequest) async throws -> [DraftStep] {
        var drafts: [DraftStep] = []
        for (index, bag) in request.bags.enumerated() {
            // A fresh session per request, as Apple's guide says for
            // single-turn work, reusing the prewarmed one for the first.
            let session = lock.withLock { () -> LanguageModelSession in
                defer { warmPlanSession = nil }
                return warmPlanSession
                    ?? LanguageModelSession(model: model, instructions: BriefingPrompts.planInstructions)
            }
            let response = try await session.respond(
                to: BriefingPrompts.planPrompt(forBag: bag, cruiseMinutes: request.cruiseMinutes),
                generating: GeneratedTaskParts.self,
                options: Self.planOptions
            )
            drafts += response.content.parts.map {
                DraftStep(bag: index + 1, action: $0.action, minutes: $0.minutes)
            }
        }
        return drafts
    }

    func captainLine(for request: BriefingRequest, firstStep: String) async throws -> String {
        let session = LanguageModelSession(model: model, instructions: BriefingPrompts.captainInstructions)
        let response = try await session.respond(
            to: BriefingPrompts.captainPrompt(for: request, firstStep: firstStep),
            options: Self.captainOptions
        )
        return response.content
    }

    /// `LanguageModelSession.GenerationError` onto `BriefingError`, case for
    /// case the way Firefox's `SummarizerError` does it.
    static func map(_ error: Error) -> BriefingError? {
        guard let generation = error as? LanguageModelSession.GenerationError else { return nil }
        switch generation {
        case .exceededContextWindowSize: return .contextTooLong
        case .assetsUnavailable: return .unavailable
        case .guardrailViolation: return .guardrail
        case .refusal: return .refusal
        case .unsupportedLanguageOrLocale: return .unsupportedLanguage
        case .rateLimited: return .rateLimited
        case .concurrentRequests: return .busy
        case .decodingFailure, .unsupportedGuide: return .invalidOutput
        @unknown default: return .unknown
        }
    }
}
#endif
