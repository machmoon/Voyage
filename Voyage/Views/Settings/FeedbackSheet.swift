import SwiftUI

/// The feedback sheet. The text never leaves the device on its own.
/// Tapping the button hands a prefilled issue to GitHub in Safari, where the
/// user posts it publicly under their own account.
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
                            Text(kind.issueTitlePrefix).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } header: {
                    Text("What's on your mind?")
                }

                Section {
                    TextField("Describe it here.", text: $message, axis: .vertical)
                        .lineLimit(5...12)
                        .focused($writing)
                } footer: {
                    Text("Voyage adds its version, your iOS version, and your device model so a report doesn't need a follow-up question.")
                }

                Section {
                    Button {
                        send()
                    } label: {
                        Label("Open GitHub", systemImage: "arrow.up.forward.app.fill")
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.7)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("This opens github.com/\(AppFeedback.repository) in your browser with the form already filled in. Nothing is sent until you press Submit there, and the issue is public and posted from your GitHub account.")
                }
            }
            .navigationTitle("Send feedback")
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

// Largest accessibility Dynamic Type. Verifies the "Open GitHub" button
// label scales/wraps instead of clipping at AX5.
#Preview("AX5") {
    FeedbackSheet()
        .environment(\.dynamicTypeSize, .accessibility5)
}
