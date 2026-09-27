import XCTest
@testable import Voyage

/// The on-device briefing, tested entirely against a fake. Nothing here
/// touches FoundationModels, and `BriefingServiceFactory` refuses to hand out
/// the real service under XCTest.
@MainActor
final class FlightBriefingTests: XCTestCase {

    private let request = BriefingRequest(
        bags: ["Finish problem set 4", "Read chapter 9"],
        originCity: "San Francisco",
        destinationCity: "Denver",
        cruiseMinutes: 90
    )

    // MARK: Fake

    private struct FakeService: FlightBriefingService {
        var drafts: Result<[DraftStep], Error> = .success([])
        var line: Result<String, Error> = .success("")

        func prewarm() {}
        func draftPlan(for request: BriefingRequest) async throws -> [DraftStep] { try drafts.get() }
        func captainLine(for request: BriefingRequest, firstStep: String) async throws -> String { try line.get() }
    }

    // MARK: Request

    func testRequestTrimsDropsEmptyBagsAndCapsAtThree() {
        let request = BriefingRequest(bags: ["  Essay intro ", "", "   ", "A", "B", "C"],
                                      originCity: "Boston", destinationCity: "Miami",
                                      cruiseMinutes: 120)
        XCTAssertEqual(request.bags, ["Essay intro", "A", "B"])
    }

    func testRequestCapsLongBagsForTheContextWindow() {
        let long = String(repeating: "x", count: 500)
        let request = BriefingRequest(bags: [long], originCity: "", destinationCity: "", cruiseMinutes: 60)
        XCTAssertEqual(request.bags.first?.count, BriefingRequest.maximumBagLength)
    }

    // MARK: Prompts

    func testPlanPromptCarriesOneBagAsDataAndTheWindow() {
        XCTAssertEqual(BriefingPrompts.planPrompt(forBag: "Read chapter 9", cruiseMinutes: 90),
                       "Task: Read chapter 9\nTime for all of today's tasks: 90 minutes.")
    }

    func testInstructionsNeverContainTheTravelersWords() {
        // Firefox's separation: rules in instructions, user text only in the prompt.
        for bag in request.bags {
            XCTAssertFalse(BriefingPrompts.planInstructions.contains(bag))
            XCTAssertFalse(BriefingPrompts.captainInstructions.contains(bag))
        }
        XCTAssertTrue(BriefingPrompts.planInstructions.contains("Never add"))
        XCTAssertTrue(BriefingPrompts.captainInstructions.contains("Do not use numbers"))
    }

    func testCaptainPromptNamesTheDestinationFirstTaskAndTheRest() {
        let prompt = BriefingPrompts.captainPrompt(for: request, firstStep: "Problem set 4, first half")
        XCTAssertEqual(prompt, """
        Flying from: San Francisco
        Flying to: Denver
        First task: Problem set 4, first half
        Also packed: Read chapter 9
        """)
    }

    // MARK: Captain's note rules

    func testCaptainLineIsTidiedIntoHouseStyle() {
        let line = BriefingRules.captainLine("\"Captain: We're at cruise to Denver \u{2014} first up, problem set 4!\"",
                                             request: request)
        XCTAssertEqual(line, "We're at cruise to Denver, first up, problem set 4.")
    }

    func testCaptainLineWithInventedNumbersIsDropped() {
        // "45 minutes" is not in the traveler's words.
        XCTAssertNil(BriefingRules.captainLine("About 45 minutes to Denver.", request: request))
        // "4" and "9" are.
        XCTAssertNotNil(BriefingRules.captainLine("Set 4 now, chapter 9 after.", request: request))
    }

    func testCaptainLineRejectsEmojiEmptyAndOverlong() {
        XCTAssertNil(BriefingRules.captainLine("Welcome aboard \u{2708}\u{FE0F}\u{1F600}", request: request))
        XCTAssertNil(BriefingRules.captainLine("   ", request: request))
        XCTAssertNil(BriefingRules.captainLine(String(repeating: "Cruising. ", count: 30), request: request))
    }

    /// The first real simulator run returned exactly this kind of line.
    func testStockAnnouncementThatNamesNoBagIsDropped() {
        XCTAssertNil(BriefingRules.captainLine(
            "Ladies and gentlemen, we are now cruising at cruising altitude. Our destination is Denver.",
            request: request))
        XCTAssertNil(BriefingRules.captainLine("We're level on the way to Denver.", request: request))
        XCTAssertNotNil(BriefingRules.captainLine("We're level on the way to Denver. Your reading is first.",
                                                  request: BriefingRequest(bags: ["Reading for seminar"],
                                                                           originCity: "", destinationCity: "Denver",
                                                                           cruiseMinutes: 60)))
    }

