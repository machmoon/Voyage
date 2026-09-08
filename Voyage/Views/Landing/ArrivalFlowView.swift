import SwiftUI
import UIKit
import StoreKit
import MapKit

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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var revealed = false

    private var city: Airport { session.itinerary.destination }

    /// Reduce Motion keeps the copy in place and lets opacity do the work.
    private func rise(_ distance: CGFloat) -> CGFloat {
        revealed || reduceMotion ? 0 : distance
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.surfaceSubtle, Theme.surfaceDark, Theme.ink],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            // You just flew somewhere real, so show the place. The gradient
            // above stays as the base layer, which is what you see while the
            // snapshot loads and what you keep if it never arrives.
            DestinationImageryView(airport: city)
                .ignoresSafeArea()
                .opacity(revealed ? 1 : 0)
                .animation(.smooth(duration: 1.2), value: revealed)

            // Sink the imagery so white type holds contrast over bright terrain.
            LinearGradient(
                colors: [
                    Theme.ink.opacity(0.55),
                    Theme.ink.opacity(0.35),
                    Theme.ink.opacity(0.82)
                ],
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
                    .offset(y: rise(16))

                Text(city.city)
                    .font(.system(size: 58, weight: .black))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .opacity(revealed ? 1 : 0)
                    .offset(y: rise(26))
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
                    .offset(y: rise(30))

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

/// Your checked intentions come around the belt. Mark off what you finished.
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

/// The final thunk: an inked cachet presses into an open passport spread and
/// lands alone, then the receipt and optional caption sequence in behind it.
private struct StampView: View {
    @Bindable var session: FlightSession
    let onDone: () -> Void

    @Environment(\.requestReview) private var requestReview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

                passportSpread
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
            // Reduce Motion drops the travel and the overshoot, not the payoff:
            // the haptic and the thunk still fire on the same beat.
            withAnimation(reduceMotion ? .easeOut(duration: 0.25)
                                       : .spring(duration: 0.3, bounce: 0.42)) {
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

    // MARK: The spread

    /// The destination's own ink. Blended well toward the tonal passport blue so
    /// a pale city color still prints as a border-control ink rather than as UI
    /// chrome, and so every stamp in the logbook stays part of one family.
    private var cachetInk: Color {
        Color.blended(Color(hex: city.accentHex), with: Color(hex: "1E3866"), amount: 0.58)
    }

    private var passportSpread: some View {
        PassportSpread(
            accent: Color(hex: city.accentHex),
            pageNumber: pageNumber,
            mrzTop: mrz.line1,
            mrzBottom: mrz.line2
        ) {
            ZStack {
                // The stub you tore to board, slipped into the page the way a
                // passport actually carries one. Sits under the stamp so the
                // stamp stays the thing that lands.
                TuckedTicket(
                    origin: session.itinerary.origin,
                    destination: city,
                    flightNumber: session.itinerary.primaryFlightNumber,
                    seat: session.seat,
                    dateText: stampDateText
                )
                .rotationEffect(.degrees(3.5))
                .offset(x: 4, y: 104)
                .opacity(stamped ? 1 : 0)
                .offset(y: stamped || reduceMotion ? 0 : 10)
                .animation(.smooth(duration: 0.5).delay(0.12), value: stamped)

                ArrivalCachet(
                    code: city.code,
                    city: city.city,
                    dateText: stampDateText,
                    milesText: "+\(Int(session.completedMiles).formatted()) MI",
                    ink: cachetInk,
                    seed: cachetSeed
                )
                .rotationEffect(.degrees(-6.5))
                // The press: comes down slightly oversized and off-angle, then
                // seats into the page rather than fading up from nothing.
                .scaleEffect(stamped || reduceMotion ? 1 : 1.34)
                .rotationEffect(.degrees(stamped || reduceMotion ? 0 : -5))
                .opacity(stamped ? 1 : 0)
                .offset(y: -18)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Passport page. Entry stamp: admitted at \(city.city), \(city.code), \(stampDateText), \(Int(session.completedMiles).formatted()) miles."
        )
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

    /// Page numbering runs through the booklet, so pick a stable page from the
    /// route rather than reprinting the same number on every arrival. Derived
    /// from the codes rather than from `hashValue`, which is seeded per process
    /// and would renumber the page on every launch.
    private var pageNumber: String {
        let route = session.itinerary.origin.code + city.code
        let sum = route.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return String(format: "%02d", sum % 26 + 5)
    }

    /// The die is the same die every time you land in this city, so the worn
    /// patches in the ink stay put. A per-flight seed would make the same stamp
    /// look like a different die on every trip.
    private var cachetSeed: UInt64 {
        city.code.unicodeScalars.reduce(UInt64(1_469)) { $0 &* 31 &+ UInt64($1.value) }
    }

    /// A format-exact ICAO 9303 TD3 machine-readable zone built from this trip.
    private var mrz: TravelDocumentCode.TD3 {
        TravelDocumentCode.td3(
            surname: city.city,
            givenNames: session.itinerary.origin.city,
            documentNumber: session.itinerary.primaryFlightNumber,
            issueDate: .now,
            entryDate: .now,
            optionalData: "\(session.itinerary.origin.code)\(city.code)\(session.seat)"
        )
    }
}

// MARK: - Machine-readable zone

/// ICAO Doc 9303 Part 4, TD3: two lines of exactly 44 characters, character set
/// A to Z, 0 to 9 and the filler `<`, with check digits over the 7-3-1 weight
/// cycle. Field widths and the composite check-digit input follow the reference
/// generator in `Arg0s1080/mrz` (`mrz/generator/td3.py`).
///
/// This is a fictional travel document. The issuing-state field carries `VOY`,
/// which is deliberately not an assigned ISO 3166-1 alpha-3 code, and the fixed
/// TD3 slots carry trip data: the name subfields hold the destination and origin
/// cities, the document number holds the flight number, and the two date fields
/// hold the issue and entry dates.
private enum TravelDocumentCode {
    struct TD3 {
        let line1: String
        let line2: String
    }

    static let issuingAuthority = "VOY"

    /// ICAO 9303 character values: digits are themselves, A to Z are 10 to 35,
    /// and the filler `<` is 0.
    static func value(of character: Character) -> Int {
        guard let ascii = character.asciiValue else { return 0 }
        switch ascii {
        case 48...57: return Int(ascii) - 48      // "0" to "9"
        case 65...90: return Int(ascii) - 55      // "A" to "Z"
        default: return 0                          // "<" and anything else
        }
    }

    /// Weights cycle 7, 3, 1 across the field; the digit is the sum modulo 10.
    static func checkDigit(_ field: String) -> String {
        let weights = [7, 3, 1]
        var sum = 0
        for (index, character) in field.enumerated() {
            sum += value(of: character) * weights[index % 3]
        }
        return String(sum % 10)
    }

    /// Fold arbitrary text into the MRZ character set, then pad with fillers.
    /// Anything outside A to Z and 0 to 9 becomes `<`, which is how spaces,
    /// hyphens and accented forms are transliterated on a real document.
    static func field(_ text: String, width: Int) -> String {
        var folded = ""
        folded.reserveCapacity(width)
        for scalar in text.uppercased().unicodeScalars {
            let character = Character(scalar)
            if character.isASCII, character.isLetter || character.isNumber {
                folded.append(character)
            } else {
                folded.append("<")
            }
        }
        return pad(folded, to: width)
    }

    static func pad(_ text: String, to width: Int) -> String {
        text.count >= width
            ? String(text.prefix(width))
            : text + String(repeating: "<", count: width - text.count)
    }

    private static let sixDigitDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyMMdd"
        return f
    }()

    static func td3(
        surname: String,
        givenNames: String,
        documentNumber: String,
        issueDate: Date,
        entryDate: Date,
        optionalData: String
    ) -> TD3 {
        // Line 1: positions 1 to 2 document type, 3 to 5 issuing state,
        // 6 to 44 the name field with `<<` between the two identifiers.
        let names = field(surname, width: 39) // fold first so spaces become `<`
            .trimmingCharacters(in: CharacterSet(charactersIn: "<"))
        let given = field(givenNames, width: 39)
            .trimmingCharacters(in: CharacterSet(charactersIn: "<"))
        let line1 = "P<" + issuingAuthority + pad(names + "<<" + given, to: 39)

        // Line 2, per the TD3 layout.
        let number = field(documentNumber.filter { !$0.isWhitespace }, width: 9)
        let numberCheck = checkDigit(number)
        let issued = sixDigitDate.string(from: issueDate)
        let issuedCheck = checkDigit(issued)
        let entered = sixDigitDate.string(from: entryDate)
        let enteredCheck = checkDigit(entered)
        let optional = field(optionalData, width: 14)
        let optionalCheck = checkDigit(optional)
        // Position 21 is the sex field; `<` is the valid unspecified filler.
        let sex = "<"

        let composite = number + numberCheck
            + issued + issuedCheck
            + entered + enteredCheck
            + optional + optionalCheck
        let compositeCheck = checkDigit(composite)

        let line2 = number + numberCheck
            + issuingAuthority
            + issued + issuedCheck
            + sex
            + entered + enteredCheck
            + optional + optionalCheck
            + compositeCheck

        return TD3(line1: pad(line1, to: 44), line2: pad(line2, to: 44))
    }
}

// MARK: - Deterministic noise

/// A small xorshift generator so paper grain, security fibres and ink wear
/// render identically on every launch. Stable QA screenshots, no per-frame
/// shimmer, and the same die prints the same worn patches every time.
private struct StampRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    /// Uniform in 0..<1.
    mutating func unit() -> Double { Double(next() % 1_000_000) / 1_000_000 }

    mutating func range(_ lower: Double, _ upper: Double) -> Double {
        lower + unit() * (upper - lower)
    }
}

// MARK: - Paper grain

/// Paper tooth, generated once into a 128 by 128 bitmap and then tiled.
///
/// This follows `kgn/KGNoise`: seed a generator, write random black and white
/// pixels into one small image, cache it, and tile that image to fill any size
/// rather than drawing per-pixel noise at every draw. Tiling a cached CGImage
/// costs one texture upload; the previous approach filled several thousand
/// `Canvas` ellipses on every layout pass.
private enum PaperGrainTile {
    /// Built at 3x so one bitmap pixel lands near one device pixel and the
    /// grain reads as tooth rather than as visible dots.
    static let scale: CGFloat = 3

    static let image: UIImage? = make()

    private static func make() -> UIImage? {
        let side = 128
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        var rng = StampRNG(seed: 0x5EED_10FF)

        for index in stride(from: 0, to: pixels.count, by: 4) {
            // Half the specks lift the stock, half sink it. Alpha stays low so
            // the tile reads as tooth under an overlay blend, not as static.
            let luminance: UInt8 = rng.next() % 2 == 0 ? 0 : 255
            let alpha = UInt8(rng.next() % 30)
            let premultiplied = UInt8(Int(luminance) * Int(alpha) / 255)
            pixels[index] = premultiplied
            pixels[index + 1] = premultiplied
            pixels[index + 2] = premultiplied
            pixels[index + 3] = alpha
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        guard let cgImage = CGImage(
            width: side,
            height: side,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return nil }

        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }
}

private struct PaperGrain: View {
    var opacity: Double = 0.55

    var body: some View {
        if let image = PaperGrainTile.image {
            Image(uiImage: image)
                .resizable(resizingMode: .tile)
                .opacity(opacity)
                .blendMode(.overlay)
                .allowsHitTesting(false)
        }
    }
}

/// Short coloured threads pressed into the stock while it is still pulp. Real
/// security paper carries visible fibres as well as fluorescent ones, and they
/// are the cheapest cue that a surface is paper rather than a fill.
private struct SecurityFibres: View {
    var accent: Color
    var seed: UInt64 = 0xF1B3

    var body: some View {
        Canvas { context, size in
            var rng = StampRNG(seed: seed)
            let palette = [Color(hex: "B4453C"), Color(hex: "3F5D9B"), accent]
            let count = Int(size.width * size.height / 900)
            for _ in 0..<max(count, 12) {
                let x = rng.range(0, size.width)
                let y = rng.range(0, size.height)
                let angle = rng.range(0, .pi * 2)
                let length = rng.range(2.5, 8)
                // A fibre lies in the sheet, so it bows rather than running straight.
                let bow = rng.range(-1.4, 1.4)
                var path = Path()
                path.move(to: CGPoint(x: x, y: y))
                path.addQuadCurve(
                    to: CGPoint(x: x + cos(angle) * length, y: y + sin(angle) * length),
                    control: CGPoint(
                        x: x + cos(angle) * length / 2 - sin(angle) * bow,
                        y: y + sin(angle) * length / 2 + cos(angle) * bow
                    )
                )
                let colour = palette[Int(rng.next() % UInt64(palette.count))]
                context.stroke(
                    path,
                    with: .color(colour.opacity(rng.range(0.10, 0.26))),
                    style: StrokeStyle(lineWidth: rng.range(0.35, 0.7), lineCap: .round)
                )
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Guilloche

/// One guilloche rosette: a hypotrochoid, which is the curve a pen at distance
/// `penOffset` traces when a circle of radius `rollingRadius` rolls inside a
/// fixed circle of radius `fixedRadius`. This is the actual geometry a rose
/// engine cuts, which is why security printing looks the way it does.
///
/// The parametrisation, the greatest-common-divisor trick for finding where the
/// curve closes, and the `stride` sampling are the ones from Hacking with
/// Swift's "Creating a spirograph with SwiftUI" project; the same equations
/// drive `stabla/guillocheJS`.
///
///     x(θ) = (R - r)·cos θ + d·cos((R - r)/r · θ)
///     y(θ) = (R - r)·sin θ - d·sin((R - r)/r · θ)
///
/// The curve closes after `2π·r / gcd(R, r)` radians, and has `R / gcd(R, r)`
/// petals, so the two radii are chosen to land on a petal count rather than
/// eyeballed.
private struct GuillocheRosette: Shape {
    /// R, the fixed circle.
    var fixedRadius: Int
    /// r, the rolling circle.
    var rollingRadius: Int
    /// d, the pen's distance from the rolling circle's centre.
    var penOffset: Double
    /// Radians per sample. Smaller is smoother and more expensive.
    var step: Double = 0.045
    /// Rotation of the whole rosette, in radians. Superposing copies at
    /// slightly different rotations is what produces the interference moire
    /// that reads as engine turning.
    var rotation: Double = 0

    func path(in rect: CGRect) -> Path {
        let R = Double(fixedRadius)
        let r = Double(rollingRadius)
        guard r > 0 else { return Path() }

        let divisor = Double(Self.greatestCommonDivisor(fixedRadius, rollingRadius))
        let difference = R - r
        let end = ceil(2 * .pi * r / max(divisor, 1))

        // Normalise so the widest excursion just touches the frame.
        let extent = max(abs(difference) + penOffset, 0.0001)
        let unit = min(rect.width, rect.height) / 2 / extent

        let cosR = cos(rotation)
        let sinR = sin(rotation)

        var path = Path()
        var started = false
        for theta in stride(from: 0, through: end, by: step) {
            let baseX = difference * cos(theta) + penOffset * cos(difference / r * theta)
            let baseY = difference * sin(theta) - penOffset * sin(difference / r * theta)
            let point = CGPoint(
                x: rect.midX + (baseX * cosR - baseY * sinR) * unit,
                y: rect.midY + (baseX * sinR + baseY * cosR) * unit
            )
            if started {
                path.addLine(to: point)
            } else {
                path.move(to: point)
                started = true
            }
        }
        path.closeSubpath()
        return path
    }

    static func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
        var a = a, b = b
        while b != 0 { (a, b) = (b, a % b) }
        return max(a, 1)
    }
}

/// The lathe band a passport prints across a page head: a family of lines whose
/// two superposed harmonics drift out of phase, so the band shows the moire an
/// anti-scan pattern is designed to produce.
private struct GuillocheBand: View {
    var ink: Color
    var lines: Int = 9
    var amplitude: Double = 5

    var body: some View {
        Canvas { context, size in
            for index in 0..<lines {
                let phase = Double(index) / Double(max(lines - 1, 1))
                let baseY = size.height * (0.16 + 0.68 * phase)
                var path = Path()
                var x: Double = 0
                while x <= size.width {
                    let y = baseY
                        + sin(x / 21 + phase * 5.1) * amplitude
                        + sin(x / 8.5 - phase * 3.3) * amplitude * 0.34
                    if x == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                    x += 2.5
                }
                context.stroke(path, with: .color(ink.opacity(0.34)), lineWidth: 0.4)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Everything printed into the stock before anyone stamps it: the rosette
/// watermark, the lathe bands, and the fine anti-scan ruling.
///
/// All of it is stroked with a single split-fountain gradient rather than a flat
/// colour. Iris printing (two or three inks fed into one fountain so the hue
/// drifts across the sheet) is a real security-print feature and cannot be
/// reproduced with a photocopier, which is the point of it. It is also where the
/// destination's own colour enters the page: as a shift in the printed ink
/// rather than as interface chrome.
private struct SecurityPrint: View {
    var accent: Color
    var ink: Color

    private var irisInk: LinearGradient {
        LinearGradient(
            colors: [
                ink.opacity(0.30),
                accent.opacity(0.34),
                Color(hex: "8A7B57").opacity(0.30)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack {
            // Fine ruling across the whole page, the anti-scan ground.
            GuillocheBand(ink: ink.opacity(0.4), lines: 30, amplitude: 3.2)
                .opacity(0.5)

            // The rosette watermark. Three copies of one curve at small
            // rotational offsets; the interference between them is the effect.
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    GuillocheRosette(
                        fixedRadius: 90,
                        rollingRadius: 85,
                        penOffset: 30,
                        rotation: Double(index) * 0.052
                    )
                    .stroke(irisInk, lineWidth: 0.4)
                }
                // A tighter inner rosette, the way an engraved medallion nests.
                ForEach(0..<2, id: \.self) { index in
                    GuillocheRosette(
                        fixedRadius: 112,
                        rollingRadius: 105,
                        penOffset: 34,
                        rotation: 0.31 + Double(index) * 0.075
                    )
                    .stroke(irisInk, lineWidth: 0.35)
                    .padding(46)
                }
            }
            .compositingGroup()
            .opacity(0.85)

            GuillocheBand(ink: accent.opacity(0.5), lines: 7, amplitude: 4)
                .frame(height: 34)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 46)
                .opacity(0.7)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Passport page

private enum PassportMetrics {
    /// A TD3 booklet page is 88 by 125 mm. Keeping that ratio is most of what
    /// separates a passport page from a rounded rectangle.
    static let pageWidth: CGFloat = 276
    static let pageHeight: CGFloat = 392
    /// How much of the facing page stays visible past the binding.
    static let versoWidth: CGFloat = 26
    static let margin: CGFloat = 15
    static let cornerRadius: CGFloat = 7
}

/// An open passport held to the recto page: the sliver of the facing page, the
/// valley of the gutter between them, the block of remaining leaves showing at
/// the fore edge, and the printed page itself.
///
/// Shadows are layered rather than single, following the elevation rule in Josh
/// Comeau's "Designing Beautiful Shadows in CSS" and Material Design's elevation
/// scale: one light source for the whole scene, offset and blur roughly doubling
/// per layer while opacity falls, vertical offset twice the horizontal, and a
/// warm hue-matched shadow colour instead of pure black. A single shadow reads
/// as a sticker; the tight contact layer is what puts an object on a surface.
private struct PassportSpread<Overlay: View>: View {
    var accent: Color
    var pageNumber: String
    var mrzTop: String
    var mrzBottom: String
    @ViewBuilder var overlay: () -> Overlay

    private let paper = Theme.passportPaper
    private let furniture = Color(hex: "8A7B57")
    private let ink = Theme.passportInk
    /// Warm rather than neutral, matched to the counter the passport lies on.
    private let shadowInk = Color(hex: "150E04")

    var body: some View {
        ZStack(alignment: .leading) {
            bookBlock
            HStack(spacing: 0) {
                versoSliver
                rectoPage
            }
            .overlay(alignment: .leading) { gutter }
        }
        .compositingGroup()
        // Contact, mid and ambient. Light sits up and to the left, so every
        // offset runs down and right at a 1:2 horizontal to vertical ratio.
        .shadow(color: shadowInk.opacity(0.55), radius: 1.5, x: 1, y: 2)
        .shadow(color: shadowInk.opacity(0.34), radius: 7, x: 3, y: 6)
        .shadow(color: shadowInk.opacity(0.30), radius: 24, x: 9, y: 18)
    }

    /// The rest of the booklet showing at the fore edge and foot. Three offset
    /// leaves is enough to read as a bound block rather than a single sheet.
    private var bookBlock: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<3, id: \.self) { index in
                let step = CGFloat(index + 1)
                RoundedRectangle(cornerRadius: PassportMetrics.cornerRadius, style: .continuous)
                    .fill(Color(hex: "E3DAC4").opacity(1 - Double(index) * 0.22))
                    .frame(
                        width: PassportMetrics.versoWidth + PassportMetrics.pageWidth,
                        height: PassportMetrics.pageHeight
                    )
                    .offset(x: step * 1.4, y: step * 1.4)
            }
        }
        .allowsHitTesting(false)
    }

    /// The facing page, curving away into the binding. Only its printed ground
    /// is visible, and it darkens sharply toward the gutter.
    private var versoSliver: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "E7DFCB"), Color(hex: "D8CDB1")],
                startPoint: .leading, endPoint: .trailing
            )
            // Only the ruled ground, not the full rosette: 26 points of a page
            // that is curving into the binding does not earn the curve cost.
            GuillocheBand(ink: ink.opacity(0.4), lines: 30, amplitude: 3.2)
                .opacity(0.4)
            PaperGrain(opacity: 0.4)
            // The page curls into the spine, so the far edge lifts and the
            // near edge falls away.
            LinearGradient(
                colors: [.white.opacity(0.28), .clear, .black.opacity(0.34)],
                startPoint: .leading, endPoint: .trailing
            )
            .blendMode(.plusDarker)
            .opacity(0.9)
        }
        .frame(width: PassportMetrics.versoWidth, height: PassportMetrics.pageHeight)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: PassportMetrics.cornerRadius,
                bottomLeadingRadius: PassportMetrics.cornerRadius,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
    }

    /// The valley where the two pages meet the binding: dark at the seam,
    /// falling off in both directions, with a hairline of stitching light.
    private var gutter: some View {
        ZStack {
            LinearGradient(
                colors: [.clear, .black.opacity(0.42), .black.opacity(0.30), .clear],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: 34)
            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(width: 0.5)
                .offset(x: 1.5)
        }
        .frame(width: 34)
        .offset(x: PassportMetrics.versoWidth - 17)
        .blendMode(.multiply)
        .allowsHitTesting(false)
    }

    private var rectoPage: some View {
        ZStack {
            // Stock, warmed toward the gutter where less light reaches it.
            LinearGradient(
                colors: [paper, Color(hex: "EFE7D3")],
                startPoint: .topTrailing, endPoint: .bottomLeading
            )

            SecurityPrint(accent: accent, ink: ink)
                .padding(PassportMetrics.margin + 4)

            SecurityFibres(accent: accent)
            PaperGrain()

            printedFrame

            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                footer
            }
            .padding(.top, 16)
            .padding(.bottom, 12)
            .padding(.horizontal, PassportMetrics.margin + 6)

            microprintEdge

            overlay()
        }
        .frame(width: PassportMetrics.pageWidth, height: PassportMetrics.pageHeight)
        .compositingGroup()
        .overlay(alignment: .leading) {
            // The recto also bends into the spine.
            LinearGradient(colors: [.black.opacity(0.20), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 30)
                .blendMode(.multiply)
                .allowsHitTesting(false)
        }
        .overlay {
            // Fore-edge lift plus a soft page vignette, so the sheet is not flat.
            LinearGradient(colors: [.clear, .white.opacity(0.22)],
                           startPoint: .leading, endPoint: .trailing)
                .blendMode(.softLight)
                .allowsHitTesting(false)
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: PassportMetrics.cornerRadius,
                topTrailingRadius: PassportMetrics.cornerRadius,
                style: .continuous
            )
        )
    }

    /// Two keylines and corner rules, the way a visa page is pre-printed to mark
    /// the area an officer may stamp.
    private var printedFrame: some View {
        ZStack {
            Rectangle()
                .strokeBorder(furniture.opacity(0.42), lineWidth: 0.8)
                .padding(PassportMetrics.margin)
            Rectangle()
                .strokeBorder(furniture.opacity(0.20), lineWidth: 0.4)
                .padding(PassportMetrics.margin + 3.5)
        }
        .allowsHitTesting(false)
    }

    private var header: some View {
        VStack(spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("VOYAGE PASSPORT")
                    .font(.system(size: 9, weight: .heavy))
                    .kerning(2.4)
                Spacer(minLength: 4)
                Text(pageNumber)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .kerning(1)
            }
            .foregroundStyle(furniture)

            Rectangle()
                .fill(furniture.opacity(0.45))
                .frame(height: 0.6)

            HStack {
                Text("ENDORSEMENTS AND ENTRIES")
                    .font(.system(size: 7, weight: .bold))
                    .kerning(1.6)
                Spacer(minLength: 4)
                Text("TYPE P")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .kerning(1)
            }
            .foregroundStyle(furniture.opacity(0.72))
        }
    }

    private var footer: some View {
        VStack(spacing: 5) {
            microprintLine
            Rectangle()
                .fill(furniture.opacity(0.35))
                .frame(height: 0.5)
            machineReadableZone
        }
    }

    /// Microprinting: text set far below the resolution a copier can hold, which
    /// reads as a grey rule at arm's length and resolves into words up close.
    private var microprintLine: some View {
        // Sized so the repeat fills the measure without truncating: at 2.6 point
        // monospaced the advance is about 1.56 points, so roughly 150 characters
        // span the 234 points inside the printed frame.
        Text(String(repeating: "VOYAGEAIR·", count: 15))
            .font(.system(size: 2.6, weight: .semibold, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(furniture.opacity(0.55))
            .accessibilityHidden(true)
    }

    private var microprintEdge: some View {
        Text(String(repeating: "VOYAGEAIR·", count: 23))
            .font(.system(size: 2.6, weight: .semibold, design: .monospaced))
            .lineLimit(1)
            .foregroundStyle(furniture.opacity(0.45))
            .fixedSize()
            .rotationEffect(.degrees(-90))
            .frame(width: 6, height: PassportMetrics.pageHeight - PassportMetrics.margin * 2)
            .clipped()
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, PassportMetrics.margin + 4)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var machineReadableZone: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(mrzTop)
            Text(mrzBottom)
        }
        // OCR-B is the specified face. Monospaced is the closest system stand-in,
        // and the fixed advance is what makes the zone read as machine input.
        .font(.system(size: 8, weight: .medium, design: .monospaced))
        .lineLimit(1)
        .minimumScaleFactor(0.4)
        .foregroundStyle(Color(hex: "3A3427").opacity(0.72))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }
}

// MARK: - Entry cachet

/// Worn rubber: soft holes punched out of the mark so ink coverage is uneven,
/// plus heavier bare patches where the die has aged. Applied with
/// `.destinationOut` over a compositing group, which is the SwiftUI equivalent
/// of masking a distress texture out of a stamp layer in Photoshop.
private struct CachetWear: View {
    var seed: UInt64

    var body: some View {
        Canvas { context, size in
            var rng = StampRNG(seed: seed)
            // Fine dropout across the whole mark.
            for _ in 0..<150 {
                let x = rng.range(0, size.width)
                let y = rng.range(0, size.height)
                let radius = rng.range(0.4, 2.6)
                context.fill(
                    Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                                           width: radius * 2, height: radius * 2)),
                    with: .color(.white.opacity(rng.range(0.12, 0.62)))
                )
            }
            // A few larger worn patches so one part of the die presses lighter.
            for _ in 0..<8 {
                let x = rng.range(0, size.width)
                let y = rng.range(0, size.height)
                let radius = rng.range(6, 22)
                context.fill(
                    Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                                           width: radius * 2, height: radius * 2)),
                    with: .color(.white.opacity(rng.range(0.08, 0.16)))
                )
            }
        }
        .allowsHitTesting(false)
    }
}

