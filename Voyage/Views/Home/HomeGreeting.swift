import Foundation

/// The Home screen greets you with a different line every time it opens. The
/// pool leans playful and stays short: the destination cards underneath already
/// show each route's focus time, so the greeting does not need to explain the
/// app. No em-dashes: the copy reads like plain documentation.
enum HomeGreeting {
    static let lines: [String] = [
        "Where to today?",
        "Pick a runway.",
        "Ready when you are.",
        "Somewhere far today?",
        "Clear skies ahead.",
        "Let's fly.",
        "Chasing a horizon?",
        "Time to lock in.",
        "Window seat or aisle?",
        "Good to see you.",
        "Boarding at your leisure.",
        "Make it count.",
        "Wheels up when you are.",
        "The world is open."
    ]

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
