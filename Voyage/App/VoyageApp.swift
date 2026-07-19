import SwiftUI
import SwiftData

@main
struct VoyageApp: App {
    private let modelContainer: ModelContainer

    init() {
        modelContainer = Self.makeContainer()
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
        do {
            let support = URL.applicationSupportDirectory.appending(path: "Voyage", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            let config = ModelConfiguration(url: support.appending(path: "Logbook.store"))
            return try ModelContainer(for: LogbookEntry.self, configurations: config)
        } catch {
            // Still launch — persistence is important but never worth a crash on open.
            let fallback = ModelConfiguration(isStoredInMemoryOnly: true)
            return try! ModelContainer(for: LogbookEntry.self, configurations: fallback)
        }
    }
}
