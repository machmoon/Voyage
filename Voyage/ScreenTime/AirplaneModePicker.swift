import FamilyControls
import SwiftUI

extension View {
    /// Presents the Screen Time app picker and saves what is chosen.
    func airplaneModePicker(isPresented: Binding<Bool>) -> some View {
        modifier(AirplaneModePickerPresenter(isPresented: isPresented))
    }
}

/// "N apps blocked during flights", counting categories and websites as one
/// each, as the picker does.
enum AirplaneModeCopy {
    static func blockedLine(count: Int) -> String {
        count == 1 ? "1 app blocked during flights" : "\(count) apps blocked during flights"
    }
}


private struct AirplaneModePickerPresenter: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            AppPicker(isPresented: $isPresented)
        }
    }
}

/// Foqos's `AppPicker` (awaseem/foqos
/// `Foqos/Components/BlockedProfileView/AppPicker.swift` at 4f6864c, MIT):
/// `FamilyActivityPicker` in a NavigationStack, a refresh button that
/// rebuilds the picker, a count against Apple's 50-item limit in the title
/// and a check-mark Done. It also keeps Foqos's workaround for the iOS bug
/// where the picker's selection stops propagating: a clear text toggled
/// every second forces the view to update. Deviations: Done saves the
/// selection to the App Group (Foqos binds it to a profile draft), and
/// Cancel discards it.
private struct AppPicker: View {
    @Binding var isPresented: Bool

    @State private var selection = AirplaneModeSelectionStore.load()
    @State private var updateFlag = false
    @State private var refreshID = UUID()
    @State private var showLimitAlert = false
    private let stateUpdateTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var selectedCount: Int { AirplaneModeSelectionStore.count(selection) }
    private var isOverLimit: Bool { selectedCount > 50 }

    var body: some View {
        NavigationStack {
            ZStack {
                Text(verbatim: "Updating view state because of bug in iOS...")
                    .foregroundStyle(.clear)
                    .accessibilityHidden(true)
                    .opacity(updateFlag ? 1 : 0)

                FamilyActivityPicker(selection: $selection)
                    .id(refreshID)
            }
            .onReceive(stateUpdateTimer) { _ in updateFlag.toggle() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 5) {
                        Text("\(selectedCount)")
                            .fontWeight(.semibold)
                            .foregroundStyle(isOverLimit ? Color.red : Theme.accent)
                        Text("/ 50").foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    .monospacedDigit()
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(selectedCount) of 50 selected")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        if isOverLimit { showLimitAlert = true } else { save() }
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("Over Apple's 50-item limit", isPresented: $showLimitAlert) {
                Button("Keep choosing", role: .cancel) {}
                Button("Save anyway") { save() }
            } message: {
                Text("Screen Time blocks up to 50 apps, categories and websites. A category counts as one.")
            }
        }
    }

    private func save() {
        AirplaneModeSelectionStore.save(selection)
        AirplaneMode.shared.selectionDidChange()
        Haptics.success()
        isPresented = false
    }
}
