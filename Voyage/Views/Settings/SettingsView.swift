import SwiftUI
import UIKit
import AVFoundation
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var settings = SettingsStore.shared
    @Query private var entries: [LogbookEntry]
    @State private var hasSeededData = false
    @State private var isWritingFeedback = false
    @State private var showingFlightManual = false
    /// Read once when Settings opens; Apple Intelligence state changes in the
    /// Settings app, which reopening this screen picks up.
    @State private var intelligence = IntelligenceAvailability.current

    /// Installed English voices, best first.
    private var paVoices: [AVSpeechSynthesisVoice] {
        Announcer.rankedEnglishVoices()
    }

    /// True when the traveler picked one of this device's synthesized voices
    /// instead of a recorded Voyage Air voice. The recorded voices ship with
    /// the app, so nothing below applies to them.
    private var isUsingDeviceVoice: Bool {
        guard let identifier = settings.paVoiceIdentifier else { return false }
        return PAVoice(rawValue: identifier) == nil
    }

    /// True when at least one downloaded voice is installed. iOS ships only the
    /// compact voices; the good ones arrive when the traveler downloads them,
    /// and no API lets an app fetch one on their behalf.
    private var hasDownloadedVoice: Bool {
        paVoices.contains { Announcer.isHighFidelityVoice($0) || Announcer.isSiriVoice($0) }
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
                if VoyageApp.logbookIsEphemeral {
                    Section {
                        LogbookStorageWarning()
                    }
                }

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

                        if isUsingDeviceVoice && !hasDownloadedVoice {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Only the compact voice is installed",
                                      systemImage: "exclamationmark.triangle.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.orange)
                                Text("Download a better one in Settings, Accessibility, Spoken Content, Voices. Voyage Air voices need no download.")
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
                    }
                } header: {
                    Text("Sound")
                } footer: {
                    Text("Everything plays on device and works in airplane mode.")
                }

                Section {
                    Toggle(isOn: $settings.cabinServiceEnabled) {
                        Label("Cabin service", systemImage: "figure.stand")
                    }
                } header: {
                    Text("In flight")
                } footer: {
                    Text("Short cards at cruise: rest your eyes, stretch, drink water.")
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
                        Label("Departure airport", systemImage: "airplane.departure")
                    }
                } header: {
                    Text("Origin")
                } footer: {
                    Text("Defaults to the airport nearest you.")
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
                    .onChange(of: settings.windowWorldMode) { _, mode in
                        settings.realWorldTwinEnabled = mode == .real
                    }
                } header: {
                    Text("Window")
                } footer: {
                    Text(settings.windowWorldMode.caption)
                }

                Section {
                    LabeledContent("Grace period", value: "30 seconds")
                    LabeledContent("Penalty", value: "Stopped early")
                } header: {
                    Text("Strict mode")
                } footer: {
                    Text("Completed legs still earn partial miles.")
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
                    Text("Add Voyage to an iOS Focus Filter, then turn that Focus on before boarding.")
                }

                if intelligence.offersSetting {
                    Section {
                        Toggle(isOn: Binding(
                            get: { settings.onDeviceIntelligenceEnabled },
                            set: { settings.onDeviceIntelligenceEnabled = $0 }
                        )) {
                            Label("Flight plan and captain's note", systemImage: "sparkles")
                        }
                        .disabled(intelligence != .available)
                        .accessibilityIdentifier("settings-apple-intelligence")
                    } header: {
                        Text("Apple Intelligence")
                    } footer: {
                        Text(intelligence.settingsFootnote)
                    }
                }

                FirstClassSettingsSection()

                Section {
                    Button {
                        showingFlightManual = true
                    } label: {
                        Label("The Flight Manual", systemImage: "book.pages")
                    }
                    .accessibilityIdentifier("settings-flight-manual")
                } footer: {
                    Text("The studies behind each part of a flight.")
                }

                Section {
                    Button {
                        settings.hasCompletedOnboarding = false
                        dismiss()
                    } label: {
                        Label("Replay onboarding", systemImage: "arrow.counterclockwise")
                    }
                    Button {
                        isWritingFeedback = true
                    } label: {
                        Label("Send a note to the flight deck", systemImage: "paperplane.fill")
                    }
                } header: {
                    Text("Help")
                } footer: {
                    Text("A note opens GitHub, posted publicly under your account.")
                }

                Section {
                    LogbookExportButtons(entries: entries)
                } header: {
                    Text("Logbook")
                } footer: {
                    Text("One Markdown file of your recent flights.")
                }

                // Seeded demo history is a development affordance, not a
                // shipping feature — it would wipe a real traveler's logbook.
                #if DEBUG
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
                    Text("A few weeks of sample flights. Replaces any existing history.")
                }
                #endif

                Section {
                    Link("Open-Meteo", destination: URL(string: "https://open-meteo.com")!)
                    Link("CC BY 4.0 license", destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
                } header: {
                    Text("Weather data")
                } footer: {
                    Text("Weather from Open-Meteo, licensed under CC BY 4.0.")
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                    LabeledContent("Airline", value: "Voyage Air")
                    LabeledContent("Cabin voice", value: "AI voice by ElevenLabs")
                    Link("Voyage Terms of Use", destination: URL(string: "https://github.com/machmoon/Voyage/blob/main/TERMS.md")!)
                    Link("Voyage Privacy Notice", destination: URL(string: "https://github.com/machmoon/Voyage/blob/main/PRIVACY.md")!)
                    Link("Source code on GitHub", destination: URL(string: "https://github.com/machmoon/Voyage")!)
                } footer: {
                    Text("For students, by students. Voyage is free and open source.")
                }
            }
            .tint(Theme.accent)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { hasSeededData = TestModeSeeder.hasSeededData(in: modelContext) }
            .sheet(isPresented: $isWritingFeedback) { FeedbackSheet() }
            .sheet(isPresented: $showingFlightManual) { FlightManualView() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
