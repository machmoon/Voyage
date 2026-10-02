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
    @State private var airplaneMode = AirplaneMode.shared
    @State private var choosingApps = false

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

    // Grouped the way iOS Settings and IceCubesApp group theirs: the body
    // is a short list of named sections, most-used first, About and data
    // last (IceCubesApp, IceCubesApp/App/Tabs/Settings/SettingsTab.swift at
    // b2db303: appSection, accountsSection, generalSection, ..., cacheSection;
    // AGPL, read for structure only, no code taken). Each row carries an SF
    // Symbol in a tinted square, as iOS Settings draws them (`SettingsLabel`).
    var body: some View {
        NavigationStack {
            Form {
                if VoyageApp.logbookIsEphemeral {
                    Section {
                        LogbookStorageWarning()
                    }
                }

                flightSection
                windowSection
                soundSection
                focusSection
                if intelligence.offersSetting {
                    intelligenceSection
                }
                FirstClassSettingsSection()
                    .labelStyle(SettingsIconLabelStyle(tint: Theme.seatFirstGold))
                logbookSection
                #if DEBUG
                testModeSection
                #endif
                helpSection
                aboutSection
                weatherSection
            }
            .tint(Theme.accent)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { hasSeededData = TestModeSeeder.hasSeededData(in: modelContext) }
            .sheet(isPresented: $isWritingFeedback) { FeedbackSheet() }
            .sheet(isPresented: $showingFlightManual) { FlightManualView() }
            .airplaneModePicker(isPresented: $choosingApps)
            .onAppear { airplaneMode.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Flight

    private var flightSection: some View {
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
                SettingsLabel("Departure airport", systemImage: "airplane.departure", tint: .blue)
            }
            Toggle(isOn: $settings.cabinServiceEnabled) {
                SettingsLabel("Cabin service", systemImage: "figure.stand", tint: .teal)
            }
            Toggle(isOn: $settings.customsEnabled) {
                SettingsLabel("Customs", systemImage: "person.text.rectangle", tint: .indigo)
            }
            .accessibilityIdentifier("settings-customs")
            LabeledContent {
                Text("30 seconds")
            } label: {
                SettingsLabel("Grace period", systemImage: "timer", tint: .orange)
            }
            LabeledContent {
                Text("Stopped early")
            } label: {
                SettingsLabel("Penalty", systemImage: "exclamationmark.octagon.fill", tint: .red)
            }
        } header: {
            Text("Flight")
        } footer: {
            Text("Cabin service brings short cards at cruise. Customs asks three questions out loud after landing, on this iPhone. Completed legs still earn miles if you leave early.")
        }
    }

    private var windowSection: some View {
        Section {
            Picker(selection: Binding(
                get: { settings.windowWorldMode },
                set: { settings.windowWorldMode = $0 }
            )) {
                ForEach(WindowWorldMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            } label: {
                SettingsLabel("Window view", systemImage: "cloud.sun.fill", tint: .cyan)
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
    }

    // MARK: Sound & voice

    private var soundSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { settings.soundEffectsEnabled },
                set: { settings.soundEffectsEnabled = $0 }
            )) {
                SettingsLabel("Sound cues", systemImage: "bell.fill", tint: .red)
            }
            Toggle(isOn: Binding(
                get: { settings.ambienceEnabled },
                set: {
                    settings.ambienceEnabled = $0
                    if !$0 { CabinAudioEngine.shared.stopAmbience() }
                }
            )) {
                SettingsLabel("Cabin ambience", systemImage: "speaker.wave.2.fill", tint: .pink)
            }
            Toggle(isOn: Binding(
                get: { settings.announcementsEnabled },
                set: { settings.announcementsEnabled = $0; if !$0 { Announcer.shared.stop() } }
            )) {
                SettingsLabel("Spoken check-ins", systemImage: "waveform", tint: .purple)
            }

            if settings.announcementsEnabled {
                voicePicker

                Button {
                    Announcer.shared.previewSelectedVoice()
                } label: {
                    SettingsLabel("Preview voice", systemImage: "play.fill", tint: .gray)
                }

                if isUsingDeviceVoice && !hasDownloadedVoice {
                    compactVoiceWarning
                }
            }
        } header: {
            Text("Sound & Voice")
        } footer: {
            Text("Everything plays on device and works in airplane mode.")
        }
    }

    private var voicePicker: some View {
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
            SettingsLabel("Voice", systemImage: "person.wave.2.fill", tint: .purple)
        }
    }

    /// Only when a device voice is picked and just the compact one is
    /// installed. Not a row label, so it keeps its own warning glyph.
    private var compactVoiceWarning: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Only the compact voice is installed")
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

    // MARK: Focus and Apple Intelligence

    // Airplane Mode sits here rather than under Flight: like a Focus, it is
    // about what reaches you while you fly, and the two read as one choice.
    private var focusSection: some View {
        Section {
            if airplaneMode.isAvailable {
                Toggle(isOn: $airplaneMode.isEnabled) {
                    SettingsLabel("Airplane Mode", systemImage: "airplane", tint: .orange)
                }
                .disabled(airplaneMode.selectionCount == 0)
                .accessibilityIdentifier("settings-airplane-mode")
                Button {
                    Task {
                        if await airplaneMode.requestAuthorization() { choosingApps = true }
                    }
                } label: {
                    LabeledContent {
                        Text(airplaneMode.selectionCount == 0 ? "None" : "\(airplaneMode.selectionCount)")
                    } label: {
                        SettingsLabel("Choose apps", systemImage: "square.grid.2x2.fill", tint: .orange)
                    }
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("settings-airplane-mode-apps")
            }
            Toggle(isOn: Binding(
                get: { settings.flightFocusRemindersEnabled },
                set: { settings.flightFocusRemindersEnabled = $0 }
            )) {
                SettingsLabel("Depart focus reminders", systemImage: "moon.fill", tint: .indigo)
            }
        } header: {
            Text("Focus")
        } footer: {
            Text(focusFootnote)
        }
    }

    private var focusFootnote: String {
        let focus = "Add Voyage to an iOS Focus Filter, then turn that Focus on before boarding."
        guard airplaneMode.isAvailable else { return focus }
        if airplaneMode.authorization == .denied {
            return "Screen Time access is off for Voyage. Turn it on in iOS Settings, Screen Time. " + focus
        }
        return "Airplane Mode blocks the apps you choose from takeoff until you land, with Screen Time. Wi-Fi stays on. " + focus
    }

    private var intelligenceSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { settings.onDeviceIntelligenceEnabled },
                set: { settings.onDeviceIntelligenceEnabled = $0 }
            )) {
                SettingsLabel("Flight plan and captain's note", systemImage: "sparkles", tint: .purple)
            }
            .disabled(intelligence != .available)
            .accessibilityIdentifier("settings-apple-intelligence")
        } header: {
            Text("Apple Intelligence")
        } footer: {
            Text(intelligence.settingsFootnote)
        }
    }

    // MARK: Logbook data

    private var logbookSection: some View {
        Section {
            LogbookExportButtons(entries: entries)
                .labelStyle(SettingsIconLabelStyle(tint: .green))
        } header: {
            Text("Logbook")
        } footer: {
            Text("One Markdown file of your recent flights.")
        }
    }

    #if DEBUG
    /// Seeded demo history is a development affordance, not a shipping
    /// feature: it would wipe a real traveler's logbook.
    private var testModeSection: some View {
        Section {
            Button {
                TestModeSeeder.seed(into: modelContext)
                hasSeededData = true
            } label: {
                SettingsLabel("Load demo history", systemImage: "wand.and.stars", tint: .gray)
            }
            if hasSeededData {
                Button(role: .destructive) {
                    TestModeSeeder.clear(from: modelContext)
                    hasSeededData = false
                } label: {
                    SettingsLabel("Clear logbook", systemImage: "trash", tint: .red)
                }
            }
        } header: {
            Text("Test mode")
        } footer: {
            Text("A few weeks of sample flights. Replaces any existing history.")
        }
    }
    #endif

    // MARK: Help and About

    private var helpSection: some View {
        Section {
            Button {
                showingFlightManual = true
            } label: {
                SettingsLabel("The Flight Manual", systemImage: "book.pages.fill", tint: .brown)
            }
            .accessibilityIdentifier("settings-flight-manual")
            Button {
                settings.hasCompletedOnboarding = false
                dismiss()
            } label: {
                SettingsLabel("Replay onboarding", systemImage: "arrow.counterclockwise", tint: .gray)
            }
            Button {
                isWritingFeedback = true
            } label: {
                SettingsLabel("Send a note to the flight deck", systemImage: "paperplane.fill", tint: .blue)
            }
        } header: {
            Text("Help")
        } footer: {
            Text("A note opens GitHub, posted publicly under your account.")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
            LabeledContent("Airline", value: "Voyage Air")
            LabeledContent("Cabin voice", value: "AI voice by ElevenLabs")
            Link("Voyage Terms of Use", destination: URL(string: "https://github.com/machmoon/Voyage/blob/main/TERMS.md")!)
            Link("Voyage Privacy Notice", destination: URL(string: "https://github.com/machmoon/Voyage/blob/main/PRIVACY.md")!)
            Link("Source code on GitHub", destination: URL(string: "https://github.com/machmoon/Voyage")!)
        } header: {
            Text("About")
        } footer: {
            Text("For students, by students. Voyage is free and open source.")
        }
    }

    /// Open-Meteo's CC BY 4.0 credit. Its own section by design (CLAUDE.md:
    /// the credit lives in Settings "Weather data", off the flight screen).
    private var weatherSection: some View {
        Section {
            Link("Open-Meteo", destination: URL(string: "https://open-meteo.com")!)
            Link("CC BY 4.0 license", destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
        } header: {
            Text("Weather data")
        } footer: {
            Text("Weather from Open-Meteo, licensed under CC BY 4.0.")
        }
    }
}

// MARK: - Row icon

/// A Settings row title with its SF Symbol in a tinted rounded square, the
/// icon iOS Settings gives each row. Built explicitly rather than through
/// `.labelStyle` on a section: a Form's Toggle and LabeledContent rows do not
/// pass a section's label style down to their labels (measured on iOS 26.5).
struct SettingsLabel: View {
    let title: String
    let systemImage: String
    let tint: Color

    init(_ title: String, systemImage: String, tint: Color) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            SettingsIcon(tint: tint) { Image(systemName: systemImage) }
        }
    }
}

/// The same tinted square for rows built in other files (Voyage First,
/// logbook export), whose Buttons do take a label style from outside.
struct SettingsIconLabelStyle: LabelStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        Label {
            configuration.title
        } icon: {
            SettingsIcon(tint: tint) { configuration.icon }
        }
    }
}

private struct SettingsIcon<Icon: View>: View {
    let tint: Color
    @ViewBuilder let icon: Icon

    /// 29pt at the default size, as iOS Settings draws it, and it grows with
    /// Dynamic Type alongside the row title.
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 29

    var body: some View {
        icon
            .font(.system(size: side * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background(tint, in: RoundedRectangle(cornerRadius: side * 0.24, style: .continuous))
    }
}
