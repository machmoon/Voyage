import SwiftUI

/// Shown wherever the logbook is read when the on-disk store failed to open
/// (`VoyageApp.logbookIsEphemeral`). The app keeps working on an in-memory
/// store, but nothing from this launch survives a quit, and the traveler
/// deserves to know that before flying for an hour.
struct LogbookStorageWarning: View {
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text("Logbook can't be saved")
                    .font(.subheadline.weight(.semibold))
                Text("Voyage could not open its storage on this device. Flights you complete now will be gone after you quit the app. Restarting your phone or freeing up space usually fixes this.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.destructive)
        }
        .accessibilityElement(children: .combine)
    }
}
