import UIKit

/// Central haptics helper — one generator per style, pre-warmed.
@MainActor
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notify = UINotificationFeedbackGenerator()

    static func prepare() {
        light.prepare(); medium.prepare(); heavy.prepare()
        rigid.prepare(); selection.prepare(); notify.prepare()
    }

    /// Seat taps, toggle flips.
    static func tap() { selection.selectionChanged() }

    /// Boarding-pass tear ratchet tick.
    static func ratchet() { rigid.impactOccurred(intensity: 0.6) }

    /// The pass finally rips free.
    static func rip() {
        heavy.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
            rigid.impactOccurred(intensity: 0.8)
        }
    }

    /// Landing-gear thunk (up after climb, down on approach).
    static func gearThunk() {
        heavy.impactOccurred(intensity: 0.9)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            medium.impactOccurred(intensity: 0.5)
        }
    }

    /// Main-gear touchdown, then nose gear.
    static func touchdown() {
        heavy.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            rigid.impactOccurred(intensity: 0.9)
        }
    }

    /// Passport stamp thunk.
    static func stamp() {
        heavy.impactOccurred(intensity: 1.0)
    }

    static func success() { notify.notificationOccurred(.success) }
    static func warning() { notify.notificationOccurred(.warning) }
    static func failure() { notify.notificationOccurred(.error) }
    static func softTick() { soft.impactOccurred(intensity: 0.4) }
}
