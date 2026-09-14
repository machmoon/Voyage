import SwiftUI
import SwiftData
import os

@main
struct VoyageApp: App {
    private let modelContainer: ModelContainer
    /// True when the on-disk logbook could not be opened and the app is
    /// running on an in-memory store. Everything saved this launch is lost on
    /// quit, and the Logbook and Settings screens say so.
    static private(set) var logbookIsEphemeral = false

    init() {
        modelContainer = Self.makeContainer()
        // Starts the seven-day clock the review prompt waits on; a no-op after
        // the first launch of the install.
        MainActor.assumeIsolated { AppFeedback.stampFirstLaunchIfNeeded() }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
    }

    /// Ensures Application Support exists before opening the SwiftData store.
    /// Without this, the first launch can race CoreData against a missing directory.
    private static func makeContainer() -> ModelContainer {
        // `-VoyageRecorderDemo` swaps in an in-memory logbook so the flight
        // data recorder can be reviewed without flying twenty-two sessions.
        // In-memory on purpose: a demo launch cannot touch the real store.
        if RecorderDemoLogbook.isEnabled, let demo = try? RecorderDemoLogbook.makeContainer() {
            return demo
        }
        // `-VoyageEmptyLogbook`: a fresh in-memory logbook, for captures of
        // first-launch states on a simulator whose real store has history.
        if ProcessInfo.processInfo.arguments.contains("-VoyageEmptyLogbook"),
           let empty = try? ModelContainer(for: LogbookEntry.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true)) {
            return empty
        }
        do {
            let support = URL.applicationSupportDirectory.appending(path: "Voyage", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            let config = ModelConfiguration(url: support.appending(path: "Logbook.store"))
            return try ModelContainer(for: LogbookEntry.self, configurations: config)
        } catch {
            // Still launch — persistence is important but never worth a crash on
            // open. But say so: a silent in-memory store looks like a working
            // logbook that empties itself on every launch.
            Logger(subsystem: "com.patrickliu.voyage", category: "persistence")
                .fault("Logbook store failed to open, running in memory: \(error.localizedDescription, privacy: .public)")
            logbookIsEphemeral = true
            let fallback = ModelConfiguration(isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: LogbookEntry.self, configurations: fallback)
            } catch {
                fatalError("SwiftData cannot open even an in-memory store: \(error)")
            }
        }
    }
}
