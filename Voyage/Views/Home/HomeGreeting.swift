import Foundation

/// The Home screen greets you with a different line every time it opens. The
/// pool blends three registers on purpose: calm welcomes, a little wit, and a
/// push to start, so the rotation feels human instead of one scripted voice.
/// The fixed subtitle underneath carries the actual explanation, which frees
/// these to be short. No em-dashes: the copy reads like plain documentation.
enum HomeGreeting {
    static let lines: [String] = [
        "Where to today?",
        "Pick a place to focus.",
        "Ready when you are.",
        "Somewhere new today?",
        "Clear skies ahead.",
        "Let's fly.",
        "Chasing a horizon?",
        "Time to focus.",
        "Pick a runway.",
        "Good to see you.",
        "Window seat today?",
        "Make it count.",
        "Wheels up when you are.",
        "The world is open."
    ]

    /// The one line shown beneath the greeting. It stays put while the greeting
    /// rotates, so a first-time viewer always sees what tapping a place does.
    static let subtitle = "Pick a destination. Its real flight time becomes your focus session."

    private static let lastIndexKey = "homeGreetingLastIndex"

    /// A line chosen at random, never the one shown last launch, so two opens in
    /// a row never repeat. The chosen index is remembered across launches.
    static func next(defaults: UserDefaults = .standard) -> String {
        guard lines.count > 1 else { return lines.first ?? "" }
        let last = defaults.object(forKey: lastIndexKey) as? Int
        var index = Int.random(in: 0..<lines.count)
        if let last {
            // Re-roll off the previous line by walking a random step forward,
            // which is uniform over the remaining lines and never loops.
            while index == last { index = (index + Int.random(in: 1..<lines.count)) % lines.count }
        }
        defaults.set(index, forKey: lastIndexKey)
        return lines[index]
    }
}
