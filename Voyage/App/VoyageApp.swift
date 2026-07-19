import SwiftUI
import SwiftData

@main
struct VoyageApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: LogbookEntry.self)
    }
}
