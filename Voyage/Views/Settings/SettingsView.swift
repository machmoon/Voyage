import SwiftUI
import AVFoundation

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings = SettingsStore.shared

    /// Installed English voices, best first (same ranking the PA uses).
    private var paVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") && !$0.identifier.contains("speech.synthesis") }
            .sorted { lhs, rhs in
                if lhs.quality != rhs.quality { return lhs.quality.rawValue > rhs.quality.rawValue }
                return lhs.name < rhs.name
            }
    }

    private func voiceLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        let quality: String
        switch voice.quality {
        case .premium: quality = " · Premium"
        case .enhanced: quality = " · Enhanced"
        default: quality = ""
        }
        return "\(voice.name)\(quality)"
    }

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
                    Picker(selection: Binding(
                        get: { settings.paVoiceIdentifier ?? "auto" },
                        set: { settings.paVoiceIdentifier = $0 == "auto" ? nil : $0 }
                    )) {
                        Text("Automatic (best installed)").tag("auto")
                        ForEach(paVoices, id: \.identifier) { voice in
                            Text(voiceLabel(voice)).tag(voice.identifier)
                        }
                    } label: {
                        Label("PA voice", systemImage: "person.wave.2.fill")
                    }
                } header: {
                    Text("Sound")
                } footer: {
                    Text("Engine rumble is generated live — no loops, no downloads. For the best PA, download a Siri or Enhanced voice in iOS Settings → Accessibility → Spoken Content → Voices; Voyage will pick it up automatically.")
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
