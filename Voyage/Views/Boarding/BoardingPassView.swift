import SwiftUI

/// The boarding pass prints out of a slot, then a drag-to-tear gesture
/// along the perforation starts the flight. This is the commitment moment.
struct BoardingPassView: View {
    @Bindable var session: FlightSession
    let onBoarded: () -> Void

    @State private var printed = false
    @State private var tearTranslation: CGFloat = 0
    @State private var ripped = false
    @State private var lastRatchetStep = 0

    private var leg: FlightLeg { session.itinerary.legs[0] }

    private var gate: String {
        var hash: UInt64 = 5381
        for byte in leg.flightNumber.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        return "B\(hash % 22 + 1)"
    }

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

                Text(ripped ? "Boarding…" : "Pull the stub sideways to tear & board")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.bottom, 24)
            }
            .clipped()
        }
        .onAppear { startPrinting() }
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
        for i in 0..<8 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 + Double(i) * 0.18) {
                Haptics.softTick()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            printed = true
        }
    }

    // MARK: Pass card

    private var passCard: some View {
        VStack(spacing: 0) {
            passBody
            perforation
            stub
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.45), radius: 22, y: 12)
        )
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
    }

    private func halfNotch(leading: Bool) -> some View {
        Circle()
            .fill(Theme.nightSkyBottom)
            .frame(width: 22, height: 22)
            .offset(x: leading ? -11 : 11)
    }

    // MARK: Stub + tear gesture

    private var stub: some View {
        let width = UIScreen.main.bounds.width - 56
        let progress = min(1, abs(tearTranslation) / (width * 0.55))

        return HStack {
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
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
        .padding(.bottom, 20)
        .contentShape(Rectangle())
        .offset(x: ripped ? width * 1.4 : tearTranslation)
        .rotationEffect(.degrees(ripped ? 14 : Double(progress * 5)), anchor: .bottomLeading)
        .opacity(ripped ? 0 : 1)
        .gesture(tearGesture(width: width))
        .animation(ripped ? .smooth(duration: 0.55) : nil, value: ripped)
    }

    private func tearGesture(width: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard printed, !ripped else { return }
                tearTranslation = value.translation.width
                // Ratchet haptic every ~7% of tear progress.
                let step = Int(abs(tearTranslation) / (width * 0.07))
                if step != lastRatchetStep {
                    lastRatchetStep = step
                    Haptics.ratchet()
                }
                if abs(tearTranslation) > width * 0.55 {
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            onBoarded()
        }
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
