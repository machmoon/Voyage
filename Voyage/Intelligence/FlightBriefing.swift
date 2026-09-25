import Foundation
import os

// On-device flight briefing: a plan that breaks the traveler's bags into
// steps sized to this leg's cruise, and one short note from the captain at
// the top of cruise.
//
// Everything in this file is plain Swift and builds for iOS 17. The Apple
// Intelligence half lives in `FoundationModelsBriefingService.swift`, behind
// `#if canImport(FoundationModels)` and `@available(iOS 26, *)`.
//
// The split follows two apps that ship Foundation Models below an iOS 26
// deployment target:
//
// - iBurn (iBurnApp/iBurn-iOS, iBurn/AISearch/AISearchService.swift): a
//   service protocol with no availability requirement, and a factory that
//   returns `nil` below iOS 26 or when the model is unavailable, so every
//   caller's fallback is simply "no service".
// - Firefox (mozilla-mobile/firefox-ios,
//   BrowserKit/Sources/SummarizeKit/Backend/SummarizerError.swift and
//   FoundationModelsSummarizer.swift): the framework's `GenerationError`
//   mapped onto the app's own error type, and the user's text kept out of
//   the instructions so it is only ever treated as data.
//
// What the model is trusted with is deliberately narrow. The study coach
// (Voyage/Views/Logbook/StudyCoachSection.swift) records that a free-form
// Foundation Models note over the logbook was tried on September 15, 2026 and
// dropped because it invented counts. So here the model only rewords the
// traveler's own bags. Minutes are computed in code, and any number the model
// writes that is not in the traveler's own words throws the text away.

// MARK: - Request

/// What the model is told. Built from the live session, never from the logbook.
struct BriefingRequest: Equatable, Sendable {
    /// The traveler's bags, trimmed, non-empty, at most three.
    let bags: [String]
    let originCity: String
    let destinationCity: String
    /// Whole minutes between the top of climb and the top of descent on this leg.
    let cruiseMinutes: Int

    /// Longest bag text passed to the model. The on-device model has a 4,096
    /// token window for instructions, prompt and output together (Apple
    /// TN3193); three bags of this length stay far inside it.
    static let maximumBagLength = 120

    init(bags: [String], originCity: String, destinationCity: String, cruiseMinutes: Int) {
        self.bags = bags
            .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumBagLength)) }
            .filter { !$0.isEmpty }
            .prefix(3)
            .map { $0 }
        self.originCity = originCity
        self.destinationCity = destinationCity
        self.cruiseMinutes = max(0, cruiseMinutes)
    }
}

// MARK: - Model output, before and after the rules

/// One step as the model proposed it. `bag` is 1-based, the way the prompt
/// numbers the bags.
struct DraftStep: Equatable, Sendable {
    let bag: Int
    let action: String
    let minutes: Int
}

/// The plan the traveler sees. Minutes are measured from the top of cruise
/// and always sum to the cruise window.
struct FlightPlan: Equatable, Sendable {
    struct Step: Equatable, Sendable, Identifiable {
        let index: Int
        /// 0-based index into the request's bags.
        let bag: Int
        let action: String
        let startMinute: Int
        let minutes: Int

        var id: Int { index }
        var endMinute: Int { startMinute + minutes }
    }

    let steps: [Step]

    var totalMinutes: Int { steps.last?.endMinute ?? 0 }

    /// The step being worked on `minute` minutes into cruise. Before cruise it
    /// is the first step; past the end it is the last.
    func step(atCruiseMinute minute: Double) -> Step? {
        guard let first = steps.first else { return nil }
        if minute < 0 { return first }
        return steps.first { minute < Double($0.endMinute) } ?? steps.last
    }
}

// MARK: - Errors

/// The app's own taxonomy for a briefing that did not arrive. Mapped from
/// `LanguageModelSession.GenerationError` the way Firefox maps it in
/// `SummarizerError.swift`. None of these is shown to the traveler: every one
/// ends in the flight as it was before, so the cases exist for tests and logs.
enum BriefingError: Error, Equatable {
    case unavailable
    case guardrail
    case refusal
    case contextTooLong
    case unsupportedLanguage
    case busy
    case rateLimited
    case invalidOutput
    case cancelled
    case unknown
}

