import SwiftUI

/// Airline-style seat map: cream page, white fuselage, a 1–1 First Class
/// cabin up front, a 2–2 Main Cabin behind it, exit-row markers over the
/// wing box, and a fare card with cabin class, seat, flight number, and price.
struct SeatSelectionView: View {
    @Bindable var session: FlightSession
    let onContinue: () -> Void

    @State private var selected: String?

    private let firstRows = Array(1...2)
    private let economyRows = Array(3...12)
    private let leftLetters = ["A", "B"]
    private let rightLetters = ["C", "D"]
    /// Visual break (exit row / over-wing box) after this economy row.
    private let wingBreakAfterRow = 6
    private let firstClassRows = 1...2

    var body: some View {
        VStack(spacing: 0) {
            header
            legend
                .padding(.top, 4)
                .padding(.bottom, 10)

            ScrollView(showsIndicators: false) {
                fuselage
                    .frame(maxWidth: 300)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                    .padding(.bottom, 16)
            }

            fareCard
        }
        .background(Theme.seatMapBackground.ignoresSafeArea())
    }

    // MARK: Header / legend

    private var header: some View {
        Text("Select Seats")
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(Theme.seatMapInk)
            .padding(.top, 6)
            .padding(.bottom, 6)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendChip(color: Theme.seatFirstGold, label: "First")
            legendChip(color: Theme.seatOpen, label: "Available")
            legendChip(color: Theme.seatTakenFill, label: "Booked")
            legendChip(color: Theme.seatChosen, label: "Selected")
        }
    }

    private func legendChip(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color)
                .frame(width: 15, height: 15)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.seatMapInk.opacity(0.8))
        }
    }

    // MARK: Aircraft

    private var fuselage: some View {
        VStack(spacing: 0) {
            nose
            firstCabin
            cabinDivider("MAIN CABIN")
                .padding(.top, 18)
                .padding(.bottom, 14)
            economyCabin
        }
        .background(
            NoseCappedColumn()
                .fill(Theme.seatMapFuselage)
                .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
        )
    }

    private var nose: some View {
        VStack(spacing: 8) {
            // Cockpit windscreen.
            Capsule()
                .fill(Theme.seatMapInk.opacity(0.85))
                .frame(width: 58, height: 14)
                .padding(.top, 34)
            cabinDivider("FIRST CLASS")
                .padding(.top, 14)
        }
        .padding(.bottom, 14)
        .accessibilityHidden(true)
    }

    private func cabinDivider(_ label: String) -> some View {
        HStack(spacing: 10) {
            dividerLine
            Text(label)
                .font(.system(size: 10, weight: .heavy))
                .kerning(1.6)
                .foregroundStyle(Theme.seatMapInk.opacity(0.4))
                .fixedSize()
            dividerLine
        }
        .padding(.horizontal, 22)
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(Theme.seatMapInk.opacity(0.1))
            .frame(height: 1)
    }

    // MARK: First Class (1–1 wide recliners)

    private var firstCabin: some View {
        VStack(spacing: 14) {
            ForEach(firstRows, id: \.self) { row in
                HStack(spacing: 0) {
                    windowTick
                    firstSeatButton(row: row, letter: "A")
                        .frame(maxWidth: .infinity)
                    Text("\(row)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.seatMapInk.opacity(0.25))
                        .frame(width: 34)
                    firstSeatButton(row: row, letter: "D")
                        .frame(maxWidth: .infinity)
                    windowTick
                }
                .padding(.horizontal, 18)
            }
        }
    }

    private func firstSeatButton(row: Int, letter: String) -> some View {
        let id = displaySeat(row: row, letter: letter)
        let taken = isTaken(id)
        let isSelected = selected == id

        let shell: Color = isSelected ? Theme.seatChosen
            : (taken ? Theme.seatTakenFill : Theme.seatFirstGold)
        let cushion: Color = isSelected ? Theme.seatChosen.opacity(0.72)
            : (taken ? Theme.seatTakenFill.opacity(0.7) : Theme.seatFirstGoldLight)

        return Button {
            guard !taken else { return }
            Haptics.tap()
            withAnimation(.snappy(duration: 0.25)) { selected = id }
        } label: {
            // A front-view armchair: tall backrest with a headrest notch,
            // wide seat cushion, armrests flanking the sides.
            HStack(alignment: .bottom, spacing: 2) {
                armrest(shell: shell, taken: taken)
                VStack(spacing: 0) {
                    // Backrest with headrest.
                    UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 4,
                                           bottomTrailingRadius: 4, topTrailingRadius: 16,
                                           style: .continuous)
                        .fill(shell)
                        .overlay(alignment: .top) {
                            Capsule()
                                .fill(.white.opacity(taken ? 0.25 : 0.4))
                                .frame(width: 22, height: 4)
                                .padding(.top, 5)
                        }
                        .overlay {
                            if isSelected {
                                Text(id)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                            } else if !taken {
                                Image(systemName: "diamond.fill")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(Theme.seatMapInk.opacity(0.3))
                            }
                        }
                        .frame(width: 46, height: 40)
                    // Seat cushion.
                    UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 8,
                                           bottomTrailingRadius: 8, topTrailingRadius: 3,
                                           style: .continuous)
                        .fill(cushion)
                        .frame(width: 52, height: 12)
                        .padding(.top, 2)
                }
                armrest(shell: shell, taken: taken)
            }
            .frame(width: 78, height: 58, alignment: .bottom)
        }
        .buttonStyle(.plain)
        .disabled(taken)
        .scaleEffect(isSelected ? 1.06 : 1)
        .animation(.snappy(duration: 0.25), value: isSelected)
        .accessibilityLabel(taken ? "First class seat \(id), taken" : "First class seat \(id)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func armrest(shell: Color, taken: Bool) -> some View {
        UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 3,
                               bottomTrailingRadius: 3, topTrailingRadius: 5,
                               style: .continuous)
            .fill(shell.opacity(taken ? 0.8 : 1))
            .overlay(
                UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 3,
                                       bottomTrailingRadius: 3, topTrailingRadius: 5,
                                       style: .continuous)
                    .strokeBorder(Theme.seatMapInk.opacity(0.15), lineWidth: 1)
            )
            .frame(width: 9, height: 30)
    }

    // MARK: Main Cabin (2–2)

    private var economyCabin: some View {
        VStack(spacing: 12) {
            columnHeaders
            ForEach(economyRows, id: \.self) { row in
                seatRow(row)
                if row == wingBreakAfterRow {
                    exitRowBreak
                }
            }
        }
        .padding(.bottom, 34)
    }

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            windowTick.opacity(0)
            seatHeaderGroup(leftLetters)
            Text("")
                .frame(width: 34)
            seatHeaderGroup(rightLetters)
            windowTick.opacity(0)
        }
        .padding(.horizontal, 18)
        .accessibilityHidden(true)
    }

    private func seatHeaderGroup(_ letters: [String]) -> some View {
        HStack(spacing: 10) {
            ForEach(letters, id: \.self) { letter in
                Text(letter)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.seatMapInk.opacity(0.45))
                    .frame(width: 44)
            }
        }
    }

    /// Over-wing exit row: red EXIT markers at both fuselage edges,
    /// the way real airline seat maps mark it.
    private var exitRowBreak: some View {
        HStack {
            exitTag
            Spacer()
            exitTag
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .accessibilityHidden(true)
    }

    private var exitTag: some View {
        Text("EXIT")
            .font(.system(size: 8, weight: .heavy))
            .kerning(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color(hex: "C4453B"), in: RoundedRectangle(cornerRadius: 3))
    }

    private func seatRow(_ row: Int) -> some View {
        HStack(spacing: 0) {
            windowTick
            HStack(spacing: 10) {
                ForEach(leftLetters, id: \.self) { seatButton(row: row, letter: $0) }
            }
            Text("\(row)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.seatMapInk.opacity(0.25))
                .frame(width: 34)
            HStack(spacing: 10) {
                ForEach(rightLetters, id: \.self) { seatButton(row: row, letter: $0) }
            }
            windowTick
        }
        .padding(.horizontal, 18)
    }

    /// Small gray pill on the fuselage edge — a cabin window.
    private var windowTick: some View {
        Capsule()
            .fill(Theme.seatMapInk.opacity(0.18))
            .frame(width: 5, height: 16)
            .accessibilityHidden(true)
    }

    private func seatButton(row: Int, letter: String) -> some View {
        let id = displaySeat(row: row, letter: letter)
        let taken = isTaken(id)
        let isSelected = selected == id

        return Button {
            guard !taken else { return }
            Haptics.tap()
            withAnimation(.snappy(duration: 0.25)) { selected = id }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(seatColor(taken: taken, selected: isSelected))
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        taken ? Theme.seatMapInk.opacity(0.05) : Theme.accent.opacity(isSelected ? 0 : 0.35),
                        lineWidth: 1
                    )
                if isSelected {
                    Text(id)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(taken)
        .scaleEffect(isSelected ? 1.08 : 1)
        .animation(.snappy(duration: 0.25), value: isSelected)
        .accessibilityLabel(taken ? "Seat \(id), taken" : "Seat \(id)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func seatColor(taken: Bool, selected: Bool) -> Color {
        if selected { return Theme.seatChosen }
        if taken { return Theme.seatTakenFill }
        return Theme.seatOpen
    }

    // MARK: Seat identity / pricing

    /// Reference design labels seats letter-first ("C10").
    private func displaySeat(row: Int, letter: String) -> String { "\(letter)\(row)" }

    /// Deterministic "already booked" seats, seeded by the flight number,
    /// so the cabin looks the same if you go back a step.
    private func isTaken(_ seatID: String) -> Bool {
        var hash: UInt64 = 1469598103934665603
        for byte in (session.currentLeg.flightNumber + seatID).utf8 {
            hash = (hash ^ UInt64(byte)) &* 1099511628211
        }
        return hash % 100 < 32
    }

    private var selectedRow: Int? {
        selected.flatMap { Int($0.filter(\.isNumber)) }
    }

    private var cabinClass: String {
        guard let row = selectedRow else { return "—" }
        return firstClassRows.contains(row) ? "First" : "Main Cabin"
    }

    private var price: Int {
        guard let row = selectedRow else { return 0 }
        let base = 59.0 + session.itinerary.totalMiles * 0.085
        let multiplier = firstClassRows.contains(row) ? 3.0 : 1.0
        return Int(((base * multiplier) / 5).rounded()) * 5
    }

    // MARK: Fare card

    private var fareCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top) {
                fareField("Cabin Class", cabinClass)
                Spacer()
                fareField("Selected Seat", selected ?? "—", centered: true)
                Spacer()
                fareField("Flight No", session.currentLeg.flightNumber, trailing: true)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Total Price")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.seatMapInk.opacity(0.5))
                    Text(selected == nil ? "$—" : "$\(price)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Theme.seatMapInk)
                        .contentTransition(.numericText())
                }
                Spacer()
                Button {
                    if let selected {
                        session.seat = selected
                        Haptics.success()
                        onContinue()
                    }
                } label: {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(selected == nil ? Theme.seatMapInk.opacity(0.5) : .white)
                        .frame(width: 58, height: 58)
                        .background(
                            selected == nil
                                ? Theme.seatTakenFill.opacity(0.6)
                                : Theme.accent,
                            in: Circle()
                        )
                }
                .disabled(selected == nil)
                .accessibilityLabel(selected.map { "Take seat \($0)" } ?? "Select a seat")
            }
        }
        .padding(20)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 28, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 0, topTrailingRadius: 28,
                                   style: .continuous)
                .fill(Theme.seatMapFuselage)
                .shadow(color: .black.opacity(0.10), radius: 16, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
        .animation(.snappy(duration: 0.25), value: selected)
    }

    private func fareField(_ label: String, _ value: String,
                           centered: Bool = false, trailing: Bool = false) -> some View {
        let alignment: HorizontalAlignment = trailing ? .trailing : (centered ? .center : .leading)
        return VStack(alignment: alignment, spacing: 3) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.seatMapInk.opacity(0.5))
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.seatMapInk)
                .contentTransition(.numericText())
        }
    }
}

// MARK: - Airframe shape

/// White fuselage column with a rounded nose and slight tail taper.
private struct NoseCappedColumn: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let noseHeight = min(rect.height * 0.16, 90)
        let tailInset = rect.width * 0.12

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + noseHeight))
        // Nose dome.
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + noseHeight),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        // Body sides with gentle tail taper.
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY * 0.82))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - tailInset, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.maxY * 0.95))
        path.addLine(to: CGPoint(x: rect.minX + tailInset, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY * 0.82),
                          control: CGPoint(x: rect.minX, y: rect.maxY * 0.95))
        path.closeSubpath()
        return path
    }
}
