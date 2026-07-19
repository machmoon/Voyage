import SwiftUI

/// Cabin seat map: 3–3 economy (plus a 2–2 business cabin for Silver+),
/// some seats already taken, window seats gently encouraged.
struct SeatSelectionView: View {
    @Bindable var session: FlightSession
    let onContinue: () -> Void

    @State private var selected: String?

    private var businessRows: Range<Int> { session.isPremiumCabin ? 1..<3 : 1..<1 }
    private let economyRows = 3..<13
    private let letters = ["A", "B", "C", "D", "E", "F"]
    private let businessLetters = ["A", "C", "D", "F"]

    private var accent: Color { session.itinerary.destination.accentColor }

    var body: some View {
        VStack(spacing: 0) {
            header
            legend
            ScrollView {
                ZStack {
                    fuselageShell
                    VStack(spacing: 12) {
                        fuselageNose
                        if session.isPremiumCabin {
                            cabinLabel("BUSINESS")
                            ForEach(Array(businessRows), id: \.self) { row in
                                seatRow(row: row, letters: businessLetters, isBusiness: true)
                            }
                            aisleDivider
                            cabinLabel("ECONOMY")
                        }
                        ForEach(Array(economyRows), id: \.self) { row in
                            seatRow(row: row, letters: letters, isBusiness: false)
                        }
                        fuselageTail
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 22)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }

            continueButton
        }
        .foregroundStyle(.white)
    }

    // MARK: - Header / legend

    private var header: some View {
        VStack(spacing: 6) {
            Text("Choose your seat")
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text("Flight \(session.currentLeg.flightNumber) · \(session.itinerary.origin.code) → \(session.itinerary.destination.code)")
                .font(.subheadline)
                .foregroundStyle(Theme.cabinSecondary)
            Text("Window seats show the view you’ll get in flight.")
                .font(.caption)
                .foregroundStyle(Theme.cabinLabel)
        }
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendChip(color: Theme.seatAvailableTop, label: "Open")
            legendChip(color: Theme.seatTaken, label: "Taken")
            legendChip(color: accent, label: "Yours")
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(accent.opacity(0.35))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(accent.opacity(0.9), lineWidth: 1)
                    )
                    .frame(width: 14, height: 14)
                    .shadow(color: accent.opacity(0.55), radius: 4)
                Text("WINDOW")
                    .font(.system(size: 10, weight: .heavy))
                    .kerning(1.2)
                    .foregroundStyle(accent)
            }
        }
        .padding(.bottom, 10)
    }

    private func legendChip(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color)
                .frame(width: 14, height: 14)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.cabinSecondary)
        }
    }

    // MARK: - Fuselage chrome

    private var fuselageShell: some View {
        RoundedRectangle(cornerRadius: 48, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Theme.cabinFuselage.opacity(0.95),
                        Theme.cabinCanvas,
                        Theme.cabinFuselage.opacity(0.9)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 48, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Theme.cabinMetal.opacity(0.55),
                                Theme.cabinMetal.opacity(0.15),
                                Theme.cabinMetal.opacity(0.4)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            )
            .overlay {
                // Soft aisle strip down the cabin center
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.cabinAisle.opacity(0.55))
                    .frame(width: 10)
                    .padding(.vertical, 56)
            }
            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }

    private var fuselageNose: some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Theme.cabinMetal.opacity(0.7), Theme.cabinMetal.opacity(0.2)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 54, height: 22)
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 28, height: 6)
                        .offset(y: 4)
                }
            Image(systemName: "airplane")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.cabinLabel)
                .rotationEffect(.degrees(-90))
            Text("FORWARD")
                .font(.system(size: 9, weight: .heavy))
                .kerning(2)
                .foregroundStyle(Theme.cabinLabel)
        }
        .padding(.bottom, 4)
        .accessibilityHidden(true)
    }

    private var fuselageTail: some View {
        Capsule()
            .fill(Theme.cabinMetal.opacity(0.25))
            .frame(width: 36, height: 8)
            .padding(.top, 8)
            .accessibilityHidden(true)
    }

    private var aisleDivider: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Theme.cabinMetal.opacity(0.35)).frame(height: 1)
            Text("AISLE")
                .font(.system(size: 9, weight: .heavy))
                .kerning(1.6)
                .foregroundStyle(Theme.cabinLabel)
            Rectangle().fill(Theme.cabinMetal.opacity(0.35)).frame(height: 1)
        }
        .padding(.vertical, 2)
    }

    private func cabinLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy))
            .kerning(2.4)
            .foregroundStyle(text == "BUSINESS" ? accent.opacity(0.85) : Theme.cabinLabel)
            .padding(.vertical, 2)
    }

    // MARK: - Rows / seats

    private func seatRow(row: Int, letters rowLetters: [String], isBusiness: Bool) -> some View {
        let half = rowLetters.count / 2
        return HStack(spacing: isBusiness ? 12 : 8) {
            ForEach(rowLetters.prefix(half), id: \.self) { letter in
                seatButton(row: row, letter: letter, isBusiness: isBusiness)
            }
            Text("\(row)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.cabinLabel)
                .frame(width: 28)
            ForEach(rowLetters.suffix(half), id: \.self) { letter in
                seatButton(row: row, letter: letter, isBusiness: isBusiness)
            }
        }
    }

    private func seatButton(row: Int, letter: String, isBusiness: Bool) -> some View {
        let id = "\(row)\(letter)"
        let taken = isTaken(id)
        let isSelected = selected == id
        let isWindow = letter == "A" || letter == "F"
        let size: CGFloat = isBusiness ? 52 : 46

        return Button {
            guard !taken else { return }
            Haptics.tap()
            withAnimation(.snappy(duration: 0.25)) { selected = id }
        } label: {
            SeatCushion(
                size: size,
                isBusiness: isBusiness,
                taken: taken,
                selected: isSelected,
                isWindow: isWindow,
                accent: accent,
                label: letter
            )
        }
        .buttonStyle(.plain)
        .disabled(taken)
        .accessibilityLabel(taken ? "Seat \(id), taken" : "Seat \(id)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .scaleEffect(isSelected ? 1.06 : 1)
        .animation(.snappy(duration: 0.25), value: isSelected)
    }

    /// Deterministic "already taken" seats, seeded by the flight number,
    /// so the cabin looks the same if you go back a step.
    private func isTaken(_ seatID: String) -> Bool {
        var hash: UInt64 = 1469598103934665603
        for byte in (session.currentLeg.flightNumber + seatID).utf8 {
            hash = (hash ^ UInt64(byte)) &* 1099511628211
        }
        return hash % 100 < 32
    }

    private var continueButton: some View {
        VStack(spacing: 8) {
            if let selected, selected.hasSuffix("A") || selected.hasSuffix("F") {
                Text("Window seat — this is the view you’ll get in flight.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(accent)
                    .multilineTextAlignment(.center)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            Button {
                if let selected {
                    session.seat = selected
                    Haptics.success()
                    onContinue()
                }
            } label: {
                Text(selected.map { "Take seat \($0)" } ?? "Select a seat")
                    .font(.headline)
                    .foregroundStyle(selected == nil ? Theme.cabinLabel : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                selected == nil
                                    ? LinearGradient(
                                        colors: [Theme.cabinAisle, Theme.cabinAisle],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    : LinearGradient(
                                        colors: [accent, accent.opacity(0.75)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                            )
                    }
            }
            .disabled(selected == nil)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
        .animation(.snappy(duration: 0.25), value: selected)
    }
}

// MARK: - Seat cushion glyph

/// Soft layered cushion — not an SF car-seat symbol.
private struct SeatCushion: View {
    let size: CGFloat
    let isBusiness: Bool
    let taken: Bool
    let selected: Bool
    let isWindow: Bool
    let accent: Color
    let label: String

    private var corner: CGFloat { isBusiness ? 14 : 11 }

    var body: some View {
        ZStack {
            // Backrest
            UnevenRoundedRectangle(
                topLeadingRadius: corner,
                bottomLeadingRadius: corner * 0.45,
                bottomTrailingRadius: corner * 0.45,
                topTrailingRadius: corner,
                style: .continuous
            )
            .fill(cushionGradient)
            .overlay(alignment: .top) {
                // Soft highlight along the top edge of the cushion
                Capsule()
                    .fill(Color.white.opacity(taken ? 0.04 : (selected ? 0.22 : 0.12)))
                    .frame(width: size * 0.55, height: 4)
                    .padding(.top, 5)
            }
            .overlay {
                UnevenRoundedRectangle(
                    topLeadingRadius: corner,
                    bottomLeadingRadius: corner * 0.45,
                    bottomTrailingRadius: corner * 0.45,
                    topTrailingRadius: corner,
                    style: .continuous
                )
                .strokeBorder(borderColor, lineWidth: selected || (isWindow && !taken) ? 1.6 : 0.8)
            }

            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: isBusiness ? 15 : 13, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Text(label)
                    .font(.system(size: isBusiness ? 13 : 11, weight: .bold, design: .rounded))
                    .foregroundStyle(labelColor)
            }
        }
        .frame(width: size, height: size)
        .shadow(
            color: selected
                ? accent.opacity(0.55)
                : (isWindow && !taken ? accent.opacity(0.35) : .clear),
            radius: selected ? 8 : 5
        )
        .opacity(taken ? 0.55 : 1)
    }

    private var cushionGradient: LinearGradient {
        if taken {
            return LinearGradient(
                colors: [Theme.seatTakenTop, Theme.seatTaken],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        if selected {
            return LinearGradient(
                colors: [accent, accent.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        if isBusiness {
            return LinearGradient(
                colors: [
                    Theme.seatAvailableTop.opacity(0.95),
                    accent.opacity(0.28),
                    Theme.seatAvailable
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        return LinearGradient(
            colors: [Theme.seatAvailableTop, Theme.seatAvailable],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var borderColor: Color {
        if selected { return accent.opacity(0.95) }
        if taken { return Color.white.opacity(0.06) }
        if isWindow { return accent.opacity(0.75) }
        return Color.white.opacity(0.1)
    }

    private var labelColor: Color {
        if taken { return Color.white.opacity(0.28) }
        if isWindow { return accent.opacity(0.95) }
        return Color.white.opacity(0.85)
    }
}