// MARK: - Service

/// The seam unit tests replace. Production has exactly one conformer, the
/// Foundation Models service, and gets it only from `BriefingServiceFactory`.
protocol FlightBriefingService: Sendable {
    /// Loads the model ahead of the first request. Apple's trip planner sample
    /// calls `session.prewarm()` when its screen appears
    /// (FoundationModelsTripPlanner, Views/Itinerary/LandmarkTripView.swift).
    func prewarm()
    func draftPlan(for request: BriefingRequest) async throws -> [DraftStep]
    func captainLine(for request: BriefingRequest, firstStep: String) async throws -> String
}

// MARK: - Prompts

/// Instructions and prompts, kept apart so tests can read them. Instructions
/// hold the rules; the traveler's words only ever appear in the prompt, as
/// data, which is the separation Firefox's summarizer relies on.
enum BriefingPrompts {
    /// One bag per request. Asked for all three at once, the on-device model
    /// repeated the bag list three times, or filed one bag's step under
    /// another; one task at a time it only has to split one thing.
    static let planInstructions = """
    A student is studying on a flight and wrote down one task. Split that task \
    into two or three smaller, concrete parts, in the order to do them. Each \
    part is a different piece of the task; never repeat the task itself. Keep \
    the task's own words in each part and keep each part under eight words. \
    Never add page numbers, problem numbers, chapter numbers or counts that are \
    not in the task. Estimate the minutes each part needs.
    """
    // No worked example here or in the captain's instructions. With one, the
    // on-device model copied it: a simulator run filed "Outline the history
    // essay" under the bag "Finish problem set 4".

    static func planPrompt(forBag bag: String, cruiseMinutes: Int) -> String {
        "Task: \(bag)\nTime for all of today's tasks: \(cruiseMinutes) minutes."
    }

    static let captainInstructions = """
    You are the captain of a Voyage Air flight with one passenger, a student \
    who is studying during the flight. Write the short note the captain gives \
    that passenger when the plane reaches cruise. Speak to them as "you", never \
    "ladies and gentlemen".
    Name the destination city and the student's first task, using the task's \
    own words. Be calm and plain, like a real airline captain. Use at most two \
    short sentences and fewer than thirty words. Do not mention altitude, speed \
    or time. Do not use numbers, exclamation marks or emoji. Do not give study \
    advice and do not promise results.
    """

