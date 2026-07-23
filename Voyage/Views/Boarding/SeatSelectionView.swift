import SwiftUI

/// Airline-style seat map, drawn from the aircraft's real cabin plan: a 2-2
/// First cabin, extra-legroom and main 3-3 cabins on the narrowbodies, and
/// exit-row markers over the wing box. Uses main's rounded fuselage silhouette
/// with branch cabin geometry and seat selection.
struct SeatSelectionView: View {
    @Bindable var session: FlightSession
    let onContinue: () -> Void

    @State private var selected: String?

    private var plan: CabinPlan { session.aircraft.cabinPlan }

    // MARK: Metrics
    //
    // Every cabin shares one column grid so rows line up down the aircraft even
    // where the seat count changes. The widest cabin sets the seat size.

    // Scaled off a real 737-800 cabin so the map reads at airline proportions
    // rather than as oversized tiles: 17.2" seat, 20" aisle, 139" interior
    // width, 31" pitch. One point here is roughly half an inch of cabin.
    private var seatSize: CGFloat { 34 }
    private var seatGap: CGFloat { 3 }
    /// Wider than a seat, as the aisle is on the real aircraft.
    private var aisleWidth: CGFloat { 38 }
    /// Sidewall and armrest margin — also wide enough to hold a turned EXIT
    /// marker beside the window seats.
    private var edgeInset: CGFloat { 16 }
    /// Cushion depth. Shorter than the pitch, which is what leaves the
    /// legroom gap between rows.
    private var seatDepth: CGFloat { 34 }
    /// Seats are drawn smaller than they are tapped: the button fills the row
    /// pitch so no target falls below the 44pt minimum.
    private var rowPitch: CGFloat { 46 }

    private var groupWidth: CGFloat {
        let count = CGFloat(plan.maxSeatsPerRow / 2)
        return count * seatSize + (count - 1) * seatGap
    }

    private var fuselageWidth: CGFloat {
        groupWidth * 2 + aisleWidth + edgeInset * 2
    }

