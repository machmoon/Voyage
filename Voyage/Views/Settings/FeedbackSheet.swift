import SwiftUI

/// A note to the flight deck. The text never leaves the device on its own —
/// tapping the button hands a prefilled issue to GitHub in Safari, where the
/// traveler posts it publicly under their own account.
struct FeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var kind: AppFeedback.FeedbackKind = .broke
    @State private var message = ""
    @FocusState private var writing: Bool

    private var environmentFooter: String {
        AppFeedback.environmentFooter(systemVersion: UIDevice.current.systemVersion)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Kind", selection: $kind) {
                        ForEach(AppFeedback.FeedbackKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } header: {
                    Text("What's on your mind?")
                }

                Section {
                    TextField(kind.prompt, text: $message, axis: .vertical)
                        .lineLimit(5...12)
                        .focused($writing)
                } footer: {
                    Text("Voyage adds its version, your iOS version, and your device model so a report doesn't need a follow-up question.")
                }

                Section {
                    Button {
                        send()
                    } label: {
                        Label("Open GitHub to post it", systemImage: "arrow.up.forward.app.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("This opens github.com/\(AppFeedback.repository) in your browser with the form already filled in. Nothing is sent until you press Submit there, and the issue is public and posted from your GitHub account.")
                }
            }
            .navigationTitle("Talk to the flight deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func send() {
        guard let url = AppFeedback.issueURL(kind: kind, message: message, environment: environmentFooter) else { return }
        openURL(url)
        dismiss()
    }
}