    static func captainPrompt(for request: BriefingRequest, firstStep: String) -> String {
        var lines = [
            "Flying from: \(request.originCity)",
            "Flying to: \(request.destinationCity)",
            "First task: \(firstStep)"
        ]
        let others = request.bags.dropFirst()
        if !others.isEmpty {
            lines.append("Also packed: \(others.joined(separator: "; "))")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Rules applied to every model output

enum BriefingRules {
    /// Shortest step the plan will schedule. Matches `StudyCoach`'s rounding.
    static let stepGranularity = 5
    static let maximumSteps = 6
    static let maximumActionLength = 60
    static let maximumCaptainLength = 200

    /// Cleans a line of model text into the owner's house style: straight
    /// whitespace, no wrapping quotes, no em or en dashes, no exclamation marks.
    static func tidy(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "\u{2014}", with: ", ")
            .replacingOccurrences(of: "\u{2013}", with: ", ")
            .replacingOccurrences(of: "!", with: ".")
        result = result.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        result = result.replacingOccurrences(of: " ,", with: ",")
        result = result.replacingOccurrences(of: ",,", with: ",")
        let wrappers = CharacterSet(charactersIn: "\"'\u{201C}\u{201D}\u{2018}\u{2019}` ")
        return result.trimmingCharacters(in: wrappers)
    }

    /// Every run of digits in `text` must also appear in one of `sources`.
    /// This is the rule that answers the study coach's failure: a model that
    /// writes "problems 1 to 10" for a bag that says "problem set" has made
    /// the numbers up, and the whole line goes.
    static func numbersAreGrounded(_ text: String, in sources: [String]) -> Bool {
        let allowed = Set(sources.flatMap(digitRuns))
        return digitRuns(in: text).allSatisfy(allowed.contains)
    }

    static func digitRuns(in text: String) -> [String] {
        var runs: [String] = []
        var current = ""
        for character in text {
            if character.isASCII, character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                runs.append(current)
                current = ""
            }
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    /// The note exists to be about the traveler's own work. The first real
    /// run on the simulator returned a stock cruise announcement that named
    /// no task at all, so a note that shares no word of four letters or more
    /// with any bag is dropped, and the recorded PA carries the flight alone.
    static func mentionsABag(_ text: String, bags: [String]) -> Bool {
        let lineWords = Set(words(in: text))
        return bags.contains { bag in words(in: bag).contains(where: lineWords.contains) }
    }

    /// Lowercased words of four letters or more, with a plural "s" dropped so
    /// "problems" matches "problem".
    static func words(in text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter }
            .map(String.init)
            .filter { $0.count >= 4 }
            .map { $0.count > 4 && $0.hasSuffix("s") ? String($0.dropLast()) : $0 }
    }

    static func containsEmoji(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.properties.isEmojiPresentation }
    }

    /// The captain's note, or `nil` when it breaks a rule. `nil` means the
    /// flight carries on with its recorded announcements and nothing else.
    static func captainLine(_ raw: String, request: BriefingRequest) -> String? {
        var line = tidy(raw)
        // A model sometimes signs the announcement; the card already says who
        // it is from.
        for prefix in ["Captain:", "Captain here:", "PA:"] where line.hasPrefix(prefix) {
            line = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        guard !line.isEmpty,
              line.count <= maximumCaptainLength,
              !containsEmoji(line),
              !line.localizedCaseInsensitiveContains("ladies and gentlemen"),
              numbersAreGrounded(line, in: request.bags),
              mentionsABag(line, bags: request.bags)
        else { return nil }
        if let last = line.last, !".?".contains(last) { line.append(".") }
        return line
    }

    /// Turns model drafts into a plan that fits the cruise window exactly, or
    /// `nil` when nothing usable came back.
    ///
    /// The model proposes the steps and a rough weight for each; the minutes
    /// on screen are arithmetic. Weights are scaled to the window, rounded to
    /// five, and the last step takes the remainder, so the plan always ends at
    /// the top of descent.
    static func plan(from drafts: [DraftStep], request: BriefingRequest) -> FlightPlan? {
        guard !request.bags.isEmpty else { return nil }

        var kept: [(bag: Int, action: String, weight: Int)] = []
        var seen = Set<String>()
        for draft in drafts {
            let bag = draft.bag - 1
            guard request.bags.indices.contains(bag) else { continue }
            let action = tidy(draft.action).trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard !action.isEmpty,
                  action.count <= maximumActionLength,
                  !containsEmoji(action),
                  numbersAreGrounded(action, in: [request.bags[bag]]),
                  // A step that shares no word with its own bag is about
                  // something else: an echoed example, or another bag.
                  mentionsABag(action, bags: [request.bags[bag]]),
                  seen.insert(action.lowercased()).inserted
            else { continue }
            kept.append((bag, action, max(1, draft.minutes)))
        }

        // Every bag the traveler packed stays in the plan, in their words when
        // the model dropped it.
        let averageWeight = kept.isEmpty ? 30 : kept.map(\.weight).reduce(0, +) / kept.count
        for bag in request.bags.indices where !kept.contains(where: { $0.bag == bag }) {
            kept.append((bag, request.bags[bag], averageWeight))
        }
        // Nothing the model wrote survived: that is not a plan, it is the bag
        // list the traveler already has.
        guard kept.contains(where: { $0.action != request.bags[$0.bag] }) else { return nil }

        let fit = min(maximumSteps, request.cruiseMinutes / stepGranularity)
        guard fit >= 1 else { return nil }
        let chosen = Array(kept.prefix(fit))

        let total = request.cruiseMinutes
        let weightSum = max(1, chosen.map(\.weight).reduce(0, +))
        var steps: [FlightPlan.Step] = []
        var start = 0
        for (index, item) in chosen.enumerated() {
            let remainingSteps = chosen.count - index - 1
            let minutes: Int
            if remainingSteps == 0 {
                minutes = total - start
            } else {
                let share = Double(total) * Double(item.weight) / Double(weightSum)
                let rounded = Int((share / Double(stepGranularity)).rounded()) * stepGranularity
                // Leave at least one granule for each step still to come.
                let ceiling = total - start - remainingSteps * stepGranularity
                minutes = min(max(stepGranularity, rounded), ceiling)
            }
            steps.append(FlightPlan.Step(index: index, bag: item.bag, action: item.action,
                                         startMinute: start, minutes: minutes))
            start += minutes
        }
        return FlightPlan(steps: steps)
    }
}

// MARK: - Live state for one leg

/// Owns the briefing for the leg on screen. Created by `InFlightView`, fed
/// the session's clock readings, and never read by `FlightSession`: nothing
/// about takeoff, diversion, landing or the logbook waits on it.
@MainActor
@Observable
final class FlightBriefing {
    enum Status: Equatable {
        case idle
        case preparing
        case finished
        /// No service: below iOS 26, Apple Intelligence off or not ready,
        /// the traveler switched it off, or no bags were packed.
        case unavailable
    }

    /// How long the captain's note stays on screen. The cabin service card's
    /// 90 seconds (`CabinServicePlanner.cueDuration`), for the same reason:
    /// gone well before anything else wants the space.
    static let captainNoteDuration: TimeInterval = CabinServicePlanner.cueDuration

    /// Error cases only in release. Model text (which contains the traveler's
    /// bags) is logged in DEBUG builds only.
    private static let logger = Logger(subsystem: "com.patrickliu.voyage", category: "briefing")

    let request: BriefingRequest
    private let service: FlightBriefingService?

    private(set) var status: Status = .idle
    private(set) var plan: FlightPlan?
    private(set) var captainLine: String?
    /// Why the plan or the note did not arrive, for tests and logs.
    private(set) var lastError: BriefingError?

    /// When the note first went up, on the session's clock.
    private(set) var captainShownAt: Date?
    private(set) var captainDismissed = false
    private(set) var isCaptainNoteVisible = false

    init(request: BriefingRequest, service: FlightBriefingService?) {
        self.request = request
        self.service = service
    }

    func prewarm() {
        guard let service, !request.bags.isEmpty else { return }
        service.prewarm()
    }

    /// Asks for the plan, then the note. Safe to call more than once; only the
    /// first call does anything. Never throws: a failure leaves the flight
    /// exactly as it is without Apple Intelligence.
    func prepare() async {
        guard status == .idle else { return }
        guard let service, !request.bags.isEmpty, request.cruiseMinutes >= BriefingRules.stepGranularity else {
            status = .unavailable
            return
        }
        status = .preparing

        do {
            let drafts = try await service.draftPlan(for: request)
            plan = BriefingRules.plan(from: drafts, request: request)
            if plan == nil { lastError = .invalidOutput }
            #if DEBUG
            Self.logger.debug("plan drafts: \(String(describing: drafts), privacy: .public) kept: \(self.plan?.steps.count ?? 0, privacy: .public)")
            #endif
        } catch {
            lastError = Self.briefingError(from: error)
            Self.logger.info("plan failed: \(String(describing: self.lastError), privacy: .public)")
        }

        let firstStep = plan?.steps.first?.action ?? request.bags[0]
        do {
            let raw = try await service.captainLine(for: request, firstStep: firstStep)
            captainLine = BriefingRules.captainLine(raw, request: request)
            if captainLine == nil { lastError = .invalidOutput }
            #if DEBUG
            Self.logger.debug("captain raw: \(raw, privacy: .public) kept: \(self.captainLine != nil, privacy: .public)")
            #endif
        } catch {
            lastError = Self.briefingError(from: error)
            Self.logger.info("captain failed: \(String(describing: self.lastError), privacy: .public)")
        }
        status = .finished
    }

    /// Called on every session tick with the session's own phase and clock,
    /// so a `ManualClock` test drives it exactly as a live flight does.
    func update(phase: LegPhase, now: Date) {
        if captainShownAt == nil, !captainDismissed, captainLine != nil, phase == .cruise {
            captainShownAt = now
        }
        let visible = Self.captainNoteVisible(shownAt: captainShownAt, now: now,
                                              phase: phase, dismissed: captainDismissed)
        if visible != isCaptainNoteVisible { isCaptainNoteVisible = visible }
    }

    func dismissCaptainNote() {
        captainDismissed = true
        isCaptainNoteVisible = false
    }

    /// Up for 90 seconds from the moment it first showed, and only in cruise.
    nonisolated static func captainNoteVisible(shownAt: Date?, now: Date,
                                               phase: LegPhase, dismissed: Bool) -> Bool {
        guard let shownAt, !dismissed, phase == .cruise else { return false }
        return now >= shownAt && now < shownAt.addingTimeInterval(captainNoteDuration)
    }

    nonisolated static func briefingError(from error: Error) -> BriefingError {
        if let briefing = error as? BriefingError { return briefing }
        if error is CancellationError { return .cancelled }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), let mapped = FoundationModelsBriefingService.map(error) {
            return mapped
        }
        #endif
        return .unknown
    }
}

// MARK: - Factory

/// The only way production code gets a service. Returns `nil` whenever the
/// answer should be "the flight as it is today".
enum BriefingServiceFactory {
    static func make(settings: SettingsStore = .shared,
                     processInfo: ProcessInfo = .processInfo) -> FlightBriefingService? {
        // Unit tests never reach the real model; they build a fake directly.
        guard processInfo.environment["XCTestConfigurationFilePath"] == nil else { return nil }
        #if DEBUG
        // QA only: a canned service so a simulator without Apple Intelligence
        // can still photograph the plan and the note. Never in a release build.
        if processInfo.arguments.contains("-VoyageBriefingDemo") {
            return DemoBriefingService()
        }
        #endif
        guard settings.onDeviceIntelligenceEnabled else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), IntelligenceAvailability.current == .available {
            return FoundationModelsBriefingService()
        }
        #endif
        return nil
    }
}

