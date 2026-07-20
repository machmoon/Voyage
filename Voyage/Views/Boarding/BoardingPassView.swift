import SwiftUI

/// The boarding pass prints down into view (with the dot-matrix sound to
/// match), then a drag-to-tear gesture along the perforation starts the
/// flight. Tearing IS departing — this is the commitment moment.
struct BoardingPassView: View {
    @Bindable var session: FlightSession
    let onBoarded: () -> Void

    @State private var printed = false
    /// 0→1 feed progress: the pass emerges below the slot in line-feed steps.
    @State private var printProgress: CGFloat = 0
    /// Positive = stub pulled down away from the body (vertical tear).
    @State private var tearTranslation: CGFloat = 0
    @State private var ripped = false
    @State private var lastRatchetStep = 0
    /// Torn paper fibers that burst from the perforation on rip.
    @State private var shreds: [PaperShred] = []
    /// Flipped one frame after the shreds are inserted so their fall animates.
    @State private var shredsFlying = false

    private var leg: FlightLeg { session.itinerary.legs[0] }

    /// Operating carrier from the flight number's airline code ("UA 1546").
    private var carrierName: String {
        let code = leg.flightNumber.prefix { !$0.isWhitespace }
        return Carrier(rawValue: String(code))?.name.uppercased() ?? "VOYAGE AIR"
    }

    private var gate: String {
        var hash: UInt64 = 5381
        for byte in leg.flightNumber.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        return "B\(hash % 22 + 1)"
    }

    private var cabinClass: String {
        guard let row = Int(session.seat.filter(\.isNumber)) else { return "MAIN" }
        return (1...2).contains(row) ? "FIRST" : "MAIN"
    }

    /// Distance the stub must travel before the tear commits.
    private let tearThreshold: CGFloat = 72