/// The three things that separate a stamped mark from a printed badge: ink
/// bleeds a little past the die, coverage is uneven, and the hand that pressed
/// it was not level, so one side takes more ink than the other.
private struct Inked: ViewModifier {
    var seed: UInt64

    func body(content: Content) -> some View {
        content
            .compositingGroup()
            // Bleed: a soft darker echo spread under the mark.
            .background(content.blur(radius: 1.4).opacity(0.35))
            .compositingGroup()
            .overlay(CachetWear(seed: seed).blendMode(.destinationOut))
            .compositingGroup()
            // The roll: the die landed heel first, so the ink thins across it.
            .mask {
                LinearGradient(
                    colors: [.white, .white, .white.opacity(0.74)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
            .blur(radius: 0.35)
    }
}

private extension View {
    func inked(seed: UInt64) -> some View { modifier(Inked(seed: seed)) }
}

/// The inked cachet pressed into the page.
///
/// A real entry stamp carries the port of entry, the date, and the mode of
/// arrival, inside a keyline with corner register ticks. It is not a clean
/// vector badge: the keyline doubles and wobbles, the ink is uneven, and the
/// whole mark multiplies into the paper instead of sitting on top of it.
private struct ArrivalCachet: View {
    let code: String
    let city: String
    let dateText: String
    let milesText: String
    var ink: Color = Theme.passportInk
    var seed: UInt64 = 907

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 7) {
                rule
                Text("ADMITTED")
                    .font(.system(size: 10.5, weight: .heavy))
                    .kerning(2.5)
                    .fixedSize()
                Image(systemName: "airplane")
                    .font(.system(size: 9, weight: .black))
                rule
            }

            Text(code)
                .font(.system(size: 46, weight: .black, design: .monospaced))
                .kerning(2)
                .padding(.top, 1)

            Text(city.uppercased())
                .font(.system(size: 10, weight: .bold))
                .kerning(3.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Rectangle()
                .fill(ink)
                .frame(width: 78, height: 0.9)
                .padding(.top, 4)

            Text(dateText)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .kerning(1.5)
                .padding(.top, 3)

            Text("AIR · \(milesText)")
                .font(.system(size: 8.5, weight: .heavy))
                .kerning(1.6)
                .padding(.top, 1)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 26)
        .padding(.vertical, 16)
        .overlay(cornerTicks)
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(ink, lineWidth: 2.6)
        )
        // A second pass of the same keyline, a hair off register. A die that is
        // pressed by hand never lands twice in the same place.
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(ink.opacity(0.42), lineWidth: 1.1)
                .offset(x: 0.7, y: -0.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(ink.opacity(0.9), lineWidth: 1)
                .padding(-4)
        )
        .inked(seed: seed)
        .opacity(0.94)
        // Ink darkens paper, it does not cover it: the grain, the guilloche and
        // the ticket edge all stay visible through the mark.
        .blendMode(.multiply)
    }