    /// The note that was dropped on the simulator: a whole cruise announcement
    /// over several lines, with invented numbers around the useful sentence.
    func testMultiLineAnnouncementKeepsTheSentenceAboutTheWork() {
        let raw = """
        Good afternoon, this is your captain speaking.
        We've reached our cruising altitude of 35,000 feet and should arrive in Denver in about 2 hours.
        Your first task is problem set 4, first half. Enjoy the flight!
        """
        XCTAssertEqual(BriefingRules.captainLine(raw, request: request),
                       "Your first task is problem set 4, first half. Enjoy the flight.")
    }

    func testGreetingBeforeTheTaskIsKept() {
        XCTAssertEqual(BriefingRules.captainLine("We're level over the Rockies. Problem set 4 is first.",
                                                 request: request),
                       "We're level over the Rockies. Problem set 4 is first.")
    }

    func testDigitRunsAreWholeNumbers() {
        XCTAssertEqual(BriefingRules.digitRuns(in: "pages 12-140, set 4"), ["12", "140", "4"])
        // "14" is not grounded by "140".
        XCTAssertFalse(BriefingRules.numbersAreGrounded("page 14", in: ["pages 140"]))
    }

    // MARK: Plan rules and sizing

    func testPlanFitsTheCruiseWindowExactlyInFiveMinuteSteps() throws {
        let drafts = [
            DraftStep(bag: 1, action: "Warm up on problem set 4", minutes: 20),
            DraftStep(bag: 1, action: "Work the hard problems in set 4", minutes: 40),
            DraftStep(bag: 2, action: "Read chapter 9", minutes: 30),
        ]
        let plan = try XCTUnwrap(BriefingRules.plan(from: drafts, request: request))
        XCTAssertEqual(plan.steps.map(\.minutes), [20, 40, 30])
        XCTAssertEqual(plan.steps.map(\.startMinute), [0, 20, 60])
        XCTAssertEqual(plan.totalMinutes, 90)
        XCTAssertTrue(plan.steps.dropLast().allSatisfy { $0.minutes % 5 == 0 })
    }

    func testModelMinutesAreOnlyWeights() throws {
        // The model thinks this takes six hours; the flight has ninety minutes.
        let drafts = [DraftStep(bag: 1, action: "Outline problem set 4", minutes: 180),
                      DraftStep(bag: 2, action: "Skim chapter 9", minutes: 180)]
        let plan = try XCTUnwrap(BriefingRules.plan(from: drafts, request: request))
        XCTAssertEqual(plan.steps.map(\.minutes), [45, 45])
    }

    func testStepsWithInventedNumbersAreDroppedAndTheBagComesBack() throws {
        let drafts = [
            DraftStep(bag: 1, action: "Problems 1 to 10", minutes: 30),   // invented
            DraftStep(bag: 2, action: "Summarize chapter 9", minutes: 30),
        ]
        let plan = try XCTUnwrap(BriefingRules.plan(from: drafts, request: request))
        XCTAssertEqual(plan.steps.map(\.action), ["Summarize chapter 9", "Finish problem set 4"])
        XCTAssertEqual(plan.steps.map(\.bag), [1, 0])
    }

    /// The drafts the on-device model returned on the simulator when the
    /// instructions carried a worked example: the example's essay steps filed
    /// under the problem-set bag, and a step from one bag filed under the other.
    func testStepsAboutSomethingElseAreDropped() throws {
        let drafts = [
            DraftStep(bag: 1, action: "Write the history essay", minutes: 15),
            DraftStep(bag: 1, action: "Outline the history essay", minutes: 10),
            DraftStep(bag: 2, action: "Read chapter 9", minutes: 20),
            DraftStep(bag: 2, action: "Summarize chapter 9", minutes: 10),
            DraftStep(bag: 2, action: "Review notes", minutes: 10),
            DraftStep(bag: 2, action: "Write summary of problem set 4", minutes: 20),
        ]
        let plan = try XCTUnwrap(BriefingRules.plan(from: drafts, request: request))
        XCTAssertEqual(plan.steps.map(\.action),
                       ["Read chapter 9", "Summarize chapter 9", "Finish problem set 4"])
    }

    /// The real on-device model on the simulator, 2026-09-27: the problem
    /// set lost its number, and chapter 9 grew five-minute filler steps.
    /// With those gone only the bag list is left, which is no plan at all:
    /// the flight keeps its bag tags.
    func testVagueParaphrasesAndFillerStepsAreDropped() {
        let drafts = [
            DraftStep(bag: 1, action: "Solve the problems", minutes: 50),
            DraftStep(bag: 2, action: "Open chapter 9", minutes: 5),
            DraftStep(bag: 2, action: "Read chapter 9", minutes: 20),
            DraftStep(bag: 2, action: "Close chapter 9", minutes: 5),
        ]
        XCTAssertNil(BriefingRules.plan(from: drafts, request: request))
    }