// MARK: - Availability, for Settings

/// `SystemLanguageModel.Availability` flattened into a type iOS 17 can hold.
/// Each unavailable reason gets its own sentence, as Apple's trip planner
/// sample does in Views/Itinerary/TripPlanningView.swift.
enum IntelligenceAvailability: Equatable {
    case available
    case requiresNewerSystem
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unsupportedLanguage
    case unavailable

    static var current: IntelligenceAvailability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return FoundationModelsBriefingService.availability
        }
        #endif
        return .requiresNewerSystem
    }

    /// Whether Settings should offer the switch at all. A device that can
    /// never run the model is not shown a control that does nothing.
    var offersSetting: Bool {
        switch self {
        case .requiresNewerSystem, .deviceNotEligible: return false
        default: return true
        }
    }

    var settingsFootnote: String {
        switch self {
        case .available:
            return "Apple Intelligence splits your bags into steps that fit the flight, and the captain says one line about them at cruise. It runs on this iPhone. Your bags are not sent anywhere."
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in the Settings app to get a flight plan and a note from the captain. Flights work the same without it."
        case .modelNotReady:
            return "Apple Intelligence is still downloading. Flights work the same until it is ready."
        case .unsupportedLanguage:
            return "Apple Intelligence does not support this iPhone's language yet. Flights work the same without it."
        case .requiresNewerSystem, .deviceNotEligible, .unavailable:
            return "Apple Intelligence is not available right now. Flights work the same without it."
        }
    }
}

#if DEBUG
/// Canned answers for `-VoyageBriefingDemo`. Built from the request's own
/// bags so the capture shows what the rules do to real input.
struct DemoBriefingService: FlightBriefingService {
    func prewarm() {}

    func draftPlan(for request: BriefingRequest) async throws -> [DraftStep] {
        try await Task.sleep(for: .milliseconds(600))
        return request.bags.enumerated().flatMap { index, bag in
            [DraftStep(bag: index + 1, action: "First pass: \(bag)", minutes: 20),
             DraftStep(bag: index + 1, action: "Check it over: \(bag)", minutes: 10)]
        }
    }

    func captainLine(for request: BriefingRequest, firstStep: String) async throws -> String {
        "We're level on the way to \(request.destinationCity), and the cabin is quiet. \(request.bags[0]) is first."
    }
}
#endif
