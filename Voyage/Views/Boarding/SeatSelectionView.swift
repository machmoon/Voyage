import SwiftUI

/// Airline-style seat map, drawn from the aircraft's real cabin plan: a 2-2
/// First cabin, extra-legroom and main 3-3 cabins on the narrowbodies, exit
/// rows over a visible wing box, and a tailplane at the back. The airframe
/// silhouette changes with the aircraft, so a 737 and an A320neo are not the
/// same drawing with a different label.
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

    /// Seen from above, a narrowbody nose is a shallow cap — the flight deck
    /// is barely a third of a fuselage width long. Drawing it longer turned
    /// the top of the map into a dome with nothing in it.
    private var noseLength: CGFloat { fuselageWidth * (0.30 + 0.12 * plan.noseFullness) }
    private var tailLength: CGFloat { fuselageWidth * 0.42 }

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
                    .frame(width: fuselageWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                    .padding(.bottom, 28)
            }
            .scrollClipDisabled()

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
                        .background(alignment: .top) {
                            if row == plan.wingAnchorRow { wingLayer }
                        }
                }
            }
            tailBand
        }
        .background(
            FuselageShape(noseLength: noseLength, tailLength: tailLength)
                .fill(Theme.seatMapFuselage)
                .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
        )
    }

    /// Reserves exactly the height the shape spends on the nose cone, so the
    /// first row of seats begins where the fuselage reaches full width.
    private var nose: some View {
        // The flight-deck bulkhead, drawn as a light rule rather than a solid
        // slug so it recedes the way it does on an airline seat map.
        Capsule()
            .fill(Theme.seatMapInk.opacity(0.16))
            .frame(width: fuselageWidth * 0.34, height: 6)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 12)
            .frame(height: noseLength)
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

    /// A narrowbody wing is not a band between two rows. Its root chord is
    /// close to twice the fuselage width and its half-span is four times it,
    /// so at cabin scale the wing runs the length of the over-wing block and
    /// leaves the screen on both sides. Drawn behind the seats — the seats are
    /// inside the aircraft, so nothing about the wing may cover one.
    private var wingRootChord: CGFloat { fuselageWidth * 1.45 }
    private var wingOverhang: CGFloat { fuselageWidth * plan.wingSpan * 2.6 }

    private var wingLayer: some View {
        ZStack {
            WingPair(overhang: wingOverhang, sweep: plan.wingSweep)
                .fill(Theme.seatMapWing)
            EnginePair(overhang: wingOverhang, size: plan.engineSize)
                .fill(Theme.seatMapWing.opacity(0.9))
        }
        .frame(width: fuselageWidth + wingOverhang * 2, height: wingRootChord)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Horizontal stabilizers: the same wing geometry at a smaller scale,
    /// sitting where the fuselage begins to taper into the tail.
    private var tailBand: some View {
        // The stabiliser is roughly 40% of the wing's span and chord.
        let overhang = wingOverhang * 0.4
        return WingPair(overhang: overhang, sweep: plan.wingSweep * 1.6)
            .fill(Theme.seatMapWing)
            .frame(height: wingRootChord * 0.4)
            .padding(.horizontal, -overhang)
            .padding(.top, 18)
            .frame(height: tailLength, alignment: .top)
            .accessibilityHidden(true)
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
                    if let selected {
                        session.seat = selected
                        Haptics.success()
                        onContinue()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text("Continue")
                        Image(systemName: "arrow.right")
                    }
                        .font(.subheadline.bold())
                        .foregroundStyle(selected == nil ? Theme.seatMapInk.opacity(0.5) : .white)
                        .padding(.horizontal, 18)
                        .frame(height: 52)
                        .background(
                            selected == nil
                                ? Theme.seatTakenFill.opacity(0.6)
                                : Theme.accent,
                            in: Capsule()
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

// MARK: - Airframe shapes

/// Fuselage seen from above: an ogive nose cone, parallel sides through the
/// cabin, and a tail that tapers to a narrow boat-tail.
private struct FuselageShape: Shape {
    let noseLength: CGFloat
    let tailLength: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let nose = rect.minY + noseLength
        let tail = rect.maxY - tailLength
        // The cone ends in a small rounded cap rather than a point — the sides
        // hug the fuselage for most of the run, then turn in hard.
        let capHalf = rect.width * 0.26
        let tailHalf = rect.width * 0.16
        let hug = noseLength * 0.58

        // Control points stay inside the fuselage half-width, otherwise the
        // curve bows out past the cabin sides and the nose reads as a mushroom.
        let shoulder = min(capHalf * 1.5, rect.width * 0.4)

        path.move(to: CGPoint(x: rect.minX, y: nose))
        path.addCurve(to: CGPoint(x: rect.midX - capHalf, y: rect.minY),
                      control1: CGPoint(x: rect.minX, y: nose - hug),
                      control2: CGPoint(x: rect.midX - shoulder, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.midX + capHalf, y: rect.minY),
                          control: CGPoint(x: rect.midX, y: rect.minY - capHalf * 0.28))
        path.addCurve(to: CGPoint(x: rect.maxX, y: nose),
                      control1: CGPoint(x: rect.midX + shoulder, y: rect.minY),
                      control2: CGPoint(x: rect.maxX, y: nose - hug))
        path.addLine(to: CGPoint(x: rect.maxX, y: tail))
        path.addCurve(to: CGPoint(x: rect.midX + tailHalf, y: rect.maxY),
                      control1: CGPoint(x: rect.maxX, y: tail + tailLength * 0.45),
                      control2: CGPoint(x: rect.midX + tailHalf, y: rect.maxY - tailLength * 0.28))
        path.addLine(to: CGPoint(x: rect.midX - tailHalf, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.minX, y: tail),
                      control1: CGPoint(x: rect.midX - tailHalf, y: rect.maxY - tailLength * 0.28),
                      control2: CGPoint(x: rect.minX, y: tail + tailLength * 0.45))
        path.closeSubpath()
        return path
    }
}

/// A swept wing on each side, rooted at the fuselage edge and raked aft.
/// The centre is left empty so the wing never draws over the cabin.
private struct WingPair: Shape {
    let overhang: CGFloat
    /// Aft rake of the tip, as a fraction of the band height.
    let sweep: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let rootTop = rect.minY
        let rootBottom = rect.minY + rect.height * 0.78
        let tipTop = rect.minY + rect.height * sweep
        let tipBottom = tipTop + rect.height * 0.15
        let tipInset: CGFloat = 3

        for side in [true, false] {
            let root = side ? rect.minX + overhang : rect.maxX - overhang
            let tip = side ? rect.minX + tipInset : rect.maxX - tipInset
            path.move(to: CGPoint(x: root, y: rootTop))
            path.addLine(to: CGPoint(x: tip, y: tipTop))
            path.addLine(to: CGPoint(x: tip, y: tipBottom))
            path.addLine(to: CGPoint(x: root, y: rootBottom))
            path.closeSubpath()
        }
        return path
    }
}

/// Nacelles slung forward of the wing root — larger on the A320neo, which is
/// how you tell it from a 737 at a glance.
private struct EnginePair: Shape {
    let overhang: CGFloat
    /// Nacelle length as a fraction of the band height.
    let size: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let length = rect.height * size * 2.6
        let width = rect.height * size * 0.95
        let top = rect.minY - length * 0.28
        let offset = overhang * 0.34

        for side in [true, false] {
            let centre = side ? rect.minX + overhang - offset : rect.maxX - overhang + offset
            path.addRoundedRect(
                in: CGRect(x: centre - width / 2, y: top, width: width, height: length),
                cornerSize: CGSize(width: width / 2, height: width / 2)
            )
        }
        return path
    }
}
