import SwiftUI

/// Gate kiosk prints the boarding pass, then you tear the stub to board.
/// Printing and tearing are two distinct beats — print completes before
/// the perforation invites a horizontal rip.
struct BoardingPassView: View {
    @Bindable var session: FlightSession
    let onRipStarted: () -> Void
    let onBoarded: () -> Void

    private enum Phase {
        case printing, ready, torn
    }

    @State private var phase: Phase = .printing
    @State private var printProgress: CGFloat = 0
    @State private var visibleLines = 0
    @State private var tearProgress: CGFloat = 0
    @State private var lastRatchetStep = 0
    @State private var perforationPulse = false
    @State private var seamFlash = false
    @State private var paperBurst = false
    @State private var passRetired = false
    @State private var departureWashVisible = false
    @State private var confirmationVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var leg: FlightLeg { session.itinerary.legs[0] }

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

    private let tearThreshold: CGFloat = 108

    private var normalizedTearProgress: CGFloat {
        min(1, max(0, tearProgress / tearThreshold))
    }

    var body: some View {
        ZStack {
            Theme.boardingBackdrop.ignoresSafeArea()
            departureWash

            VStack(spacing: 0) {
                Spacer(minLength: 8)

                printerKiosk
                    .padding(.horizontal, 28)
                    .padding(.bottom, 6)

                Group {
                    if phase == .printing {
                        passCard
                            .padding(.horizontal, 28)
                            .offset(y: -560 * (1 - printProgress))
                            .clipped()
                    } else {
                        passCard
                            .padding(.horizontal, 28)
                    }
                }
                .scaleEffect(passRetired ? 0.94 : 1, anchor: .top)
                .offset(y: passRetired ? -44 : 0)
                .opacity(passRetired ? 0 : 1)
                .blur(radius: passRetired && !reduceMotion ? 2 : 0)
                .animation(.easeIn(duration: reduceMotion ? 0.12 : 0.32), value: passRetired)

                Spacer()

                if phase == .ready {
                    tearHint
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    footerCaptionView
                        .padding(.bottom, 24)
                }
            }
            .opacity(confirmationVisible ? 0 : 1)

            if confirmationVisible {
                departureConfirmation
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .onAppear { startPrinting() }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text("Tear & board")) {
            guard phase == .ready else { return }
            rip()
        }
    }

    // MARK: Printer kiosk

    private var printerKiosk: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Circle()
                    .fill(printerLED)
                    .frame(width: 8, height: 8)
                Text(printerStatus)
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .kerning(1.2)
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Image(systemName: "printer.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.surfaceElevated, in: UnevenRoundedRectangle(
                topLeadingRadius: 14, bottomLeadingRadius: 0,
                bottomTrailingRadius: 0, topTrailingRadius: 14, style: .continuous))

