import SwiftUI

/// The boarding pass prints out of a slot, then a drag-to-tear gesture
/// along the perforation starts the flight. This is the commitment moment.
struct BoardingPassView: View {
    @Bindable var session: FlightSession
    let onBoarded: () -> Void

    @State private var printed = false
    /// Positive = stub pulled down away from the body (vertical tear).
    @State private var tearTranslation: CGFloat = 0
    @State private var ripped = false
    @State private var lastRatchetStep = 0

    private var leg: FlightLeg { session.itinerary.legs[0] }

    private var gate: String {
        var hash: UInt64 = 5381
        for byte in leg.flightNumber.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        return "B\(hash % 22 + 1)"
    }

    /// Distance the stub must travel before the tear commits.
    private let tearThreshold: CGFloat = 72

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.nightSkyTop, Theme.nightSkyBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer(minLength: 12)

                printerSlot

                passCard
                    .padding(.horizontal, 28)
                    // Emerge from the slot: start scrunched up behind it.
                    .offset(y: printed ? 0 : -560)
                    .opacity(printed ? 1 : 0)
                    .animation(.smooth(duration: 1.6), value: printed)

                Spacer()

                if printed && !ripped {
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
                    .accessibilityHint("Tears the boarding pass stub and continues to flight mode")
                }

                Text(ripped ? "Boarding…" : "Pull the stub down to tear & board")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.bottom, 24)
            }
            .clipped()
        }
        .onAppear { startPrinting() }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text("Tear & board")) {
            guard printed, !ripped else { return }
            rip()
        }
    }

    private var printerSlot: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(.black.opacity(0.75))
            .frame(height: 10)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 1)
            )
            .padding(.horizontal, 20)
            .zIndex(2)
    }

    private func startPrinting() {
        guard !printed else { return }
        // Ticking print-head haptics while the pass feeds out.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            printed = true
            for _ in 0..<8 {
                Haptics.softTick()
                try? await Task.sleep(for: .milliseconds(180))
            }
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
    }

    private var passBody: some View {
        VStack(spacing: 18) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "airplane.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("VOYAGE AIR")
                        .font(.system(size: 12, weight: .heavy))
                        .kerning(2)
                }
                Spacer()
                Text(leg.flightNumber)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

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
                        .foregroundStyle(Color.accentColor)
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
                passField("Seat", session.seat)
                passField("Gate", gate)
                passField("Focus", session.itinerary.totalFocusDuration.shortDurationText)
            }

            if !session.intentions.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "suitcase.fill")
                        .font(.system(size: 10))
                    Text("\(session.intentions.count) checked \(session.intentions.count == 1 ? "bag" : "bags")")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                }
                .foregroundStyle(.secondary)
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

    private var perforation: some View {
        HStack(spacing: 0) {
            halfNotch(leading: true)
            Line()
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                .foregroundStyle(Color(.separator))
                .frame(height: 1.5)
            halfNotch(leading: false)
        }
        .frame(height: 22)
        .background(Color(.systemBackground))
    }

    private func halfNotch(leading: Bool) -> some View {
        Circle()
            .fill(Theme.nightSkyBottom)
            .frame(width: 22, height: 22)
            .offset(x: leading ? -11 : 11)
    }

    // MARK: Stub + tear gesture

    private var stubPiece: some View {
        let progress = min(1, max(0, tearTranslation) / tearThreshold)
        let dragY = ripped ? 420 : max(0, tearTranslation)
        let dragX = ripped ? 48 : progress * 10
        let angle = ripped ? 18.0 : Double(progress * 6)

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
            .offset(x: dragX, y: dragY)
            .rotationEffect(.degrees(angle), anchor: .topLeading)
            .opacity(ripped ? 0 : 1)
            .gesture(tearGesture())
            .animation(ripped ? .smooth(duration: 0.55) : nil, value: ripped)
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
                // Vertical tear along the perforation: only count downward pull.
                // A strong horizontal swipe also contributes so either metaphor works.
                let vertical = max(0, value.translation.height)
                let horizontal = abs(value.translation.width) * 0.55
                tearTranslation = max(vertical, horizontal)

                let step = Int(tearTranslation / (tearThreshold * 0.12))
                if step != lastRatchetStep {
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
        Task { @MainActor in
            // Let the stub fly off before advancing; also gives the rip
            // one-shot time to finish before depart starts ambience.
            try? await Task.sleep(for: .milliseconds(750))
            onBoarded()
        }
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

/// Simple horizontal line shape for the perforation.
private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
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
