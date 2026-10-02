import Foundation

/// The copy for the end of a flight: the one upbeat line on the "Landed"
/// curtain, and the captions that rotate under the countdown on the way down.
///
/// Shaped on Gemini CLI's loading phrases, the open-source cousin of Claude
/// Code's spinner verbs (google-gemini/gemini-cli at c9096a8, Apache-2.0):
/// a flat list of short lines in one file
/// (`packages/cli/src/ui/constants/wittyPhrases.ts`) and a cycler that swaps
/// one line at a time on a fixed interval, filtered to a maximum length
/// (`packages/cli/src/ui/hooks/usePhraseCycler.ts`, `maxLength`,
/// `WITTY_PHRASE_CHANGE_INTERVAL_MS`). One deviation, stated: Gemini CLI draws
/// uniformly and can repeat itself; `PhraseRotation` never repeats any of the
/// last few lines, and the landed line remembers them across flights the way
/// `HomeGreeting` remembers the last greeting across launches.
///
/// House rules for the copy: positive, at most `maxLength` characters, no
/// emoji, no em-dashes (the `HomeGreeting` rule).
enum LandingPhrases {
    /// Longest line any pool may hold; long enough for a joke, short enough to
    /// sit on one line at the largest headline size on the smallest phone.
    static let maxLength = 40

    /// How many recent lines a rotation refuses to repeat.
    static let memory = 3

    /// Seconds each approach caption stays up before the next one fades in.
    static let captionInterval: TimeInterval = 8

    /// One of these is said on the "Landed" curtain.
    static let landed: [String] = [
        "Time to deplane!",
        "Wheels down, brain up.",
        "Smooth landing, captain.",
        "Seatbelt sign is off.",
        "Cabin crew, prepare for applause.",
        "You flew that focus.",
        "Gate's open. So are your options.",
        "Your thoughts are in the overhead bin.",
        "Butter-smooth touchdown.",
        "That's a greaser. Nice.",
        "Welcome to the other side of focus.",
        "Local time: proud o'clock.",
        "Arrived on time. Obviously.",
        "Taxiing to gate. Stretch those legs.",
        "Flight complete. Snack earned.",
        "Your focus arrived safely.",
        "You may now unbuckle your brain.",
        "Ding! Seatbelt sign off.",
        "Thank you for flying focused.",
        "Thanks for flying Voyage Air.",
        "Nailed the landing.",
        "Captain says: well done.",
        "Ground crew is cheering.",
        "On blocks. Engines off. Good work.",
        "Another stamp for the passport.",
        "That flight had your name on it.",
        "Stretch, sip water, feel great.",
        "Please remain proud until the gate.",
        "Landing gear and goals: down.",
        "Touchdown. Mic drop.",
        "Ten out of ten landing.",
        "Mission accomplished, pilot.",
        "The runway was impressed.",
        "Focus delivered to the gate.",
        "Flaps up, feet up.",
        "Deep breath. You did it.",
        "Clear skies, clear mind.",
        "Doors to manual. You're free.",
        "The tower says: great flight.",
        "Arrived. Ahead of schedule, in spirit."
    ]

    /// Under the countdown during `.descent`. The first line is the caption
    /// the phase always opened with, and still does.
    static let descent: [String] = [
        "Descending · start wrapping up",
        "Final approach · nearly there",
        "Flaps down · wrap it up",
        "Seatbelt sign on · last few lines",
        "Tray tables up · save your work",
        "On the glide path · finish strong"
    ]

    /// Under the countdown during `.landing`; the first line is the old one.
    static let landing: [String] = [
        "Landing",
        "Gear down · almost home",
        "Over the threshold",
        "Touchdown in moments"
    ]

    private static let recentLandedKey = "landedPhraseRecent"

    /// The landed line for this flight: random, never one of the last
    /// `memory` flights' lines, remembered across launches.
    static func nextLanded(defaults: UserDefaults = .standard) -> String {
        var generator = SystemRandomNumberGenerator()
        return nextLanded(defaults: defaults, using: &generator)
    }

    static func nextLanded<G: RandomNumberGenerator>(defaults: UserDefaults, using generator: inout G) -> String {
        let stored = defaults.stringArray(forKey: recentLandedKey) ?? []
        var rotation = PhraseRotation(pool: landed, memory: memory, recent: stored)
        let line = rotation.next(using: &generator)
        defaults.set(rotation.recent, forKey: recentLandedKey)
        return line
    }
}

/// Draws lines from a pool at random, never one of the last `memory` drawn.
struct PhraseRotation {
    let pool: [String]
    let memory: Int
    /// Oldest first. Lines no longer in the pool are dropped, so a copy edit
    /// cannot leave a stale entry blocking nothing.
    private(set) var recent: [String]

    init(pool: [String], memory: Int = LandingPhrases.memory, recent: [String] = []) {
        self.pool = pool
        // A pool of n can avoid at most n - 1 lines and still have a choice.
        self.memory = max(0, min(memory, pool.count - 1))
        self.recent = Array(recent.filter(pool.contains).suffix(self.memory))
    }

    mutating func next<G: RandomNumberGenerator>(using generator: inout G) -> String {
        let fresh = pool.filter { !recent.contains($0) }
        guard let line = (fresh.isEmpty ? pool : fresh).randomElement(using: &generator) else { return "" }
        remember(line)
        return line
    }

    mutating func next() -> String {
        var generator = SystemRandomNumberGenerator()
        return next(using: &generator)
    }

    /// Records a line shown by other means (a phase's fixed opening caption)
    /// so the rotation does not pick it again straight away.
    mutating func remember(_ line: String) {
        recent.append(line)
        if recent.count > memory { recent.removeFirst(recent.count - memory) }
    }
}
