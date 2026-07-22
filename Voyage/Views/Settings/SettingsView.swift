import SwiftUI
import AVFoundation
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var settings = SettingsStore.shared
    @State private var hasSeededData = false

    /// Installed English voices, best first.
    private var paVoices: [AVSpeechSynthesisVoice] {
        Announcer.rankedEnglishVoices()
    }

    private func voiceLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        var parts = [voice.name]
        if Announcer.isSiriVoice(voice) {
            parts.append("Siri")
        }
        switch voice.quality {
        case .premium: parts.append("Premium")
        case .enhanced: parts.append("Enhanced")
        default: break
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: Binding(
                        get: { settings.soundEffectsEnabled },
                        set: { settings.soundEffectsEnabled = $0 }
                    )) {
                        Label("Sound cues", systemImage: "bell.and.waves.left.and.right.fill")
                    }
                    Toggle(isOn: Binding(
                        get: { settings.ambienceEnabled },
                        set: {
                            settings.ambienceEnabled = $0
                            if !$0 { CabinAudioEngine.shared.stopAmbience() }
                        }
                    )) {
                        Label("Cabin ambience", systemImage: "speaker.wave.2.fill")
                    }
                    Toggle(isOn: Binding(
                        get: { settings.announcementsEnabled },
                        set: { settings.announcementsEnabled = $0; if !$0 { Announcer.shared.stop() } }
                    )) {
                        Label("Spoken check-ins", systemImage: "waveform")
                    }

                    if settings.announcementsEnabled {
                        Picker(selection: Binding(
                            get: { settings.paVoiceIdentifier ?? PAVoice.default.rawValue },
                            set: { settings.paVoiceIdentifier = $0 }
                        )) {
                            Section("Voyage Air") {
                                ForEach(PAVoice.allCases) { voice in
                                    Text("\(voice.displayName) · \(voice.subtitle)")
                                        .tag(voice.rawValue)
                                }
                            }
                            Section("This device") {
                                ForEach(paVoices, id: \.identifier) { voice in
                                    Text(voiceLabel(voice)).tag(voice.identifier)
                                }
                            }
                        } label: {
                            Label("Voice", systemImage: "person.wave.2.fill")
                        }

                        Button {
                            Announcer.shared.previewSelectedVoice()
                        } label: {
                            Label("Preview voice", systemImage: "play.circle.fill")
                        }
                    }
                } header: {
                    Text("Sound")
                } footer: {
                    Text("Sound cues confirm meaningful moments without demanding attention. Ambience is generated privately on device and mixes with your music. The Voyage Air voices are recorded into the app, so announcements play in airplane mode and no audio leaves your device.")
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
                    Text("Your home airport determines the routes and focus durations on the globe.")
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { settings.cabinServiceEnabled },
                        set: { settings.cabinServiceEnabled = $0 }
                    )) {
                        Label("Beverage service", systemImage: "cup.and.saucer.fill")
                    }
                } header: {
                    Text("Cabin service")
                } footer: {
                    Text("During cruise the cart comes through every 25 minutes with a reminder to drink some water.")
                }

                Section {
                    Picker(selection: Binding(
                        get: { settings.windowWorldMode },
                        set: { settings.windowWorldMode = $0 }
                    )) {
                        ForEach(WindowWorldMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    } label: {
                        Label("Window view", systemImage: "airplane.departure")
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text("Window")
                } footer: {
                    Text(settings.windowWorldMode.caption)
                }

                Section {
                    LabeledContent("Grace period", value: "30 seconds")
                    LabeledContent("Penalty", value: "Flight diverted")
                } header: {
                    Text("Strict mode")
                } footer: {
                    Text("Leaving Voyage for more than 30 seconds ends the session. Completed legs still earn partial miles.")
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { settings.flightFocusRemindersEnabled },
                        set: { settings.flightFocusRemindersEnabled = $0 }
                    )) {
                        Label("Depart focus reminders", systemImage: "moon.fill")
                    }
                } header: {
                    Text("Flight Focus")
                } footer: {
                    Text("Add Voyage to an iOS Focus Filter, then enable that Focus before boarding. Voyage only asks for Focus access after you configure this integration.")
                }

                Section {
                    Button {
                        TestModeSeeder.seed(into: modelContext)
                        hasSeededData = true
                    } label: {
                        Label("Load demo history", systemImage: "wand.and.stars")
                    }
                    if hasSeededData {
                        Button(role: .destructive) {
                            TestModeSeeder.clear(from: modelContext)
                            hasSeededData = false
                        } label: {
                            Label("Clear logbook", systemImage: "trash")
                        }
                    }
                } header: {
                    Text("Test mode")
                } footer: {
                    Text("Fills the logbook with a few weeks of focus flights — an active streak, Gold status, and a well-stamped passport — so you can see the app as a returning traveler would. Replaces any existing history.")
                }

                Section {
                    LabeledContent("Version", value: "1.0")
                    LabeledContent("Airline", value: "Voyage Air")
                    LabeledContent("Window world", value: "Route-aware 3D")
                    LabeledContent("Cabin voice", value: "AI voice by ElevenLabs")
                    Link("Voyage Terms of Use", destination: URL(string: "https://github.com/machmoon/Voyage/blob/main/TERMS.md")!)
                    Link("Voyage Privacy Notice", destination: URL(string: "https://github.com/machmoon/Voyage/blob/main/PRIVACY.md")!)
                    Link("Google Maps Platform Terms", destination: URL(string: "https://cloud.google.com/maps-platform/terms")!)
                    Link("Google Privacy Policy", destination: URL(string: "https://policies.google.com/privacy")!)
                } footer: {
                    Text("Real-world scenery may use Google Maps 3D or Apple Maps. Provider attribution remains visible in the airplane window; Voyage's deterministic offline world is used as a safe fallback.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { hasSeededData = TestModeSeeder.hasSeededData(in: modelContext) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