    /// First-class seats are wider because there are fewer of them across the
    /// same cabin — the geometry produces the recliner, no special casing.
    private func seatWidth(premium: Bool, perSide: Int) -> CGFloat {
        premium ? (groupWidth - seatGap * CGFloat(perSide - 1)) / CGFloat(perSide) : seatSize
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            legend
                .padding(.top, 8)
                .padding(.bottom, 10)

            ScrollView(showsIndicators: false) {
                airframe
                    .frame(maxWidth: max(300, fuselageWidth))
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                    .padding(.bottom, 16)
            }

            selectionCard
        }
        .background(Theme.seatMapBackground.ignoresSafeArea())
        .onChange(of: session.aircraft) { _, _ in
            // Letters and rows differ between aircraft, so a held seat may not
            // exist on the new one.
            withAnimation(.snappy(duration: 0.25)) { selected = nil }
        }
    }

    // MARK: Header / legend

    private var header: some View {
        HStack(spacing: 12) {
            Text("Choose your seat")
                .font(.system(size: 22, weight: .bold))
            Spacer()
            Menu {
                Picker("Aircraft", selection: $session.aircraft) {
                    ForEach(AircraftProfile.allCases) { aircraft in
                        Text(aircraft.name).tag(aircraft)
                    }
                }
            } label: {
                Label(session.aircraft.name, systemImage: session.aircraft.symbol)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(Theme.seatMapInk.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Theme.seatMapInk.opacity(0.06), in: Capsule())
            }
            .accessibilityLabel("Aircraft model, \(session.aircraft.name)")
        }
        .foregroundStyle(Theme.seatMapInk)
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 2)
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

    // MARK: Airframe

    private var airframe: some View {
        VStack(spacing: 0) {
            nose
            ForEach(Array(plan.cabins.enumerated()), id: \.element.id) { index, cabin in
                cabinDivider(cabin.name.uppercased())
                    .padding(.top, index == 0 ? 0 : 18)
                    .padding(.bottom, 10)
                columnHeaders(cabin)
                ForEach(cabin.rows, id: \.self) { row in
                    seatRow(row, cabin: cabin)
                }
            }
        }
        .padding(.bottom, 34)
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

    // MARK: Rows

    private func columnHeaders(_ cabin: CabinPlan.Cabin) -> some View {
        let width = seatWidth(premium: cabin.isPremium, perSide: cabin.left.count)
        return HStack(spacing: 0) {
            letterGroup(cabin.left, width: width)
            Text("").frame(width: aisleWidth)
            letterGroup(cabin.right, width: width)
        }
        .padding(.horizontal, edgeInset)
        .padding(.bottom, 2)
        .accessibilityHidden(true)
    }

    private func letterGroup(_ letters: [String], width: CGFloat) -> some View {
        HStack(spacing: seatGap) {
            ForEach(letters, id: \.self) { letter in
                Text(letter)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.seatMapInk.opacity(0.45))
                    .frame(width: width)
            }
        }
    }

    private func seatRow(_ row: Int, cabin: CabinPlan.Cabin) -> some View {
        let width = seatWidth(premium: cabin.isPremium, perSide: cabin.left.count)
        let isExit = plan.exitRows.contains(row)
        return HStack(spacing: 0) {
            seatGroup(cabin.left, row: row, cabin: cabin, width: width)
            Text("\(row)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.seatMapInk.opacity(0.28))
                .frame(width: aisleWidth)
            seatGroup(cabin.right, row: row, cabin: cabin, width: width)
        }
        .padding(.horizontal, edgeInset)
        .padding(.vertical, cabin.isPremium ? 5 : 2)
        .overlay {
            if isExit {
                // Turned to run along the fuselage, the way a door marking
                // does, so the tag sits in the margin instead of over a seat.
                HStack(spacing: 0) {
                    exitTag.rotationEffect(.degrees(-90))
                    Spacer()
                    exitTag.rotationEffect(.degrees(90))
                }
                .accessibilityHidden(true)
            }
        }
    }

    private func seatGroup(_ letters: [String], row: Int,
                           cabin: CabinPlan.Cabin, width: CGFloat) -> some View {
        HStack(spacing: seatGap) {
            ForEach(letters, id: \.self) { letter in
                seatButton(row: row, letter: letter, cabin: cabin, width: width)
            }
        }
    }

    /// Red EXIT markers on the fuselage edge, the way airline seat maps mark
    /// the over-wing doors.
    private var exitTag: some View {
        Text("EXIT")
            .font(.system(size: 7, weight: .heavy))
            .kerning(0.8)
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color(hex: "C4453B"), in: RoundedRectangle(cornerRadius: 3))
    }

    // MARK: Seats

    private func seatButton(row: Int, letter: String,
                            cabin: CabinPlan.Cabin, width: CGFloat) -> some View {
        let id = displaySeat(row: row, letter: letter)
        let taken = isTaken(id)
        let locked = cabin.isPremium && !session.isPremiumCabin
        let unavailable = taken || locked
        let isSelected = selected == id

        return Button {
            guard !unavailable else { return }
            Haptics.tap()
            CabinAudioEngine.shared.playSeatLatch()
            withAnimation(.snappy(duration: 0.25)) { selected = id }
        } label: {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(seatColor(cabin: cabin, taken: unavailable, selected: isSelected))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(seatBorder(cabin: cabin, taken: unavailable,
                                                 selected: isSelected), lineWidth: 1)
                }
                .overlay {
                    if isSelected {
                        Text(id)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.7)
                    } else if locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.seatMapInk.opacity(0.3))
                    }
                }
                // A headrest notch at the top of the cushion is what makes a
                // rounded square read as a seat seen from above.
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(.white.opacity(unavailable ? 0.3 : 0.55))
                        .frame(width: width * 0.42, height: 3)
                        .padding(.top, 4)
                        .opacity(isSelected ? 0.9 : 1)
                }
                .frame(width: width, height: seatDepth)
                .frame(height: rowPitch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(unavailable)
        .scaleEffect(isSelected ? 1.06 : 1)
        .animation(.snappy(duration: 0.25), value: isSelected)
        .accessibilityLabel(accessibilityLabel(id: id, cabin: cabin, taken: taken, locked: locked))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Premium seats are announced by cabin; every other seat is plain
    /// "Seat C10", which is also the contract the UI tests select on.
    private func accessibilityLabel(id: String, cabin: CabinPlan.Cabin,
                                    taken: Bool, locked: Bool) -> String {
        let prefix = cabin.isPremium ? "First class seat" : "Seat"
        if locked { return "\(prefix) \(id), unlock at Silver tier" }
        if taken { return "\(prefix) \(id), taken" }
        return "\(prefix) \(id)"
    }

    private func seatColor(cabin: CabinPlan.Cabin, taken: Bool, selected: Bool) -> Color {
        if selected { return Theme.seatChosen }
        if taken { return Theme.seatTakenFill }
        return cabin.isPremium ? Theme.seatFirstGold : Theme.seatOpen
    }

    private func seatBorder(cabin: CabinPlan.Cabin, taken: Bool, selected: Bool) -> Color {
        if selected { return .clear }
        if taken { return Theme.seatMapInk.opacity(0.05) }
        return cabin.isPremium
            ? Theme.seatFirstGold.opacity(0.9)
            : Theme.accent.opacity(0.35)
    }

    // MARK: Seat identity

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

    /// First available (non-taken, non-locked) seat, main cabins first — used
    /// when the traveler skips seat selection.
    private var defaultSeat: String? {
        for cabin in plan.cabins where !(cabin.isPremium && !session.isPremiumCabin) {
            for row in cabin.rows {
                for letter in cabin.left + cabin.right {
                    let id = displaySeat(row: row, letter: letter)
                    if !isTaken(id) { return id }
                }
            }
        }
        return nil
    }

    private var cabinClass: String {
        guard let row = selectedRow else { return "—" }
        return plan.cabin(forRow: row)?.name ?? "—"
    }

    // MARK: Selection summary

    private var selectionCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top) {
                selectionField("Cabin Class", cabinClass)
                Spacer()
                selectionField("Selected Seat", selected ?? "—", centered: true)
                Spacer()
                selectionField("Flight No", session.currentLeg.flightNumber, trailing: true)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Focus block")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.seatMapInk.opacity(0.5))
                    Text(session.itinerary.totalFocusDuration.shortDurationText)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Theme.seatMapInk)
                        .contentTransition(.numericText())
                    Text("Uninterrupted study time")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.seatMapInk.opacity(0.35))
                }
                Spacer()
                Button {
                    // Skip assigns the first open seat; otherwise take the
                    // chosen one. Either way, always advances.
                    guard let seat = selected ?? defaultSeat else { return }
                    session.seat = seat
                    Haptics.success()
                    onContinue()
                } label: {
                    HStack(spacing: 8) {
                        Text(selected == nil ? "Skip" : "Continue")
                        Image(systemName: "arrow.right")
                    }
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 52)
                        .background(Theme.accent, in: Capsule())
                }
                .accessibilityLabel(selected.map { "Take seat \($0)" } ?? "Skip seat selection")
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

    private func selectionField(_ label: String, _ value: String,
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