    func testAShortStepStaysWhenItIsTheBagsOnlyStep() throws {
        let drafts = [DraftStep(bag: 1, action: "Check problem set 4", minutes: 5),
                      DraftStep(bag: 2, action: "Skim chapter 9", minutes: 30)]
        let plan = try XCTUnwrap(BriefingRules.plan(from: drafts, request: request))
        XCTAssertEqual(plan.steps.map(\.action), ["Check problem set 4", "Skim chapter 9"])
    }

    func testKeepsTaskNeedsTheNumbersAndMostOfTheWords() {
        XCTAssertTrue(BriefingRules.keepsTask("First pass: Finish problem set 4", bag: "Finish problem set 4"))
        XCTAssertTrue(BriefingRules.keepsTask("Solve problem set 4", bag: "Finish problem set 4"))
        XCTAssertFalse(BriefingRules.keepsTask("Solve the problems", bag: "Finish problem set 4"))
        XCTAssertFalse(BriefingRules.keepsTask("Read chapter 10", bag: "Read chapter 9"))
        XCTAssertTrue(BriefingRules.keepsTask("Draft the history essay", bag: "Outline the history essay"))
        XCTAssertFalse(BriefingRules.keepsTask("Write an introduction", bag: "Outline the history essay"))
    }

    func testCaptainLineDropsAltitudeAndVagueTasks() {
        let raw = "You are now in cruising altitude. Your first task is to solve the problems."
        XCTAssertNil(BriefingRules.captainLine(raw, request: request))
        let good = "We're level on the way to Denver. Finish problem set 4 is first."
        XCTAssertEqual(BriefingRules.captainLine(good, request: request), good)
    }

    func testOutOfRangeBagsDuplicatesAndBlankActionsAreIgnored() throws {
        let drafts = [
            DraftStep(bag: 7, action: "Something else", minutes: 30),
            DraftStep(bag: 1, action: "Check answers for problem set 4", minutes: 30),
            DraftStep(bag: 1, action: "check answers for problem set 4.", minutes: 30),
            DraftStep(bag: 2, action: "  ", minutes: 30),
        ]
        let plan = try XCTUnwrap(BriefingRules.plan(from: drafts, request: request))
        XCTAssertEqual(plan.steps.map(\.action), ["Check answers for problem set 4", "Read chapter 9"])
    }

    func testNothingUsableIsNoPlan() {
        // Only invented numbers: the result would just be the bag list again.
        let drafts = [DraftStep(bag: 1, action: "Problems 1 to 10", minutes: 30)]
        XCTAssertNil(BriefingRules.plan(from: drafts, request: request))
        XCTAssertNil(BriefingRules.plan(from: [], request: request))
    }

    func testShortCruiseKeepsOnlyTheStepsThatFit() throws {
        let short = BriefingRequest(bags: request.bags, originCity: "", destinationCity: "", cruiseMinutes: 12)
        let drafts = [DraftStep(bag: 1, action: "Start problem set 4", minutes: 10),
                      DraftStep(bag: 1, action: "Finish set 4", minutes: 10),
                      DraftStep(bag: 2, action: "Skim chapter 9", minutes: 10)]
        let plan = try XCTUnwrap(BriefingRules.plan(from: drafts, request: short))
        XCTAssertEqual(plan.steps.count, 2)
        XCTAssertEqual(plan.totalMinutes, 12)
        XCTAssertNil(BriefingRules.plan(from: drafts, request: BriefingRequest(
            bags: request.bags, originCity: "", destinationCity: "", cruiseMinutes: 4)))
    }

    func testStepAtCruiseMinute() throws {
        let plan = try XCTUnwrap(BriefingRules.plan(from: [
            DraftStep(bag: 1, action: "Start problem set 4", minutes: 30),
            DraftStep(bag: 2, action: "Skim chapter 9", minutes: 60),
        ], request: request))
        XCTAssertEqual(plan.step(atCruiseMinute: -1)?.index, 0)
        XCTAssertEqual(plan.step(atCruiseMinute: 29.9)?.index, 0)
        XCTAssertEqual(plan.step(atCruiseMinute: 30)?.index, 1)
        XCTAssertEqual(plan.step(atCruiseMinute: 500)?.index, 1)
    }

    // MARK: Fallbacks

    func testNoServiceMeansTodaysFlight() async {
        let briefing = FlightBriefing(request: request, service: nil)
        await briefing.prepare()
        XCTAssertEqual(briefing.status, .unavailable)
        XCTAssertNil(briefing.plan)
        XCTAssertNil(briefing.captainLine)
    }

    func testNoBagsMeansNoRequestAtAll() async {
        let empty = BriefingRequest(bags: [], originCity: "A", destinationCity: "B", cruiseMinutes: 60)
        let briefing = FlightBriefing(request: empty, service: FakeService(line: .success("Hi.")))
        await briefing.prepare()
        XCTAssertEqual(briefing.status, .unavailable)
        XCTAssertNil(briefing.captainLine)
    }

