import SwiftUI
import UIKit

/// "Export logbook" and "Copy logbook": the two ways the Markdown export
/// leaves the device. Share is a `ShareLink` of a `String`, the same shape
/// as the receipt share in `ArrivalFlowView`; Copy puts the same text on
/// the pasteboard for a chat app the share sheet does not reach.
///
/// Two plain buttons rather than a custom control so the pair reads as
/// rows in a `Form` and as items in a `Menu` without a second layout.
struct LogbookExportButtons: View {
    let entries: [LogbookEntry]

    @State private var text = ""
    @State private var copied = false

    private struct LogbookKey: Equatable {
        let count: Int
        let lastDate: Date?
    }

    private var key: LogbookKey {
        LogbookKey(count: entries.count, lastDate: entries.map(\.date).max())
    }

    var body: some View {
        Group {
            ShareLink(item: text, subject: Text("Voyage logbook"),
                      preview: SharePreview("Voyage logbook")) {
                Label("Export logbook", systemImage: "square.and.arrow.up")
            }
            .disabled(text.isEmpty)
            .accessibilityIdentifier("export-logbook")

            Button {
                UIPasteboard.general.string = text
                Haptics.success()
                copied = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    copied = false
                }
            } label: {
                Label(copied ? "Copied" : "Copy logbook",
                      systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .disabled(text.isEmpty)
            .accessibilityIdentifier("copy-logbook")
        }
        // The export folds the recorder over the whole logbook, so it is
        // built once per change of the logbook rather than per body pass.
        .task(id: key) {
            text = LogbookExport.markdown(entries: entries, now: .now)
        }
    }
}