    private var rule: some View {
        Rectangle().fill(ink).frame(width: 22, height: 1).opacity(0.9)
    }

    private var cornerTicks: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let len: CGFloat = 9, inset: CGFloat = 7
            Path { p in
                // Four L-shaped register ticks.
                for corner in 0..<4 {
                    let right = corner % 2 == 1
                    let bottom = corner >= 2
                    let x = right ? w - inset : inset
                    let y = bottom ? h - inset : inset
                    let dx: CGFloat = right ? -len : len
                    let dy: CGFloat = bottom ? -len : len
                    p.move(to: CGPoint(x: x, y: y))
                    p.addLine(to: CGPoint(x: x + dx, y: y))
                    p.move(to: CGPoint(x: x, y: y))
                    p.addLine(to: CGPoint(x: x, y: y + dy))
                }
            }
            .stroke(ink, lineWidth: 1.4)
        }
    }
}

// MARK: - Tucked ticket

/// The boarding pass stub, slipped into the passport page. Deliberately small
/// and partly angled: it reads as a keepsake tucked between pages, not a second
/// card competing with the stamp.
private struct TuckedTicket: View {
    let origin: Airport
    let destination: Airport
    let flightNumber: String
    let seat: String
    let dateText: String

    private let paper = Color(hex: "FBF8F1")
    private let ink = Color(hex: "2A2F3A")
    private let shadowInk = Color(hex: "150E04")

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("BOARDING PASS")
                    .font(.system(size: 5.5, weight: .heavy))
                    .kerning(0.9)
                    .foregroundStyle(ink.opacity(0.5))

