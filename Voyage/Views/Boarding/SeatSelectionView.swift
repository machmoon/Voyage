import SwiftUI

/// Airline-style seat map drawn the way carriers actually draw them: a thin
/// outlined fuselage, cabin sections banded and lettered, unavailable seats
/// struck through with an X rather than boxed, the row number set in the
/// aisle, exit doors marked at the fuselage edge, and a galley/lavatory
/// block at the tail. Tapping a seat raises the detail callout the same way
/// a booking flow does, and the fare card carries the CTA.
struct SeatSelectionView: View {
    @Bindable var session: FlightSession
    let onContinue: () -> Void

    @State private var selected: String?

    private let firstRows = Array(1...2)
    private let economyRows = Array(3...12)
    private let leftLetters = ["A", "B"]
    private let rightLetters = ["C", "D"]
    /// Over-wing exit row sits after this economy row.
    private let wingBreakAfterRow = 6
    private let firstClassRows = 1...2

    /// One seat cell. Everything on the map lines up to this grid.
    private let cell: CGFloat = 44
    private let cellGap: CGFloat = 8
    private let aisleWidth: CGFloat = 34
    /// First class is 1–1: each recliner spans the width of two economy seats
    /// so the cabin reads as premium at a glance.
    private var firstCell: CGFloat { cell * 2 + cellGap }

    var body: some View {
        VStack(spacing: 0) {
            header
            legend
                .padding(.top, 2)
                .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                fuselage
                    .frame(maxWidth: 268)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 18)
            }

