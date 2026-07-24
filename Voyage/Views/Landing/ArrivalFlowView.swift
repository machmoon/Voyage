import SwiftUI
import UIKit
import StoreKit

/// The peak-end payoff after touchdown: a typographic welcome, baggage
/// claim for your checked intentions, and a passport stamp into the logbook.
struct ArrivalFlowView: View {
    @Bindable var session: FlightSession
    let onDone: () -> Void

    private enum Step {
        case welcome, baggage, stamp
    }

    @State private var step: Step = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-VoyageDebugStamp") { return .stamp }
        #endif
        return .welcome
    }()

    private var city: Airport { session.itinerary.destination }

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                WelcomeView(session: session) {
                    advance(session.intentions.isEmpty ? .stamp : .baggage)
                }
                .transition(.opacity)
            case .baggage:
                BaggageClaimView(session: session) {
                    advance(.stamp)
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .opacity))
            case .stamp:
                StampView(session: session, onDone: onDone)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .opacity))
            }
        }
    }

    private func advance(_ next: Step) {
        withAnimation(.smooth(duration: 0.5)) { step = next }
    }
}

// MARK: - Welcome

/// Full-screen typographic arrival moment in the restrained Voyage palette.
private struct WelcomeView: View {
    @Bindable var session: FlightSession
    let onContinue: () -> Void

    @State private var revealed = false

    private var city: Airport { session.itinerary.destination }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.surfaceSubtle, Theme.surfaceDark, Theme.ink],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [Theme.accent.opacity(0.3), .clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 420
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Text("Welcome to")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .opacity(revealed ? 1 : 0)
                    .offset(y: revealed ? 0 : 16)

                Text(city.city)
                    .font(.system(size: 58, weight: .black))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .opacity(revealed ? 1 : 0)
                    .offset(y: revealed ? 0 : 26)
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 6)

                Text(city.code)
                    .font(.system(size: 15, weight: .heavy, design: .monospaced))
                    .kerning(6)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 8)
                    .opacity(revealed ? 1 : 0)

                statsCard
                    .padding(.top, 44)
                    .opacity(revealed ? 1 : 0)
                    .offset(y: revealed ? 0 : 30)

                if session.watersTaken > 0 {
                    Label(
                        session.watersTaken == 1
                            ? "1 water en route"
                            : "\(session.watersTaken) waters en route",
                        systemImage: "cup.and.saucer.fill"
                    )
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 14)
                    .opacity(revealed ? 1 : 0)
                }

                Spacer()

                Button(action: onContinue) {
                    Text(session.intentions.isEmpty ? "Continue to passport control" : "Head to baggage claim")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                        )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
                .opacity(revealed ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.smooth(duration: 1.0).delay(0.25)) { revealed = true }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                Haptics.success()
            }
        }
    }

    private var statsCard: some View {
        HStack(spacing: 0) {
            arrivalStat("Miles earned", "+\(Int(session.completedMiles).formatted())")
            divider
            arrivalStat("Focus time", session.itinerary.totalFocusDuration.shortDurationText)
            divider
            arrivalStat("Flight", session.itinerary.primaryFlightNumber)
        }
        .padding(.vertical, 16)
        .background(Theme.surfaceElevated.opacity(0.86), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.09), lineWidth: 1)
        )
        .padding(.horizontal, 32)
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.2))
            .frame(width: 1, height: 30)
    }

    private func arrivalStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .kerning(1.2)
                .foregroundStyle(.white.opacity(0.6))
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Baggage claim

/// Your checked intentions come around the belt — mark off what you finished.
private struct BaggageClaimView: View {
    @Bindable var session: FlightSession
    let onContinue: () -> Void

    @State private var claimed: Set<Int> = []

    var body: some View {
        ZStack {
            Theme.surfaceDark.ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.accent)
                    Text("Baggage claim")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Text("Carousel 3 · claim what you finished")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.top, 40)

                VStack(spacing: 12) {
                    ForEach(Array(session.intentions.enumerated()), id: \.offset) { index, intention in
                        bagCard(index: index, intention: intention)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 36)

                Spacer()

                Button(action: finish) {
                    Text("Continue to passport control")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
        }
    }

    private func bagCard(index: Int, intention: String) -> some View {
        let isClaimed = claimed.contains(index)
        return Button {
            Haptics.tap()
            // Claiming reads the tag; releasing it back onto the belt does not.
            if !isClaimed { CabinAudioEngine.shared.playScanBeep() }
            withAnimation(.snappy(duration: 0.3)) {
                if isClaimed { claimed.remove(index) } else { claimed.insert(index) }
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "suitcase.rolling.fill")
                    .font(.title3)
                    .foregroundStyle(isClaimed ? Theme.accent : .white.opacity(0.35))
                Text(intention)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(isClaimed ? 0.95 : 0.7))
                    .strikethrough(isClaimed, color: .white.opacity(0.5))
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: isClaimed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isClaimed ? Theme.accent : .white.opacity(0.25))
            }
            .padding(16)
            .background(.white.opacity(isClaimed ? 0.1 : 0.05),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func finish() {
        if let entry = session.logEntry {
            entry.intentionsCompleted = session.intentions.indices.map { claimed.contains($0) }
        }
        onContinue()
    }
}

// MARK: - Passport stamp

/// The final thunk: an inked passport stamp presses into the logbook page and
/// lands alone, then the receipt and optional caption sequence in behind it.
private struct StampView: View {
    @Bindable var session: FlightSession
    let onDone: () -> Void

    @Environment(\.requestReview) private var requestReview

    /// Two beats: the stamp presses into the page (`stamped`), then once it has
    /// settled the receipt and share controls reveal (`revealed`). Sequencing
    /// them keeps the stamp moment clean instead of stacking a form under it.
    @State private var stamped = false
    @State private var revealed = false
    @State private var shareCaption = ""
    @State private var receiptPNG: Data?

