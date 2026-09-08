import Foundation

/// Cadence for in-flight wellness cues.
///
/// The structure is taken from stretchly's `app/breaksPlanner.js`
/// (hovancik/stretchly): a run of short cues with a longer one every Nth,
/// selected by `breakNumber % (breakInterval + 1) === 0`. `passNumber` is
/// their `breakNumber` and `serviceInterval` is their `breakInterval`, kept
/// under those roles so the arithmetic can be checked against theirs.
///
/// The skipped-cue accounting below follows safeeyes'
/// `plugins/healthstats/plugin.py`, which stores what you ignored as a plain
/// count (`skipped_breaks` against `breaks`) and never turns it into a
/// prompt. We keep the count and drop their unhealthy-ratio indicator: a
/// broken heart at a 20 percent skip rate is the scolding this feature is
/// supposed to avoid.
///
/// Two deviations from stretchly, both forced by the domain:
///
/// 1. `serviceInterval` is 2, not their 3. The eye-rest spacing here is fixed
///    at 20 minutes by the 20-20-20 convention, so the multiplier also decides
///    the stretch cadence. Their 3 would put the stretch at 80 minutes, past
///    the hour that sit-break guidance uses; 2 lands it on the hour.
/// 2. There is no `postponeCurrentBreak`. Postponing implies the cue is owed,
///    and nothing here is owed. An ignored cue expires on its own and is
///    counted, which is the safeeyes half of the design.
struct CabinServicePlanner: Equatable {

    /// What the cabin is offering. stretchly's microbreak/break split.
    enum Pass: Equatable {
        /// The 20-20-20 eye rest: every 20 minutes, 20 seconds looking at
        /// something 20 feet away. On this aircraft that is the horizon,
        /// which is the one thing the metaphor gives us for free.
        case eyeRest
        /// Out of the seat. Fires on the seatbelt sign, which is the moment a
        /// passenger is actually permitted to stand.
        case stretch
    }

    /// Seconds of cruise between cues. The 20 in 20-20-20.
    static let passInterval: TimeInterval = 20 * 60
    /// How long the cue asks for. The second 20.
    static let eyeRestSeconds: TimeInterval = 20
    /// How long a cue stays on screen before it expires unanswered. Chosen so
    /// an ignored cue is gone well before the next one arrives.
    static let cueDuration: TimeInterval = 90
    /// Short cues per long one. stretchly's `breakInterval`, see note above.
    static let serviceInterval = 2

    /// Cues offered so far on this flight. stretchly's `breakNumber`.
    private(set) var passNumber = 0
    /// Cues the traveller acted on. safeeyes' `breaks`.
    private(set) var taken = 0

    /// Cues that came and went unanswered. safeeyes' `skipped_breaks`.
    /// A number, never a judgement.
    var ignored: Int { max(0, passNumber - taken) }

    /// stretchly `breaksPlanner.js`: `breakNumber % breakInterval === 0`
    /// where `breakInterval = settings.get('breakInterval') + 1`.
    static func kind(forPass n: Int) -> Pass {
        let interval = serviceInterval + 1
        return n > 0 && n % interval == 0 ? .stretch : .eyeRest
    }

    /// Elapsed seconds into the leg at which pass `n` becomes due, measured
    /// from the top of cruise so climb is never interrupted.
    /// `interval` is a parameter rather than the constant so QA captures can
    /// compress it. The planner stays free of `ProcessInfo`; the launch
    /// argument lives on `FlightSession` beside the other QA flags.
    static func due(pass n: Int, cruiseBeginsAt: TimeInterval,
                    interval: TimeInterval = passInterval) -> TimeInterval {
        cruiseBeginsAt + TimeInterval(n) * interval
    }

    /// Records that a cue was shown. Returns what it should say.
    mutating func offer() -> Pass {
        passNumber += 1
        return Self.kind(forPass: passNumber)
    }

    /// The traveller acted on the cue. Nothing depends on this but the count.
    mutating func acknowledge() {
        taken = min(passNumber, taken + 1)
    }

    /// A new leg begins after a layover, and the lounge is a real break: you
    /// stand, you leave the seat, you look at something further than a screen.
    /// So the cadence restarts rather than carrying its debt into the next leg.
    mutating func reset() {
        passNumber = 0
        taken = 0
    }
}

extension CabinServicePlanner.Pass {

    /// The small caps line. Names the source of the message, the way a cabin
    /// announcement does.
    var eyebrow: String {
        switch self {
        case .eyeRest: return "FROM THE FLIGHT DECK"
        case .stretch: return "SEATBELT SIGN"
        }
    }

    /// An event in the cabin, not advice about your body. The July copy pass
    /// on this repo rewrote the old hydration card for exactly this reason:
    /// "Stay hydrated / You've been flying a while" nags from outside the
    /// world, so it became "Beverage service / The cart is at your row".
    var headline: String {
        switch self {
        case .eyeRest: return "Something to see out of the right side."
        case .stretch: return "The seatbelt sign is off."
        }
    }

    var detail: String {
        switch self {
        case .eyeRest:
            return "The horizon is the furthest thing on this aircraft. Twenty seconds on it rests the muscle that has been holding a page at arm's length for twenty minutes."
        case .stretch:
            return "You are free to move about the cabin. The flight keeps flying either way, and nothing is logged about whether you got up."
        }
    }

    /// The dismiss control. A plain past-tense fact, not a score.
    var action: String {
        switch self {
        case .eyeRest: return "Looked"
        case .stretch: return "Stood up"
        }
    }

    var systemImage: String {
        switch self {
        case .eyeRest: return "eye"
        case .stretch: return "figure.stand"
        }
    }
}