            VStack(spacing: 0) {
                if let selected {
                    seatCallout(for: selected)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                fareCard
            }
            .animation(.snappy(duration: 0.28), value: selected)
        }
        .background(Theme.seatMapBackground.ignoresSafeArea())
    }

    // MARK: Header / legend

    private var header: some View {
        Text("Select Seats")
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(Theme.seatMapInk)
            .padding(.top, 6)
            .padding(.bottom, 8)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendChip(swatch: AnyView(seatSwatch(Theme.seatFirstGold)), label: "First")
            legendChip(swatch: AnyView(seatSwatch(Theme.seatOpen)), label: "Available")
            legendChip(swatch: AnyView(takenGlyph(size: 13)), label: "Taken")
            legendChip(swatch: AnyView(seatSwatch(Theme.seatChosen)), label: "Selected")
        }
    }

    private func legendChip(swatch: AnyView, label: String) -> some View {
        HStack(spacing: 5) {
            swatch.frame(width: 15, height: 15)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.seatMapInk.opacity(0.8))
        }
    }

    private func seatSwatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(color)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Theme.seatMapInk.opacity(0.18), lineWidth: 1)
            )
    }

    // MARK: Aircraft

    private var fuselage: some View {
        VStack(spacing: 0) {
            nose

            cabinBand("FIRST CLASS")
            columnHeaders(left: ["A"], right: ["D"], width: firstCell)
            firstCabin

            cabinBand("MAIN CABIN")
                .padding(.top, 10)
            columnHeaders(left: leftLetters, right: rightLetters, width: cell)
            economyCabin

            tailBlock
        }
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Theme.seatMapFuselage)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Theme.seatMapInk.opacity(0.16), lineWidth: 1)
        )
    }

    private var nose: some View {
        Capsule()
            .fill(Theme.seatMapInk.opacity(0.8))
            .frame(width: 54, height: 12)
            .padding(.top, 26)
            .padding(.bottom, 18)
            .accessibilityHidden(true)
    }

    /// Grey band naming the cabin, the way a seat map separates sections.
    private func cabinBand(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .heavy))
            .kerning(1.4)
            .foregroundStyle(Theme.seatMapInk.opacity(0.55))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Theme.seatMapInk.opacity(0.05))
            .accessibilityAddTraits(.isHeader)
    }

    /// Column letters above each cabin, aligned to the seat grid.
    private func columnHeaders(left: [String], right: [String], width: CGFloat) -> some View {
        func header(_ letter: String) -> AnyView {
            AnyView(Text(letter)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.seatMapInk.opacity(0.45))
                .frame(width: width))
        }
        return gridRow(
            left: left.map(header),
            right: right.map(header),
            aisle: AnyView(Color.clear)
        )
        .frame(height: 22)
        .padding(.top, 8)
        .accessibilityHidden(true)
    }

    /// The shared row geometry: seats, an aisle gutter, seats — with the
    /// row number set in the gutter, as on a printed seat map.
    private func gridRow(left: [AnyView], right: [AnyView], aisle: AnyView) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: cellGap) {
                ForEach(Array(left.enumerated()), id: \.offset) { _, view in
                    view
                }
            }
            aisle.frame(width: aisleWidth)
            HStack(spacing: cellGap) {
                ForEach(Array(right.enumerated()), id: \.offset) { _, view in
                    view
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func rowNumber(_ row: Int) -> AnyView {
        AnyView(
            Text("\(row)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.seatMapInk.opacity(0.45))
                .accessibilityHidden(true)
        )
    }

    // MARK: First Class

    private var firstCabin: some View {
        VStack(spacing: cellGap) {
            ForEach(firstRows, id: \.self) { row in
                gridRow(
                    left: [AnyView(seatCell(row: row, letter: "A", isFirst: true))],
                    right: [AnyView(seatCell(row: row, letter: "D", isFirst: true))],
                    aisle: rowNumber(row)
                )
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    // MARK: Main Cabin

    private var economyCabin: some View {
        VStack(spacing: cellGap) {
            ForEach(economyRows, id: \.self) { row in
                gridRow(
                    left: leftLetters.map { AnyView(seatCell(row: row, letter: $0, isFirst: false)) },
                    right: rightLetters.map { AnyView(seatCell(row: row, letter: $0, isFirst: false)) },
                    aisle: rowNumber(row)
                )
                if row == wingBreakAfterRow {
                    exitRow
                }
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    /// Exit doors are drawn as red bars set into the fuselage wall.
    private var exitRow: some View {
        HStack {
            exitDoor
            Text("EXIT ROW")
                .font(.system(size: 9, weight: .heavy))
                .kerning(1.2)
                .foregroundStyle(Theme.seatMapInk.opacity(0.35))
            exitDoor
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
        .accessibilityHidden(true)
    }

    private var exitDoor: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(Color(hex: "C4453B"))
            .frame(width: 5, height: 22)
    }

    /// Galley and lavatory block at the tail, as on a real map.
    private var tailBlock: some View {
        HStack(spacing: 6) {
            serviceBox(systemName: "cup.and.saucer.fill")
            serviceBox(systemName: "figure.roll")
            serviceBox(systemName: "figure.stand")
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 22)
        .accessibilityHidden(true)
    }

    private func serviceBox(systemName: String) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Theme.seatMapInk.opacity(0.06))
            .frame(height: 30)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.seatMapInk.opacity(0.4))
            )
    }

    // MARK: Seat cell

    /// A taken seat is an X on the page, not a filled box — the single
    /// clearest signal on any real seat map.
    private func takenGlyph(size: CGFloat) -> some View {
        Image(systemName: "xmark")
            .font(.system(size: size, weight: .light))
            .foregroundStyle(Theme.seatMapInk.opacity(0.22))
    }

    @ViewBuilder
    private func seatCell(row: Int, letter: String, isFirst: Bool) -> some View {
        let width = isFirst ? firstCell : cell
        let id = displaySeat(row: row, letter: letter)
        let taken = isTaken(id)
        let isSelected = selected == id
        let label = isFirst ? "First class seat \(id)" : "Seat \(id)"

        if taken {
            takenGlyph(size: 17)
                .frame(width: width, height: cell)
                .accessibilityLabel("\(label), taken")
        } else {
            Button {
                Haptics.tap()
                withAnimation(.snappy(duration: 0.25)) { selected = id }
            } label: {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Theme.seatChosen
                          : (isFirst ? Theme.seatFirstGold : Theme.seatOpen))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(
                                isSelected ? Theme.seatChosen
                                    : (isFirst ? Theme.seatFirstGold.opacity(0.85)
                                       : Theme.accent.opacity(0.5)),
                                lineWidth: isSelected ? 0 : 1.5
                            )
                    )
                    .overlay {
                        if isSelected {
                            Text(id)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    .overlay {
                        // Selection ring sits outside the seat so the fill
                        // stays readable at this size.
                        if isSelected {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Theme.seatChosen.opacity(0.35), lineWidth: 2)
                                .padding(-4)
                        }
                    }
                    .frame(width: width, height: cell)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    // MARK: Selection callout

    /// The detail card a seat map raises when you pick a seat: which seat,
    /// which cabin, what it costs, and what you get for it.
    private func seatCallout(for id: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(id)
                .font(.system(size: 15, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Theme.seatChosen, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(cabinClass)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.seatMapInk)
                Text("$\(price) · \(session.currentLeg.flightNumber)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.seatMapInk.opacity(0.6))
                Text(seatPerk(for: id))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.seatMapInk.opacity(0.5))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.seatMapFuselage)
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        )
    }

    /// What the seat actually buys you, in the app's own terms.
    private func seatPerk(for id: String) -> String {
        guard let row = Int(id.filter(\.isNumber)) else { return "Standard seat" }
        if firstClassRows.contains(row) { return "Lie-flat · first to board" }
        if row == wingBreakAfterRow || row == wingBreakAfterRow + 1 { return "Extra legroom · exit row" }
        if (5...8).contains(row) { return "Over the wing · wing in view" }
        return "Standard seat"
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