    var body: some View {
        ZStack {
            // Solid backdrop so the perforation punch-outs match exactly.
            Theme.boardingBackdrop
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 12)

                printerSlot
                    .zIndex(2)

                // Everything above the slot is inside the machine; the pass
                // feeds out beneath it, one line at a time. Clipping only
                // lasts while printing so the torn stub can fall freely after.
                Group {
                    if printed {
                        passCard
                            .padding(.horizontal, 28)
                    } else {
                        passCard
                            .padding(.horizontal, 28)
                            .offset(y: -560 * (1 - printProgress))
                            .clipped()
                    }
                }
                .overlay { shredBurst }

                Spacer()

                if printed && !ripped {
                    airplaneModeReminder
                        .padding(.bottom, 14)

                    Button {
                        rip()
                    } label: {
                        Text("Tear & board")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.12), in: Capsule())
                    }
                    .accessibilityLabel("Tear and board")
                    .accessibilityHint("Tears the boarding pass stub and departs")
                }

                Text(ripped ? "Boarding…" : "Pull the stub down to tear & board")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(printed ? 0.65 : 0))
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                    .animation(.smooth(duration: 0.4), value: printed)
            }
        }
        .onAppear { startPrinting() }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text("Tear & board")) {
            guard printed, !ripped else { return }
            rip()
        }
    }

    /// iOS can't flip Airplane Mode for you — this keeps the ritual visible
    /// right where you commit, instead of on a page of its own.
    private var airplaneModeReminder: some View {
        HStack(spacing: 8) {
            Image(systemName: "airplane")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.accent)
            Text("Airplane Mode on — nothing interrupts this flight")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.white.opacity(0.07), in: Capsule())
        .transition(.opacity)
    }

    /// Gaps between line feeds — irregular, like a real gate printer that
    /// pauses on dense lines. The sound engine plays a burst per feed from
    /// this same schedule, so what you hear is what you see.
    static let feedSchedule: [Double] = [0.20, 0.15, 0.15, 0.30, 0.16, 0.16, 0.32, 0.18, 0.22]

    /// Slim printer mouth the pass feeds out of, with a print-head glow
    /// while it's working.
    private var printerSlot: some View {
        Capsule()
            .fill(.black.opacity(0.55))
            .frame(height: 5)
            .overlay(
                Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
            )
            .overlay(
                Capsule()
                    .fill(Theme.accent.opacity(printed ? 0 : (printProgress > 0 ? 0.85 : 0)))
                    .frame(width: 44, height: 3)
                    .blur(radius: 2)
                    .animation(.smooth(duration: 0.5), value: printed)
            )
            .padding(.horizontal, 36)
            .accessibilityHidden(true)
    }

    /// Discrete line feeds — advance, settle, advance — driven by
    /// `feedSchedule`, with a haptic tick per line and the printer audio
    /// running off the identical timing.
    private func startPrinting() {
        guard !printed else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            let schedule = Self.feedSchedule
            CabinAudioEngine.shared.playPrinter(feedSchedule: schedule)
            for (line, gap) in schedule.enumerated() {
                withAnimation(.spring(duration: 0.13, bounce: 0.2)) {
                    printProgress = CGFloat(line + 1) / CGFloat(schedule.count)
                }
                Haptics.softTick()
                try? await Task.sleep(for: .milliseconds(Int(gap * 1000)))
            }
            printed = true
        }
    }

    // MARK: Pass card — two separate paper pieces

    private var passCard: some View {
        VStack(spacing: 0) {
            bodyPiece
            stubPiece
        }
        // The pass is printed paper — always light, even in dark mode.
        .environment(\.colorScheme, .light)
    }

    /// Main ticket body with its own fill/shadow. After a rip, the bottom
    /// edge becomes ragged where the stub tore away.
    private var bodyPiece: some View {
        VStack(spacing: 0) {
            passBody
            if !ripped {
                perforation
            } else {
                Color.clear.frame(height: 8)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(PassBodyPaper(torn: ripped))
        .compositingGroup()
        .shadow(color: .black.opacity(ripped ? 0.35 : 0.45), radius: ripped ? 16 : 22, y: 12)
        // Paper recoils upward slightly when the stub lets go.
        .offset(y: ripped ? -7 : 0)
        .animation(.spring(duration: 0.45, bounce: 0.55), value: ripped)
    }

    /// Classic paper ticket: ink on white, no colored chrome.
    private var passBody: some View {
        VStack(spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    FieldLabel("Boarding pass")
                    Text(carrierName)
                        .font(.system(size: 15, weight: .heavy))
                        .kerning(2)
                }
                Spacer()
                Text(leg.flightNumber)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.itinerary.origin.code)
                        .font(.system(size: 38, weight: .heavy, design: .monospaced))
                    Text(session.itinerary.origin.city)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(spacing: 3) {
                    Image(systemName: "airplane")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    if let via = session.itinerary.connection {
                        Text("via \(via.code)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(session.itinerary.destination.code)
                        .font(.system(size: 38, weight: .heavy, design: .monospaced))
                    Text(session.itinerary.destination.city)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 0) {
                passField("Passenger", "FOCUSED FLYER")
                passField("Class", cabinClass)
                passField("Gate", gate)
            }

            HStack(spacing: 0) {
                passField("Board", "NOW")
                passField("Focus", session.itinerary.totalFocusDuration.shortDurationText)
                passField("Bags", session.intentions.isEmpty ? "—" : "\(session.intentions.count)")
            }
        }
        .padding(22)
        .padding(.bottom, ripped ? 4 : 0)
    }

    private func passField(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            FieldLabel(label)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Real perforation: side notches plus a row of punched holes, all
    /// filled with the backdrop color so they read as actual cutouts.
    private var perforation: some View {
        HStack(spacing: 0) {
            halfNotch(leading: true)
            GeometryReader { geo in
                let holeCount = max(8, Int(geo.size.width / 16))
                let spacing = geo.size.width / CGFloat(holeCount)
                HStack(spacing: 0) {
                    ForEach(0..<holeCount, id: \.self) { _ in
                        Circle()
                            .fill(Theme.boardingBackdrop)
                            .frame(width: 4.5, height: 4.5)
                            .frame(width: spacing)
                    }
                }
                .frame(height: geo.size.height)
            }
            halfNotch(leading: false)
        }
        .frame(height: 22)
        .background(Color(.systemBackground))
    }

    private func halfNotch(leading: Bool) -> some View {
        Circle()
            .fill(Theme.boardingBackdrop)
            .frame(width: 22, height: 22)
            .offset(x: leading ? -11 : 11)
    }

    // MARK: Stub + tear gesture

    private var stubPiece: some View {
        let progress = min(1, max(0, tearTranslation) / tearThreshold)
        // The paper tracks the finger exactly; a whisper of shear from the
        // leading corner, nothing theatrical.
        let dragY = ripped ? 420 : max(0, tearTranslation)
        let angle = ripped ? 5.0 : Double(progress * 2.5)
        // Paper curls toward you as it's peeled off the perforation.
        let curl = ripped ? 42.0 : Double(progress * 20)

        return stubContent
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 20)
            .background(Color(.systemBackground))
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 18,
                    bottomTrailingRadius: 18,
                    topTrailingRadius: 0,
                    style: .continuous
                )
            )
            // Matching top tear when separating so the stub looks like torn paper.
            .overlay(alignment: .top) {
                if tearTranslation > 2 || ripped {
                    TornEdge()
                        .fill(Color(.systemBackground))
                        .frame(height: 8)
                        .rotationEffect(.degrees(180))
                        .offset(y: -4)
                        .allowsHitTesting(false)
                }
            }
            .compositingGroup()
            .shadow(
                color: .black.opacity(progress > 0 || ripped ? 0.28 + 0.22 * progress : 0.08),
                radius: progress > 0 || ripped ? 10 + 8 * progress : 2,
                y: progress > 0 || ripped ? 6 + 6 * progress : 1
            )
            .contentShape(Rectangle())
            .rotation3DEffect(.degrees(curl), axis: (x: 1, y: 0, z: 0),
                              anchor: .top, perspective: 0.55)
            .offset(y: dragY)
            .rotationEffect(.degrees(angle), anchor: .topLeading)
            .opacity(ripped ? 0 : 1)
            .gesture(tearGesture())
            .animation(ripped ? .easeIn(duration: 0.45) : nil, value: ripped)
            .accessibilityHidden(ripped)
    }

    private var stubContent: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                FieldLabel("Seat")
                Text(session.seat)
                    .font(.system(size: 22, weight: .heavy, design: .monospaced))
            }
            Spacer()
            BarcodeView(seed: leg.flightNumber + session.seat)
                .frame(width: 150, height: 44)
            Image(systemName: "hand.draw.fill")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }

    private func tearGesture() -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard printed, !ripped else { return }
                // Vertical tear along the perforation: only the downward pull counts.
                tearTranslation = max(0, value.translation.height)

                let step = Int(tearTranslation / (tearThreshold * 0.12))
                if step != lastRatchetStep {
                    // Fibers popping one perforation at a time (pull only).
                    if step > lastRatchetStep {
                        CabinAudioEngine.shared.playTearTick()
                    }
                    lastRatchetStep = step
                    Haptics.ratchet()
                }
                if tearTranslation > tearThreshold {
                    rip()
                }
            }
            .onEnded { _ in
                guard !ripped else { return }
                withAnimation(.spring(duration: 0.4)) {
                    tearTranslation = 0
                }
                lastRatchetStep = 0
            }
    }

    private func rip() {
        guard !ripped else { return }
        ripped = true
        Haptics.rip()
        CabinAudioEngine.shared.playRip()
        // Paper fibers burst from the perforation line.
        var rng = SeededRandom(seed: UInt64(abs(session.seat.hashValue)) | 1)
        shreds = (0..<9).map { _ in PaperShred(rng: &rng) }
        DispatchQueue.main.async { shredsFlying = true }
        Task { @MainActor in
            // Let the stub fly off before departing; also gives the rip
            // one-shot time to finish before depart starts ambience.
            try? await Task.sleep(for: .milliseconds(750))
            onBoarded()
        }
    }

    // MARK: Shred burst

    @ViewBuilder
    private var shredBurst: some View {
        GeometryReader { geo in
            // The perforation sits just above the stub, ~76 pt from the bottom.
            let seamY = geo.size.height - 76
            ForEach(shreds) { shred in
                Capsule()
                    .fill(.white.opacity(shredsFlying ? 0 : 0.9))
                    .frame(width: shred.size, height: shred.size * 0.45)
                    .rotationEffect(.degrees(shredsFlying ? shred.spin : 0))
                    .position(x: geo.size.width * shred.x, y: seamY)
                    .offset(y: shredsFlying ? shred.fall : 0)
                    .animation(.easeIn(duration: 0.7).delay(shred.delay), value: shredsFlying)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One torn paper fiber: randomized size, lane, fall, and tumble.
private struct PaperShred: Identifiable {
    let id = UUID()
    let x: Double
    let size: Double
    let fall: Double
    let spin: Double
    let delay: Double

    init(rng: inout SeededRandom) {
        x = 0.08 + rng.next() * 0.84
        size = 5 + rng.next() * 7
        fall = 60 + rng.next() * 160
        spin = (rng.next() - 0.5) * 240
        delay = rng.next() * 0.08
    }
}

// MARK: - Paper shapes

/// Main pass silhouette: rounded top, flat or ragged bottom.
private struct PassBodyPaper: Shape {
    var torn: Bool

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 22
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))

        if torn {
            // Ragged tear along the bottom edge.
            let teeth = 14
            let step = rect.width / CGFloat(teeth)
            for i in 0..<teeth {
                let x = rect.maxX - CGFloat(i + 1) * step
                let dip: CGFloat = (i % 2 == 0) ? 7 : 2
                path.addLine(to: CGPoint(x: x + step * 0.5, y: rect.maxY + dip))
                path.addLine(to: CGPoint(x: x, y: rect.maxY + (i % 2 == 0 ? 1 : 6)))
            }
        } else {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }

        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// Thin jagged strip used as a torn-paper accent on the body/stub seam.
private struct TornEdge: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let teeth = 16
        let step = rect.width / CGFloat(teeth)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        for i in 0..<teeth {
            let x0 = rect.minX + CGFloat(i) * step
            let x1 = x0 + step * 0.5
            let x2 = x0 + step
            let peak: CGFloat = (i % 2 == 0) ? rect.maxY : rect.midY
            path.addLine(to: CGPoint(x: x1, y: peak))
            path.addLine(to: CGPoint(x: x2, y: rect.minY + (i % 2 == 0 ? 2 : 0)))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// Fake 1D barcode drawn from a deterministic seed.
struct BarcodeView: View {
    let seed: String

    var body: some View {
        Canvas { context, size in
            var hash: UInt64 = 14695981039346656037
            for byte in seed.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
            var x: CGFloat = 0
            var state = hash
            while x < size.width {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                let barWidth = CGFloat(state % 4) + 1
                let gap = CGFloat((state >> 8) % 3) + 1
                let rect = CGRect(x: x, y: 0, width: barWidth, height: size.height)
                context.fill(Path(rect), with: .color(.primary.opacity(0.85)))
                x += barWidth + gap
            }
        }
    }
}
