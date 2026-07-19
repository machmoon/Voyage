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

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("Choose your seat")
                    .font(.title2.bold())
                Text("Flight \(session.currentLeg.flightNumber) · \(session.itinerary.origin.code) → \(session.itinerary.destination.code)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Window seats get the best view of the flight.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 18)
            .padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 10) {
                    fuselageNose

                    if session.isPremiumCabin {
                        cabinLabel("BUSINESS")
                        ForEach(Array(businessRows), id: \.self) { row in
                            seatRow(row: row, letters: businessLetters, isBusiness: true)
                        }
                        cabinLabel("ECONOMY")
                    }

                    ForEach(Array(economyRows), id: \.self) { row in
                        seatRow(row: row, letters: letters, isBusiness: false)
                    }
                }
                .padding(.horizontal, 36)
                .padding(.bottom, 24)
            }

            continueButton
        }
    }

    private var fuselageNose: some View {
        Image(systemName: "airplane")
            .font(.system(size: 22))
            .foregroundStyle(.tertiary)
            .rotationEffect(.degrees(-90))
            .padding(.bottom, 4)
    }

    private func cabinLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy))
            .kerning(2)
            .foregroundStyle(.tertiary)
            .padding(.vertical, 2)
    }

    private func seatRow(row: Int, letters rowLetters: [String], isBusiness: Bool) -> some View {
        let half = rowLetters.count / 2
        return HStack(spacing: isBusiness ? 14 : 8) {
            ForEach(rowLetters.prefix(half), id: \.self) { letter in
                seatButton(row: row, letter: letter, isBusiness: isBusiness)
            }
            Text("\(row)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 26)
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
        let size: CGFloat = isBusiness ? 46 : 38

        return Button {
            guard !taken else { return }
            Haptics.tap()
            withAnimation(.snappy(duration: 0.25)) { selected = id }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: isSelected ? "checkmark" : "carseat.left.fill")
                    .font(.system(size: isBusiness ? 15 : 12, weight: .bold))
                if isWindow && !taken && !isSelected {
                    Circle().fill(.cyan).frame(width: 3, height: 3)
                }
            }
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: isBusiness ? 12 : 9, style: .continuous)
                    .fill(seatFill(taken: taken, selected: isSelected))
            )
            .overlay(
                RoundedRectangle(cornerRadius: isBusiness ? 12 : 9, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
            .foregroundStyle(taken ? Color(.tertiaryLabel) : (isSelected ? .white : .accentColor))
        }
        .buttonStyle(.plain)
        .disabled(taken)
        .scaleEffect(isSelected ? 1.08 : 1)
        .animation(.snappy(duration: 0.25), value: isSelected)
    }

    private func seatFill(taken: Bool, selected: Bool) -> Color {
        if taken { return Color(.systemFill) }
        if selected { return .accentColor }
        return Color.accentColor.opacity(0.12)
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
        Button {
            if let selected {
                session.seat = selected
                Haptics.success()
                onContinue()
            }
        } label: {
            Text(selected.map { "Take seat \($0)" } ?? "Select a seat")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    selected == nil ? Color(.systemFill) : Color.accentColor,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
        }
        .disabled(selected == nil)
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }
}
