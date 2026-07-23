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
    @State private var ripped = false
    /// 0→1 progress of sliding a cut across the perforation line.
    @State private var cutProgress: CGFloat = 0
    @State private var lastCutStep = 0

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


    var body: some View {
        ZStack {
            // Solid backdrop so the perforation punch-outs match exactly.
            Theme.boardingBackdrop
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 12)

                // The printer prints the pass, then slides up and vanishes,
                // leaving just the ticket. Removed (not hidden) so nothing
                // lingers; the layout animates so the ticket settles smoothly.
                if !printed {
                    printerHousing
                        .zIndex(2)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // The pass feeds out of the housing's slot, one line at a time.
                // A small negative top inset tucks the emerging edge under the
                // housing lip so it reads as coming *through* the slot. Clipping
                // only lasts while printing so the torn stub can fall freely.
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
                .padding(.top, printed ? 0 : -7)

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

                Text(ripped ? "Boarding…" : "Slide across the tear line to board")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(printed ? 0.65 : 0))
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                    .animation(.smooth(duration: 0.4), value: printed)
            }
            .animation(.smooth(duration: 0.5), value: printed)
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

    /// The gate printer the pass feeds out of: an ink-blue housing (the app's
    /// surface palette, not heavy black chrome) with a status light that pulses
    /// while printing, and a recessed slot along its bottom lip that the ticket
    /// emerges through. `working` glows the slot's print-head bar.
    private var printerHousing: some View {
        let working = !printed && printProgress > 0
        return ZStack(alignment: .bottom) {
            // Machine body
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(
                    LinearGradient(colors: [Theme.surfaceElevated, Theme.surfaceDark],
                                   startPoint: .top, endPoint: .bottom)
                )
                .frame(height: 58)
                .overlay(alignment: .top) {
                    HStack(spacing: 8) {
                        // Print-status light: accent while feeding, calm when done.
                        Circle()
                            .fill(printed ? Color(hex: "6FCF97") : Theme.accent)
                            .frame(width: 7, height: 7)
                            .shadow(color: (printed ? Color(hex: "6FCF97") : Theme.accent)
                                .opacity(working ? 0.9 : 0.4),
                                    radius: working ? 5 : 2)
                            .opacity(working ? 1 : 0.85)
                        Text(printed ? "READY" : "PRINTING")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .kerning(1.2)
                            .foregroundStyle(.white.opacity(0.35))
                        Spacer()
                        // Paper-feed vents.
                        HStack(spacing: 3) {
                            ForEach(0..<3, id: \.self) { _ in
                                Capsule().fill(.white.opacity(0.09)).frame(width: 16, height: 3)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 11)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)

            // Recessed slot along the bottom lip — the mouth the pass feeds from.
            Capsule()
                .fill(.black.opacity(0.7))
                .frame(height: 6)
                .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
                .overlay(
                    Capsule()
                        .fill(Theme.accent.opacity(working ? 0.85 : 0))
                        .frame(height: 3)
                        .blur(radius: 2)
                        .padding(.horizontal, 40)
                        .animation(.smooth(duration: 0.5), value: printed)
                )
                .padding(.horizontal, 6)
                .offset(y: 4)
        }
        .padding(.horizontal, 22)
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

    /// Main ticket body with its own fill/shadow. The bottom edge stays a clean
    /// cut after the rip — ragged paper teeth read as debris at this size.
    private var bodyPiece: some View {
        VStack(spacing: 0) {
            passBody
            if !ripped {
                perforation
            } else {
                // Keep the same height as the perforation so the printer housing
                // above doesn't jump when the stub tears away.
                Color.clear.frame(height: 22)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(PassBodyPaper())
        .compositingGroup()
        .shadow(color: .black.opacity(ripped ? 0.35 : 0.45), radius: ripped ? 16 : 22, y: 12)
        // The body stays put — only the stub tears away below it.
        .animation(.smooth(duration: 0.4), value: ripped)
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

    /// A real ticket tear line — side notches plus a dashed perforation bar
    /// (not round dots). Slide a finger along it to cut; the seam opens behind
    /// your fingertip and separates the stub cleanly.
    private var perforation: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let cutX = w * cutProgress
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    halfNotch(leading: true)
                    tearLine
                    halfNotch(leading: false)
                }

                // The parted section: the same hairline the dashes sit on,
                // opened solid from the leading edge to the fingertip. Kept at
                // dash thickness so the seam reads as a cut, not a dark bar.
                if cutProgress > 0.001 {
                    Capsule()
                        .fill(Theme.boardingBackdrop)
                        .frame(width: max(3, cutX), height: 3)
                }
            }
            .frame(height: geo.size.height, alignment: .center)
            // Tall, generous hit area so the horizontal slide is easy to catch.
            .contentShape(Rectangle().inset(by: -16))
            .gesture(cutGesture())
        }
        .frame(height: 22)
        .background(Color(.systemBackground))
        .accessibilityLabel("Tear line — slide across to tear")
    }

    /// Dashed perforation line: longer marks than dots, in the backdrop color so
    /// it reads as a real ticket tear line punched across the paper.
    private var tearLine: some View {
        GeometryReader { geo in
            let midY = geo.size.height / 2
            Path { path in
                path.move(to: CGPoint(x: 2, y: midY))
                path.addLine(to: CGPoint(x: geo.size.width - 2, y: midY))
            }
            .stroke(Theme.boardingBackdrop,
                    style: StrokeStyle(lineWidth: 3, lineCap: .butt, dash: [9, 6]))
        }
    }

    /// Comfortable swipe distance to run the cut fully across.
    private let cutSpan: CGFloat = 230

    /// Swipe sideways — anywhere along the perforation *or* across the stub tab
    /// below it — to run the cut: the seam parts as you go, ratcheting one
    /// perforation at a time, and rips once the cut reaches the far edge.
    private func cutGesture() -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard printed, !ripped else { return }
                // Sideways travel parts the paper; ignore a mostly-vertical drag.
                guard abs(value.translation.width) > abs(value.translation.height) * 0.6 else { return }
                let p = max(0, value.translation.width) / cutSpan
                // Monotonic: a wiggle can't un-cut what you've already parted.
                cutProgress = max(cutProgress, min(1, p))
                let step = Int(cutProgress / 0.09)
                if step > lastCutStep {
                    lastCutStep = step
                    CabinAudioEngine.shared.playTearTick()
                    Haptics.ratchet()
                }
                if cutProgress > 0.92 { rip() }
            }
            .onEnded { _ in
                guard !ripped else { return }
                if cutProgress < 0.92 {
                    // Cut wasn't run all the way across — the paper closes back up.
                    withAnimation(.spring(duration: 0.4)) { cutProgress = 0 }
                    lastCutStep = 0
                }
            }
    }

    private func halfNotch(leading: Bool) -> some View {
        Circle()
            .fill(Theme.boardingBackdrop)
            .frame(width: 22, height: 22)
            .offset(x: leading ? -11 : 11)
    }

    // MARK: Stub + tear gesture

    private var stubPiece: some View {
        // As the cut runs across, the stub loosens a touch; the real motion is
        // the fly-off on rip. It never tracks the finger vertically.
        let progress = min(1, max(0, cutProgress))
        let dragY = ripped ? 300 : progress * 5
        let angle = ripped ? 3.0 : Double(progress * 1.4)
        let curl = ripped ? 18.0 : Double(progress * 6)

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
            .gesture(cutGesture())
            // One short slide-and-fade. A long fall leaves the stub hanging
            // half-transparent over the backdrop, which reads as a glitch.
            .animation(ripped ? .easeIn(duration: 0.28) : nil, value: ripped)
            .accessibilityHidden(ripped)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("boarding-pass-stub")
            .accessibilityLabel("Boarding pass stub, seat \(session.seat)")
            .accessibilityHint("Slide across to tear and board")
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

    private func rip() {
        guard !ripped else { return }
        ripped = true
        Haptics.rip()
        CabinAudioEngine.shared.playRip()
        Task { @MainActor in
            // Let the stub clear the screen before departing; also gives the rip
            // one-shot time to finish before depart starts ambience.
            try? await Task.sleep(for: .milliseconds(430))
            onBoarded()
        }
    }
}

// MARK: - Paper shapes

/// Main pass silhouette: rounded top, flat bottom where the stub separates.
private struct PassBodyPaper: Shape {
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 22
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
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