                HStack(spacing: 5) {
                    Text(origin.code)
                        .font(.system(size: 17, weight: .black, design: .monospaced))
                    Image(systemName: "airplane")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.passportInk)
                    Text(destination.code)
                        .font(.system(size: 17, weight: .black, design: .monospaced))
                }
                .foregroundStyle(ink)

                Text(dateText)
                    .font(.system(size: 6, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ink.opacity(0.55))
            }

            Spacer(minLength: 6)

            // The stub half that stays with the traveler. Fixed width so the
            // tear line lands exactly on `stubInset`, keeping the die-cut
            // notches, the punched holes and the printed rule in one column.
            VStack(alignment: .trailing, spacing: 3) {
                stubField("FLIGHT", flightNumber)
                stubField("SEAT", seat)
            }
            .frame(width: Self.stubInset - 18, alignment: .trailing)
            .padding(.leading, 8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(width: 196)
        .background(
            TicketStub(notchInset: Self.stubInset)
                .fill(
                    // Not flat stock: a faint gradient so the card catches the
                    // page light instead of reading as a pasted rectangle.
                    LinearGradient(
                        colors: [paper, Color(hex: "F1ECE1")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            TicketStub(notchInset: Self.stubInset)
                .stroke(ink.opacity(0.14), lineWidth: 0.6)
        )
        .overlay(alignment: .trailing) { perforationHoles }
        .overlay(PaperGrain(opacity: 0.35).clipShape(TicketStub(notchInset: Self.stubInset)))
        .clipShape(TicketStub(notchInset: Self.stubInset))
        // Same layered rule as the booklet, one step shallower: a tight contact
        // shadow where card meets page, then a wider cast shadow. One shadow
        // alone reads as a sticker.
        .shadow(color: shadowInk.opacity(0.34), radius: 1.2, x: 0.5, y: 1)
        .shadow(color: shadowInk.opacity(0.22), radius: 5, x: 1.5, y: 3)
        .overlay { cornerHolders }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Boarding pass, \(origin.code) to \(destination.code), flight \(flightNumber), seat \(seat)"
        )
    }

    /// Distance from the trailing edge to the perforation, shared by the
    /// outline notches and the punched holes so they always line up.
    private static let stubInset: CGFloat = 62

    /// Punched holes down the tear line. A dashed rule reads as printed; holes
    /// read as a card that was actually torn off a stub.
    private var perforationHoles: some View {
        GeometryReader { proxy in
            let x = proxy.size.width - Self.stubInset
            ZStack {
                // Faint printed guide, the way a real stub prints one behind
                // the perforation.
                DashedRule()
                    .stroke(ink.opacity(0.22),
                            style: StrokeStyle(lineWidth: 0.7, dash: [2, 2.5]))
                    .frame(width: 1)

                VStack(spacing: 0) {
                    ForEach(0..<9, id: \.self) { _ in
                        Circle()
                            .fill(ink.opacity(0.18))
                            .frame(width: 1.6, height: 1.6)
                            .frame(maxHeight: .infinity)
                    }
                }
                .frame(width: 2)
            }
            .frame(height: proxy.size.height - 6)
            .position(x: x, y: proxy.size.height / 2)
        }
        .allowsHitTesting(false)
    }

    /// Paper corners holding the stub to the page, the way a passport or album
    /// actually carries one. This is what makes it read as slipped in rather
    /// than laid on top: the page is drawn over the card, not under it.
    private var cornerHolders: some View {
        ZStack {
            PaperCorner()
                .frame(width: 26, height: 26)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            PaperCorner()
                .rotationEffect(.degrees(180))
                .frame(width: 26, height: 26)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .allowsHitTesting(false)
    }

    private func stubField(_ label: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(label)
                .font(.system(size: 5, weight: .heavy))
                .kerning(0.7)
                .foregroundStyle(ink.opacity(0.45))
            Text(value)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(ink)
        }
    }
}

/// A single vertical rule, used as the stub perforation.
private struct DashedRule: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

/// Boarding-pass outline: a rounded card with a semicircular notch bitten out
/// of the top and bottom edges at the tear line, the way a real stub is die-cut
/// so it snaps off cleanly.
private struct TicketStub: Shape {
    /// Distance from the trailing edge to the tear line.
    let notchInset: CGFloat
    var cornerRadius: CGFloat = 5
    var notchRadius: CGFloat = 3.2

    func path(in rect: CGRect) -> Path {
        let x = rect.maxX - notchInset
        var path = Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)

        // Subtract a half-disc from each long edge at the tear line.
        var notches = Path()
        notches.addEllipse(in: CGRect(
            x: x - notchRadius, y: rect.minY - notchRadius,
            width: notchRadius * 2, height: notchRadius * 2
        ))
        notches.addEllipse(in: CGRect(
            x: x - notchRadius, y: rect.maxY - notchRadius,
            width: notchRadius * 2, height: notchRadius * 2
        ))
        path = path.subtracting(notches)
        return path
    }
}

