import SwiftUI
import UIKit
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

    /// True when at least one downloaded voice is installed. iOS ships only
    /// the compact voices; the good ones arrive when the user downloads them,
    /// and no API lets an app fetch them on the user's behalf.
    private var hasDownloadedVoice: Bool {
        paVoices.contains { voice in
            voice.quality != .default
                || voice.identifier.lowercased().contains("siri")
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

                    if !hasDownloadedVoice {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Only the compact voice is installed",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.orange)
                            Text("The PA falls back to the voice iOS ships with, which sounds synthetic. Download one in Settings, Accessibility, Spoken Content, Voices, English. Samantha (Enhanced) is a good pick for cabin crew. Voyage uses it the next time you fly.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Open iOS Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .font(.caption.weight(.semibold))
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Sound")
                } footer: {
                    Text("Engine rumble is generated live, with no loops and no downloads. Announcements are marked up for delivery, so the PA pauses where a real one would. For the best result, download a Siri or Enhanced voice in iOS Settings, Accessibility, Spoken Content, Voices. Voyage picks it up automatically.")
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
                    if let licence = WeatherSource.openMeteo.legalURL {
                        Link(destination: licence) {
                            Label("Weather by Open-Meteo", systemImage: "cloud.sun.fill")
                        }
                    }
                } header: {
                    Text("Weather data")
                } footer: {
                    Text("Window scenery and cabin announcements follow the real weather along your route, supplied by Open-Meteo. Tap for its licence (CC BY 4.0).")
                }

                Section {
                    LabeledContent("Version", value: "1.0")
                    LabeledContent("Airline", value: Airline.name)
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