    private var city: Airport { session.itinerary.destination }

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 0) {
                header
                    .padding(.top, 40)

                Spacer(minLength: 12)

                passportPage
                    .scaleEffect(revealed ? 0.9 : 1)
                    .padding(.top, revealed ? 0 : 24)

                Spacer(minLength: 12)

                if revealed {
                    shareSection
                        .padding(.horizontal, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))

                    Button {
                        persistShareCaption()
                        onDone()
                    } label: {
                        Text("Back to the terminal")
                    }
                    .buttonStyle(VoyagePrimaryButtonStyle())
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 30)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onAppear { runStampSequence() }
        .onChange(of: shareCaption) { _, _ in
            receiptPNG = FlightReceiptRenderer.pngData(session: session, caption: shareCaption)
            persistShareCaption()
        }
    }

    private var backdrop: some View {
        ZStack {
            Color(hex: "17140F").ignoresSafeArea()
            // A warm counter spotlight falling on the open passport.
            RadialGradient(
                colors: [Color(hex: "2A2418").opacity(0.9), .clear],
                center: .center, startRadius: 40, endRadius: 460
            )
            .ignoresSafeArea()
            RadialGradient(
                colors: [.clear, .black.opacity(0.55)],
                center: .center, startRadius: 260, endRadius: 640
            )
            .ignoresSafeArea()
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("PASSPORT CONTROL")
                .font(.system(size: 12, weight: .heavy))
                .kerning(3)
                .foregroundStyle(Theme.statusAmber)
            Text("One more for the logbook")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
        }
    }

    /// Beat 1: press the stamp (haptic + thunk). Beat 2: after it settles, bring
    /// up the receipt and share controls.
    private func runStampSequence() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation(.spring(duration: 0.3, bounce: 0.42)) {
                stamped = true
            }
            Haptics.stamp()
            CabinAudioEngine.shared.playThunk()
            receiptPNG = FlightReceiptRenderer.pngData(session: session, caption: shareCaption)

            #if DEBUG
            // QA hold: keep the stamp beat on screen for a clean capture.
            if ProcessInfo.processInfo.arguments.contains("-VoyageDebugStampHold") { return }
            #endif

            try? await Task.sleep(for: .milliseconds(950))
            withAnimation(.smooth(duration: 0.45)) {
                revealed = true
            }
            await askForReviewIfEarned()
        }
    }

    /// The stamp is the high point of the whole session, which is the only
    /// honest place to ask. Waits out the stamp spring and its thunk so the
    /// system sheet doesn't slide up over the animation.
    private func askForReviewIfEarned() async {
        guard AppFeedback.shouldRequestReview() else { return }
        try? await Task.sleep(for: .milliseconds(1_200))
        AppFeedback.markReviewRequested()
        requestReview()
    }

    /// Strava pattern: optional activity description + shareable stats image.
    private var shareSection: some View {
        VStack(spacing: 12) {
            if let receiptPNG, let uiImage = UIImage(data: receiptPNG) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
            }

            TextField("What did you work on? (optional)", text: $shareCaption, axis: .vertical)
                .lineLimit(2...4)
                .font(.subheadline)
                .padding(12)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(.white)

            if let receiptPNG, let uiImage = UIImage(data: receiptPNG) {
                ShareLink(
                    item: ReceiptShareItem(pngData: receiptPNG),
                    preview: SharePreview(
                        "Flight to \(city.code)",
                        image: Image(uiImage: uiImage)
                    )
                ) {
                    Label("Share flight receipt", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(.white.opacity(0.22), lineWidth: 1)
                        )
                }
                .simultaneousGesture(TapGesture().onEnded { persistShareCaption() })
            }
        }
    }

    private func persistShareCaption() {
        let trimmed = shareCaption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let entry = session.logEntry else { return }
        entry.shareCaption = trimmed.isEmpty ? nil : trimmed
    }

    private var passportPage: some View {
        PassportPage(mrzTop: mrzTop, mrzBottom: mrzBottom) {
            EntryStamp(
                code: city.code,
                city: city.city,
                dateText: stampDateText,
                milesText: "+\(Int(session.completedMiles).formatted()) MI"
            )
            .rotationEffect(.degrees(-6.5))
            // The press: comes down slightly oversized and off-angle, then
            // seats into the page rather than fading up from nothing.
            .scaleEffect(stamped ? 1 : 1.34)
            .rotationEffect(.degrees(stamped ? 0 : -5))
            .opacity(stamped ? 1 : 0)
            .offset(y: 6)
        }
    }

    // MARK: Stamp text

    private var stampDateText: String {
        Self.stampDate.string(from: .now).uppercased()
    }

    private static let stampDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "dd MMM yyyy"
        return f
    }()

    /// Passport-style machine-readable zone. Cosmetic, but built from the real
    /// route so it reads as this trip's page, not boilerplate.
    private var mrzTop: String {
        let cityToken = city.city.uppercased()
            .replacingOccurrences(of: " ", with: "<")
            .filter { $0.isLetter || $0 == "<" }
        return pad("P<VOY\(city.code)<\(cityToken)", to: 36)
    }

    private var mrzBottom: String {
        let origin = session.itinerary.origin.code
        let date = Self.mrzDate.string(from: .now)
        let miles = Int(session.completedMiles)
        return pad("\(city.code)\(origin)<\(date)<\(miles)MI", to: 36)
    }

    private static let mrzDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "ddMMMyy"
        return f
    }()

    private func pad(_ s: String, to width: Int) -> String {
        s.count >= width ? String(s.prefix(width))
                         : s + String(repeating: "<", count: width - s.count)
    }
}