    func testGuardrailOnThePlanStillAllowsTheNote() async {
        let service = FakeService(drafts: .failure(BriefingError.guardrail),
                                  line: .success("Cruising to Denver. First up, problem set 4."))
        let briefing = FlightBriefing(request: request, service: service)
        await briefing.prepare()
        XCTAssertNil(briefing.plan)
        XCTAssertEqual(briefing.captainLine, "Cruising to Denver. First up, problem set 4.")
        XCTAssertEqual(briefing.lastError, .guardrail)
        XCTAssertEqual(briefing.status, .finished)
    }

    func testEveryFailureEndsWithNothingOnScreen() async {
        let service = FakeService(drafts: .failure(CancellationError()),
                                  line: .failure(BriefingError.refusal))
        let briefing = FlightBriefing(request: request, service: service)
        await briefing.prepare()
        XCTAssertNil(briefing.plan)
        XCTAssertNil(briefing.captainLine)
        XCTAssertEqual(briefing.lastError, .refusal)
        briefing.update(phase: .cruise, now: Date())
        XCTAssertFalse(briefing.isCaptainNoteVisible)
    }

    func testUnknownErrorsMapToUnknown() {
        struct Other: Error {}
        XCTAssertEqual(FlightBriefing.briefingError(from: Other()), .unknown)
        XCTAssertEqual(FlightBriefing.briefingError(from: CancellationError()), .cancelled)
        XCTAssertEqual(FlightBriefing.briefingError(from: BriefingError.busy), .busy)
    }

    func testFactoryNeverHandsTestsTheRealModel() {
        XCTAssertNil(BriefingServiceFactory.make())
    }

    func testPrepareRunsOnce() async {
        let briefing = FlightBriefing(request: request, service: FakeService(line: .success("Cruising.")))
        await briefing.prepare()
        await briefing.prepare()
        XCTAssertEqual(briefing.status, .finished)
    }

    // MARK: Captain's note timing, on an injected clock

    func testCaptainNoteWaitsForCruiseThenStaysNinetySeconds() async {
        let clock = ManualClock()
        let briefing = FlightBriefing(request: request,
                                      service: FakeService(line: .success("Cruising to Denver. Problem set 4 is first.")))
        await briefing.prepare()

        briefing.update(phase: .climb, now: clock.now)
        XCTAssertFalse(briefing.isCaptainNoteVisible, "never during climb")

        clock.advance(by: 60)
        briefing.update(phase: .cruise, now: clock.now)
        XCTAssertTrue(briefing.isCaptainNoteVisible)

        clock.advance(by: 89)
        briefing.update(phase: .cruise, now: clock.now)
        XCTAssertTrue(briefing.isCaptainNoteVisible)

        clock.advance(by: 1)
        briefing.update(phase: .cruise, now: clock.now)
        XCTAssertFalse(briefing.isCaptainNoteVisible)
    }

    func testCaptainNoteLeavesAtDescentAndStaysDismissed() async {
        let clock = ManualClock()
        let briefing = FlightBriefing(request: request,
                                      service: FakeService(line: .success("Cruising to Denver. Problem set 4 is first.")))
        await briefing.prepare()
        briefing.update(phase: .cruise, now: clock.now)
        XCTAssertTrue(briefing.isCaptainNoteVisible)
        briefing.update(phase: .descent, now: clock.now)
        XCTAssertFalse(briefing.isCaptainNoteVisible)

        let second = FlightBriefing(request: request,
                                    service: FakeService(line: .success("Cruising to Denver. Problem set 4 is first.")))
        await second.prepare()
        second.update(phase: .cruise, now: clock.now)
        second.dismissCaptainNote()
        clock.advance(by: 1)
        second.update(phase: .cruise, now: clock.now)
        XCTAssertFalse(second.isCaptainNoteVisible)
    }

    // MARK: Settings copy

    func testEveryAvailabilityHasPlainCopyWithoutEmDashes() {
        let all: [IntelligenceAvailability] = [.available, .requiresNewerSystem, .deviceNotEligible,
                                               .appleIntelligenceNotEnabled, .modelNotReady,
                                               .unsupportedLanguage, .unavailable]
        for availability in all {
            XCTAssertFalse(availability.settingsFootnote.isEmpty)
            XCTAssertFalse(availability.settingsFootnote.contains("\u{2014}"))
        }
        XCTAssertFalse(IntelligenceAvailability.deviceNotEligible.offersSetting)
        XCTAssertFalse(IntelligenceAvailability.requiresNewerSystem.offersSetting)
        XCTAssertTrue(IntelligenceAvailability.appleIntelligenceNotEnabled.offersSetting)
    }
}