/// One triangular paper corner, drawn over the card it holds. The fold
/// highlight along the hypotenuse is what sells it as a lifted flap of stock
/// rather than a flat triangle.
private struct PaperCorner: View {
    var body: some View {
        ZStack {
            Triangle()
                .fill(
                    LinearGradient(
                        colors: [Theme.passportPaper, Color(hex: "DCD2B8")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            // Crease: a bright fold edge with its own shadow beneath.
            Triangle()
                .stroke(.white.opacity(0.55), lineWidth: 0.5)
            Triangle()
                .fill(.clear)
                .overlay(
                    Triangle()
                        .stroke(.black.opacity(0.18), lineWidth: 0.5)
                        .offset(x: 0.5, y: 0.5)
                        .mask(Triangle())
                )
        }
        .shadow(color: .black.opacity(0.22), radius: 1.5, x: 1, y: 1)
    }
}

/// Right triangle filling its frame from the top-left corner.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Color blending

private extension Color {
    /// Linear blend in sRGB. iOS 18 has `Color.mix(with:by:)`; this project
    /// targets iOS 17, so the components are read through `UIColor`.
    static func blended(_ a: Color, with b: Color, amount: Double) -> Color {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        guard UIColor(a).getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
              UIColor(b).getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else { return a }
        let t = CGFloat(min(max(amount, 0), 1))
        return Color(
            .sRGB,
            red: Double(r1 + (r2 - r1) * t),
            green: Double(g1 + (g2 - g1) * t),
            blue: Double(b1 + (b2 - b1) * t),
            opacity: Double(a1 + (a2 - a1) * t)
        )
    }
}

// MARK: - Destination imagery

/// Satellite imagery of the city you just flew into, behind the welcome card.
///
/// Rendered with `MKMapSnapshotter` rather than a live `Map`, because this is a
/// still backdrop: a snapshot costs one render instead of holding a map engine
/// alive behind a screen the traveler passes through in seconds. Map imagery is
/// also the licensable way to show a real place. Bundling landmark photography
/// would mean shipping someone else's copyrighted work.
private struct DestinationImageryView: View {
    let airport: Airport

    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .task(id: airport.code) {
                await load(size: geometry.size)
            }
        }
        .accessibilityHidden(true)
    }

    /// Snapshotting is off the main actor by way of `start()`'s async form, so
    /// the arrival animation never waits on tiles. Failure is silent on purpose:
    /// the gradient underneath is already a complete background.
    private func load(size: CGSize) async {
        guard image == nil, size.width > 1, size.height > 1 else { return }

        let options = MKMapSnapshotter.Options()
        options.size = size
        options.scale = displayScale
        options.mapType = .satelliteFlyover
        options.pointOfInterestFilter = .excludingAll
        options.showsBuildings = true
        // Wide enough to take in the city and its coastline or terrain, rather
        // than framing the runway the traveler just landed on.
        options.region = MKCoordinateRegion(
            center: airport.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.42, longitudeDelta: 0.42)
        )

        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return }
        await MainActor.run {
            withAnimation(.smooth(duration: 0.8)) { image = snapshot.image }
        }
    }
}
