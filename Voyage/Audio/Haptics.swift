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
        after(0.09) { rigid.impactOccurred(intensity: 0.8) }
    }

    /// Landing-gear thunk (up after climb, down on approach).
    static func gearThunk() {
        heavy.impactOccurred(intensity: 0.9)
        after(0.12) { medium.impactOccurred(intensity: 0.5) }
    }

    /// Main-gear touchdown, then nose gear.
    static func touchdown() {
        heavy.impactOccurred()
        after(0.35) { rigid.impactOccurred(intensity: 0.9) }
    }

    /// Runs a follow-up beat on the main actor after a delay.
    private static func after(_ seconds: Double, _ beat: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            beat()
        }
    }

    /// The passport stamp: contact, press, lift.
    ///
    /// This is the last physical beat of a session and the one the whole flight
    /// is spent earning, so it should be the richest thing the app does, not
    /// the thinnest. It used to be a single `heavy` impact, which made it the
    /// only one-beat event in a vocabulary where `rip`, `gearThunk` and
    /// `touchdown` are all two-beat: every lesser moment out-felt the payoff.
    ///
    /// Three beats over 160ms, shaped like a rubber die actually pressed by
    /// hand. The `medium` is the die meeting paper, the `heavy` is the weight
    /// going through it, and the light `rigid` is the hand coming off. The
    /// gaps are deliberately shorter than `rip`'s 90ms and `touchdown`'s 350ms:
    /// a stamp is one committed motion, not two separate arrivals, so the
    /// beats need to fuse into a single thunk rather than read as a sequence.
    static func stamp() {
        medium.impactOccurred(intensity: 0.55)
        after(0.05) { heavy.impactOccurred(intensity: 1.0) }
        after(0.16) { rigid.impactOccurred(intensity: 0.35) }
    }

    static func success() { notify.notificationOccurred(.success) }
    static func warning() { notify.notificationOccurred(.warning) }
    static func failure() { notify.notificationOccurred(.error) }
    static func softTick() { soft.impactOccurred(intensity: 0.4) }
}
