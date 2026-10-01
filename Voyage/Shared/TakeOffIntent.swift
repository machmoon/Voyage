import AppIntents
import Foundation

/// The Home Screen widget's one button. Compiled into both the app and the
/// widget extension: the widget needs the type to build `Button(intent:)`, and
/// with `openAppWhenRun` the system performs it in the app, which is where a
/// flight can start. Shape follows apple/sample-backyard-birds
/// `Widgets/Backyard/ResupplyBackyardIntent.swift` (an `AppIntent` the widget
/// button runs, with an empty `init()`), plus `openAppWhenRun` because a
/// Voyage flight is a full-screen session that cannot run in the background.
struct TakeOffIntent: AppIntent {
    static var title: LocalizedStringResource = "Take off"
    static var description = IntentDescription("Start a focus flight on your usual route.")
    static var openAppWhenRun = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        TakeOffRequest.post()
        NotificationCenter.default.post(name: TakeOffRequest.notification, object: nil)
        return .result()
    }
}