            // Paper slot
            ZStack {
                Capsule()
                    .fill(.black.opacity(0.7))
                    .frame(height: 6)
                Capsule()
                    .fill(Theme.accent.opacity(phase == .printing ? 0.9 : 0))
                    .frame(width: phase == .printing ? 52 : 0, height: 3)
                    .animation(.smooth(duration: 0.35), value: phase)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .background(Theme.surfaceDark)
        }
        .accessibilityHidden(true)
    }

    private var printerLED: Color {
        switch phase {
        case .printing: return Theme.statusAmber
        case .ready: return Theme.accent
        case .torn: return Theme.accent
        }
    }

    private var printerStatus: String {
        switch phase {
        case .printing: return "PRINTING"
        case .ready: return "READY — TEAR STUB"
        case .torn: return "CLEARED TO BOARD"
        }
    }

    private var footerCaption: String {
        switch phase {
        case .printing: return "Printing your boarding pass…"
        case .ready: return "Tear the ticket to start your focus session"
        case .torn: return "Boarding…"
        }
    }

    private var tearHint: some View {
        Button(action: rip) {
            HStack(spacing: 10) {
                Image(systemName: "hand.draw.fill")
                    .font(.footnote)
                Text("Slide to start focus")
                    .font(.footnote.weight(.semibold))
                Image(systemName: "chevron.right.2")
                    .font(.caption2.weight(.heavy))
            }
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Theme.accent.opacity(0.18), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Theme.accent.opacity(0.3), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .opacity(1 - normalizedTearProgress * 0.55)
        .scaleEffect(1 - normalizedTearProgress * 0.025)
        .accessibilityHint("You can also swipe the lower ticket stub to the right")
    }

    static let feedSchedule: [Double] = [0.22, 0.14, 0.14, 0.28, 0.15, 0.15, 0.30, 0.16, 0.20]

    private func startPrinting() {
        guard phase == .printing else { return }
        CabinAudioEngine.shared.playPrinter(feedSchedule: Self.feedSchedule)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            let schedule = Self.feedSchedule
            for (line, gap) in schedule.enumerated() {
                visibleLines = line + 1
                withAnimation(.spring(duration: 0.14, bounce: 0.15)) {
                    printProgress = CGFloat(line + 1) / CGFloat(schedule.count)
                }
                Haptics.softTick()
                try? await Task.sleep(for: .milliseconds(Int(gap * 1000)))
            }
            Haptics.success()
            withAnimation(.smooth(duration: 0.45)) {
                phase = .ready
            }
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                perforationPulse = true
            }
        }
    }

    // MARK: Pass card

    private var passCard: some View {
        VStack(spacing: 0) {
            bodyPiece
                .overlay(alignment: .bottom) {
                    seamEffects
                        .offset(y: 15)
                }
            stubPiece
        }
        .environment(\.colorScheme, .light)
    }

    private var bodyPiece: some View {
        VStack(spacing: 0) {
            passBody
            if phase != .torn {
                perforation
            } else {
                Color.clear.frame(height: 8)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(PassBodyPaper(torn: phase == .torn))
        .compositingGroup()
        .shadow(color: .black.opacity(phase == .torn ? 0.35 : 0.45), radius: phase == .torn ? 16 : 22, y: 12)
        .offset(y: phase == .torn ? -6 : 0)
        .animation(.easeOut(duration: 0.35), value: phase == .torn)
    }

    private var passBody: some View {
        VStack(spacing: 18) {
            if visibleLines >= 1 {
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
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if visibleLines >= 2 {
                Divider()
            }

            if visibleLines >= 3 {
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
                .transition(.opacity)
            }

            if visibleLines >= 4 {
                HStack(spacing: 0) {
                    passField("Passenger", "FOCUSED FLYER")
                    passField("Class", cabinClass)
                    passField("Gate", gate)
                }
            }

            if visibleLines >= 5 {
                HStack(spacing: 0) {
                    passField("Board", "NOW")
                    passField("Focus", session.itinerary.totalFocusDuration.shortDurationText)
                    passField("Bags", session.intentions.isEmpty ? "—" : "\(session.intentions.count)")
                }
            }
        }
        .padding(22)
        .padding(.bottom, phase == .torn ? 4 : 0)
        .animation(.snappy(duration: 0.25), value: visibleLines)
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

    private var perforation: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                TearLine()
                    .stroke(
                        phase == .ready
                            ? Theme.accent.opacity(perforationPulse ? 0.95 : 0.28)
                            : Theme.boardingBackdrop.opacity(0.58),
                        style: StrokeStyle(
                            lineWidth: 1.6,
                            lineCap: .round,
                            dash: [7, 7]
                        )
                    )
                    .shadow(
                        color: Theme.accent.opacity(phase == .ready && perforationPulse ? 0.7 : 0),
                        radius: phase == .ready && perforationPulse ? 4 : 0
                    )

                if normalizedTearProgress > 0 {
                    TearLine()
                        .stroke(
                            Theme.accent,
                            style: StrokeStyle(
                                lineWidth: 1.8,
                                lineCap: .round,
                                dash: [7, 7]
                            )
                        )
                        .frame(width: geo.size.width * normalizedTearProgress, alignment: .leading)
                        .clipped()
                }
            }
        }
        .frame(height: 18)
        .padding(.horizontal, 22)
        .background(Color(.systemBackground))
        .accessibilityHidden(true)
    }

    // MARK: Stub + horizontal tear

    private var stubPiece: some View {
        let progress = normalizedTearProgress
        let dragX = max(0, tearProgress)
        let angle = phase == .torn ? 8.0 : Double(progress * 4)
        let curl = phase == .torn ? 38.0 : Double(progress * 18)
        let exitProgress = min(1, max(0, (tearProgress - tearThreshold) / 260))

        return stubContent
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 20)
            .background(Color(.systemBackground))
            .clipShape(StubPaper(torn: tearProgress > 2 || phase == .torn))
            .compositingGroup()
            .shadow(
                color: .black.opacity(progress > 0 || phase == .torn ? 0.28 + 0.22 * progress : 0.08),
                radius: progress > 0 || phase == .torn ? 10 + 8 * progress : 2,
                y: progress > 0 || phase == .torn ? 6 + 6 * progress : 1
            )
            .contentShape(Rectangle())
            .rotation3DEffect(.degrees(curl), axis: (x: 0, y: 1, z: 0),
                              anchor: .leading, perspective: 0.55)
            .offset(x: dragX)
            .rotationEffect(.degrees(angle - progress * 2), anchor: .leading)
            .scaleEffect(x: 1 - progress * 0.018, y: 1, anchor: .leading)
            .opacity((visibleLines >= 6 ? 1 : 0.3) * (1 - exitProgress))
            .blur(radius: exitProgress * 1.5)
            .gesture(tearGesture())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Boarding pass stub")
            .accessibilityHint("Swipe right to tear and board")
            .accessibilityIdentifier("boarding-pass-stub")
            .accessibilityHidden(phase == .torn)
    }

    private var stubContent: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                FieldLabel("Seat")
                Text(session.seat)
                    .font(.system(size: 22, weight: .heavy, design: .monospaced))
            }
            Spacer()
            if visibleLines >= 7 {
                BarcodeView(seed: leg.flightNumber + session.seat)
                    .frame(width: 150, height: 44)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }

    private func tearGesture() -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard phase == .ready else { return }
                guard abs(value.translation.width) > abs(value.translation.height) * 0.55 else { return }
                tearProgress = max(0, value.translation.width)

                let step = Int(tearProgress / (tearThreshold * 0.10))
                if step != lastRatchetStep {
                    if step > lastRatchetStep {
                        CabinAudioEngine.shared.playTearTick()
                    }
                    lastRatchetStep = step
                    Haptics.ratchet()
                }
                if tearProgress > tearThreshold {
                    rip()
                }
            }
            .onEnded { value in
                guard phase == .ready else { return }
                if value.predictedEndTranslation.width > tearThreshold * 0.9 {
                    rip()
                    return
                }
                withAnimation(.spring(duration: 0.4)) {
                    tearProgress = 0
                }
                lastRatchetStep = 0
            }
    }

    private func rip() {
        guard phase == .ready else { return }
        onRipStarted()
        withAnimation(.spring(duration: reduceMotion ? 0.16 : 0.46, bounce: reduceMotion ? 0 : 0.12)) {
            phase = .torn
            perforationPulse = false
            tearProgress = reduceMotion ? tearThreshold * 2 : 520
            seamFlash = true
        }
        Haptics.rip()
        CabinAudioEngine.shared.playRip()
        Task { @MainActor in
            await Task.yield()
            withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.62)) {
                paperBurst = true
            }
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 60 : 150))
            withAnimation(.easeOut(duration: reduceMotion ? 0.1 : 0.28)) {
                seamFlash = false
            }
            withAnimation(.smooth(duration: reduceMotion ? 0.12 : 0.34)) {
                passRetired = true
                departureWashVisible = true
                confirmationVisible = true
            }
            Haptics.success()
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 180 : 560))
            onBoarded()
        }
    }

    private var seamEffects: some View {
        ZStack {
            Capsule()
                .fill(Theme.accent)
                .frame(width: seamFlash ? 300 : 12, height: 2)
                .blur(radius: seamFlash ? 5 : 0)
                .opacity(seamFlash ? 0.9 : 0)

            paperFibers
        }
        .frame(height: 32)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var paperFibers: some View {
        GeometryReader { geo in
            ForEach(0..<11, id: \.self) { index in
                let lane = CGFloat(index) / 10
                let drift = CGFloat(16 + (index % 4) * 11)
                let fall = CGFloat(18 + (index % 5) * 9)
                Capsule()
                    .fill(.white.opacity(0.86))
                    .frame(width: CGFloat(4 + index % 3 * 2), height: 2)
                    .position(x: geo.size.width * (0.06 + lane * 0.88), y: 10)
                    .offset(x: paperBurst ? drift : 0, y: paperBurst ? fall : 0)
                    .rotationEffect(.degrees(paperBurst ? Double(70 + index * 31) : 0))
                    .opacity(paperBurst ? 0 : (phase == .torn ? 0.9 : 0))
            }
        }
    }

    private var departureWash: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "0D1531"), Color(hex: "050713")],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [Theme.accent.opacity(0.32), Theme.accent.opacity(0.06), .clear],
                center: .center,
                startRadius: 12,
                endRadius: 330
            )
            .scaleEffect(departureWashVisible ? 1.25 : 0.2)
        }
        .opacity(departureWashVisible ? 1 : 0)
        .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.42), value: departureWashVisible)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var departureConfirmation: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.14))
                    .frame(width: 82, height: 82)
                Circle()
                    .strokeBorder(Theme.accent.opacity(0.3), lineWidth: 1)
                    .frame(width: 66, height: 66)
                Image(systemName: "airplane.departure")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 8) {
                Text("CLEARED FOR DEPARTURE")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .kerning(1.7)
                    .foregroundStyle(Theme.accent.opacity(0.95))

                HStack(spacing: 14) {
                    Text(leg.origin.code)
                    routeTrack
                    Text(leg.destination.code)
                }
                .font(.system(size: 28, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white)

                Text("\(leg.duration.shortDurationText) focus flight")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.52))
            }
        }
        .padding(.horizontal, 28)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Cleared for departure from \(leg.origin.code) to \(leg.destination.code)"
        )
    }

    private var routeTrack: some View {
        ZStack {
            Capsule()
                .fill(.white.opacity(0.2))
                .frame(width: 74, height: 2)
            Circle()
                .fill(.white.opacity(0.9))
                .frame(width: 5, height: 5)
                .offset(x: -35)
            Image(systemName: "airplane")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 76)
    }

    @ViewBuilder
    private var footerCaptionView: some View {
        Text(footerCaption)
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white.opacity(phase == .printing ? 0.45 : 0.65))
            .animation(.smooth(duration: 0.4), value: phase)
    }
}

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
            let teeth = 9
            let step = rect.width / CGFloat(teeth)
            for i in 0..<teeth {
                let x = rect.maxX - CGFloat(i + 1) * step
                let dip: CGFloat = (i % 2 == 0) ? 4 : 1
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

private struct StubPaper: Shape {
    var torn: Bool

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 22
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        if torn {
            let teeth = 9
            let step = rect.width / CGFloat(teeth)
            for i in 0..<teeth {
                let x = rect.minX + CGFloat(i) * step
                let dip: CGFloat = (i % 2 == 0) ? 4 : 1
                path.addLine(to: CGPoint(x: x + step * 0.5, y: rect.minY + dip))
                path.addLine(to: CGPoint(x: x + step, y: rect.minY + (i % 2 == 0 ? 1 : 6)))
            }
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                          control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

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

/// A single centered perforation path. Dash spacing is handled by the stroke,
/// so the tear guide stays even at every ticket width.
private struct TearLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

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
