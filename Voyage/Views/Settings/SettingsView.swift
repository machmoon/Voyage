import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings = SettingsStore.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: Binding(
                        get: { settings.ambienceEnabled },
                        set: { settings.ambienceEnabled = $0; if !$0 { CabinAudioEngine.shared.stopAmbience() } }
                    )) {
                        Label("Cabin ambience", systemImage: "speaker.wave.2.fill")
                    }
                    Toggle(isOn: Binding(
                        get: { settings.announcementsEnabled },
                        set: { settings.announcementsEnabled = $0; if !$0 { Announcer.shared.stop() } }
                    )) {
                        Label("PA announcements", systemImage: "megaphone.fill")
                    }
                } header: {
                    Text("Sound")
                } footer: {
                    Text("Engine rumble is generated live — no loops, no downloads. Announcements come from your captain and cabin crew.")
                }

                Section {
                    Picker(selection: Binding(
                        get: { settings.originOverrideCode ?? "auto" },
                        set: { settings.originOverrideCode = $0 == "auto" ? nil : $0 }
                    )) {
                        Text("Nearest airport (\(Airport.byCode(settings.resolvedOriginCode).code))")
                            .tag("auto")
                        ForEach(Airport.all) { airport in
                            Text("\(airport.code) · \(airport.city)").tag(airport.code)
                        }
                    } label: {
                        Label("Home airport", systemImage: "house.fill")
                    }
                } header: {
                    Text("Origin")
                } footer: {
                    Text("Your home airport determines which routes are 2-hour short-hauls and which are 6-hour long-hauls with a lounge connection.")
                }

                Section {
                    LabeledContent("Version", value: "1.0")
                    LabeledContent("Airline", value: "Voyage Air")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
