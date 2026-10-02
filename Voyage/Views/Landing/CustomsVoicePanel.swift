import SwiftUI

/// The officer's desk: one strip above the green and red channels, in the
/// arrivals hall's own black-and-yellow wayfinding colours, so the
/// declaration card above it stays exactly the form it was. What the
/// officer is doing is said in words (asking, listening, a reply), and
/// "Type instead" and "Skip" stay on screen for the whole interview.
struct CustomsVoicePanel: View {
    let interview: CustomsInterview

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let signYellow = Color(hex: "FFCC00")
    private static let listeningRed = Color(hex: "FF453A")

    var body: some View {
        if let content {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    badge
                    VStack(alignment: .leading, spacing: 3) {
                        Text(content.label)
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .kerning(1.2)
                            .foregroundStyle(Self.signYellow)
                        Text(content.text)
                            .font(.subheadline.weight(content.emphasised ? .semibold : .regular))
                            .foregroundStyle(.white.opacity(content.emphasised ? 1 : 0.75))
                            .fixedSize(horizontal: false, vertical: true)
                            .contentTransition(.opacity)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.updatesFrequently)
                controls
            }
            .padding(12)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.08)))
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .animation(.smooth(duration: 0.25), value: interview.phase)
        }
    }

    // MARK: Content per phase

    private struct Content {
        let label: String
        let text: String
        var emphasised = false
    }

    private var questionLabel: String {
        "QUESTION \((interview.activeIndex ?? 0) + 1) OF \(interview.questions.count)"
    }

    private var content: Content? {
        switch interview.phase {
        case .preparing:
            return Content(label: "OFFICER", text: "Reading what you studied…")
        case .intro:
            return Content(label: "ANSWER OUT LOUD",
                           text: "The officer asks three questions about your bags and the calendar around this flight, then listens. It all runs on this iPhone. Nothing leaves it.",
                           emphasised: true)
        case .ready:
            return Content(label: "OFFICER", text: "Ready when you are. Three questions, out loud.")
        case let .asking(index):
            return Content(label: questionLabel, text: interview.questions[index], emphasised: true)
        case .listening:
            return Content(label: "LISTENING", text: "Answer in your own words. It stops when you pause.")
        case .thinking:
            return Content(label: "OFFICER", text: "…")
        case let .feedback(_, line):
            return Content(label: "OFFICER", text: line, emphasised: true)
        case .finished:
            return Content(label: "OFFICER", text: "That's all three. Declare when you're ready.")
        case .typing:
            if let notice = interview.notice { return Content(label: "TYPING", text: notice) }
            // Typing by choice: a quiet way back to voice, or nothing at all.
            return interview.canUseVoice && hasEmptyAnswer
                ? Content(label: "OFFICER", text: "Typing. You can answer the rest out loud.")
                : nil
        }
    }

    private var hasEmptyAnswer: Bool {
        interview.answers.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    // MARK: Badge

    @ViewBuilder
    private var badge: some View {
        let listening: Bool = { if case .listening = interview.phase { return true } else { return false } }()
        ZStack {
            Circle().fill(listening ? Self.listeningRed : .white.opacity(0.12))
            if listening && !reduceMotion {
                PulseRing(color: Self.listeningRed)
            }
            Image(systemName: badgeSymbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(listening ? .white : Self.signYellow)
                .symbolEffect(.variableColor.iterative, isActive: isSpeaking && !reduceMotion)
        }
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
    }

    private var isSpeaking: Bool {
        switch interview.phase {
        case .asking, .feedback: return true
        default: return false
        }
    }

    private var badgeSymbol: String {
        switch interview.phase {
        case .listening: return "mic.fill"
        case .asking, .feedback: return "speaker.wave.2.fill"
        case .typing: return "keyboard"
        default: return "person.text.rectangle"
        }
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        switch interview.phase {
        case .intro:
            HStack(spacing: 8) {
                primary("Use voice", symbol: "mic.fill") { Task { await interview.acceptIntro() } }
                secondary("Type instead", symbol: "keyboard") { Task { await interview.declineIntro() } }
            }
        case .ready:
            HStack(spacing: 8) {
                primary("Answer out loud", symbol: "mic.fill") { interview.start() }
                secondary("Type instead", symbol: "keyboard") { interview.typeInstead() }
            }
        case .asking, .listening, .thinking, .feedback:
            HStack(spacing: 8) {
                secondary("Type instead", symbol: "keyboard") { interview.typeInstead() }
                secondary("Skip", symbol: "forward.fill") { interview.skip() }
            }
        case .typing:
            if interview.canUseVoice && hasEmptyAnswer {
                secondary("Answer out loud", symbol: "mic.fill") { interview.start() }
            }
        case .preparing:
            secondary("Type instead", symbol: "keyboard") { interview.typeInstead() }
        case .finished:
            EmptyView()
        }
    }

    private func primary(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: { Haptics.tap(); action() }) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(Self.signYellow, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func secondary(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: { Haptics.tap(); action() }) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// A ring that grows and fades around the listening badge, the iOS
/// dictation cue in the officer's colour.
private struct PulseRing: View {
    let color: Color
    @State private var expanded = false

    var body: some View {
        Circle()
            .stroke(color, lineWidth: 2)
            .scaleEffect(expanded ? 1.6 : 1)
            .opacity(expanded ? 0 : 0.8)
            .onAppear {
                withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) { expanded = true }
            }
    }
}

extension View {
    /// The card item the officer is on: a faint ink wash and a rule down the
    /// left, the way an official marks the line being read.
    func customsActiveItem(_ active: Bool) -> some View {
        padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(alignment: .leading) {
                if active {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(Theme.passportInk.opacity(0.08))
                        Rectangle().fill(Theme.passportInk).frame(width: 2)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, -6)
            .animation(.smooth(duration: 0.25), value: active)
    }
}
