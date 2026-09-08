import SwiftUI

/// Airline-style seat map, drawn from the aircraft's real cabin plan and its
/// real planform: nose taper, constant-section cabin, swept wing, tailcone.
///
/// The aircraft is drawn full-bleed rather than as a diagram on a card. The
/// wings run past both screen edges instead of stopping in stubs, so the map
/// reads as a slice of a real airframe you are scrolling along.
///
/// Follows the conventions carriers use on their own maps, so a frequent flyer
/// can read it without a key: taken seats are struck through with an X rather
/// than drawn as filled boxes, each cabin is closed off by a bulkhead, the row
/// number sits in the aisle, exit doors are marked at the fuselage wall, and
/// the galley and lavatories sit where they actually are. Picking a seat
/// raises the detail callout a booking flow would.
struct SeatSelectionView: View {
    @Bindable var session: FlightSession
    let onContinue: () -> Void

    @State private var selected: String?
    /// Centre of the over-wing exit rows, measured from the cabin's own top so
    /// the wing box is drawn where the exits actually are on this aircraft.
    @State private var wingCenterY: CGFloat = 0

    private static let cabinSpace = "voyage.cabin"

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
    /// Sidewall and armrest margin, also wide enough to hold an exit door bar
    /// beside the window seats.
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

    /// A pointed nose is a long nose. Blunt narrowbody domes are short, a
    /// supersonic spike runs for several rows before the cabin starts.
    private var noseLength: CGFloat {
        rowPitch * (1.0 + (1.0 - plan.noseFullness) * 2.6)
    }

    private var tailLength: CGFloat { rowPitch * 2.4 }

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
                cabin
                    .background(alignment: .top) { airframe }
                    .coordinateSpace(name: Self.cabinSpace)
                    .onPreferenceChange(WingAnchorKey.self) { wingCenterY = $0 }
            }

            VStack(spacing: 0) {
                if let selected {
                    seatCallout(for: selected)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                selectionCard
            }
            .animation(.snappy(duration: 0.28), value: selected)
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
            legendChip(swatch: AnyView(seatSwatch(Theme.seatFirstGold)), label: "First")
            legendChip(swatch: AnyView(seatSwatch(Theme.seatOpen)), label: "Available")
            legendChip(swatch: AnyView(takenGlyph(size: 13)), label: "Taken")
            legendChip(swatch: AnyView(seatSwatch(Theme.seatChosen)), label: "Selected")
        }
    }

    private func legendChip(swatch: AnyView, label: String) -> some View {
        HStack(spacing: 6) {
            swatch.frame(width: 15, height: 15)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.seatMapInk.opacity(0.8))
        }
    }

    private func seatSwatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(color)
    }

    // MARK: Airframe

    /// The aircraft itself, drawn behind the cabin and sized to it. Wings are
    /// deliberately run off both edges: a wing that stops inside the screen
    /// reads as a stub, and a real seat map at this zoom always cuts them.
    private var airframe: some View {
        AirframeCanvas(
            plan: plan,
            fuselageWidth: fuselageWidth,
            noseLength: noseLength,
            tailLength: tailLength,
            rowPitch: rowPitch,
            wingCenterY: wingCenterY
        )
    }

    // MARK: Cabin

    private var cabin: some View {
        VStack(spacing: 0) {
            flightDeck
            forwardGalley
            ForEach(Array(plan.cabins.enumerated()), id: \.element.id) { index, cabin in
                bulkhead(cabin.name.uppercased(), isFirst: index == 0)
                columnHeaders(cabin)
                ForEach(cabin.rows, id: \.self) { row in
                    seatRow(row, cabin: cabin)
                }
            }
            aftLavatories
            Color.clear.frame(height: tailLength)
        }
    }

    /// The nose is empty cabin-side, so the flight deck fills it: a windscreen
    /// and the two side windows either side of it.
    private var flightDeck: some View {
        Color.clear
            .frame(height: noseLength)
            .overlay(alignment: .bottom) {
                HStack(spacing: 4) {
                    cockpitGlass(width: 12, height: 9)
                    cockpitGlass(width: 30, height: 12)
                    cockpitGlass(width: 12, height: 9)
                }
                .padding(.bottom, 10)
            }
            .accessibilityHidden(true)
    }

    private func cockpitGlass(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Theme.seatMapInk.opacity(0.8))
            .frame(width: width, height: height)
    }

    /// Forward galley and the lavatory across from it, ahead of row 1. Sized
    /// against the seat pitch so the furniture is in scale with the cabin.
    private var forwardGalley: some View {
        HStack(spacing: seatGap) {
            galleyBox
                .frame(width: groupWidth)
            Color.clear.frame(width: aisleWidth)
            lavatoryBox(accessible: true)
                .frame(width: groupWidth)
        }
        .frame(height: rowPitch * 0.92)
        .padding(.horizontal, edgeInset)
        .padding(.bottom, 4)
        .accessibilityHidden(true)
    }

    /// The aft pair, either side of the rear aisle, where they sit on a
    /// single-aisle aircraft.
    private var aftLavatories: some View {
        HStack(spacing: seatGap) {
            lavatoryBox(accessible: false)
                .frame(width: groupWidth)
            Color.clear.frame(width: aisleWidth)
            galleyBox
                .frame(width: groupWidth)
        }
        .frame(height: rowPitch * 0.92)
        .padding(.horizontal, edgeInset)
        .padding(.top, 8)
        .accessibilityHidden(true)
    }

    /// A galley reads as its cart bays: a run of vertical dividers, not a
    /// blank box with an icon dropped in the middle.
    private var galleyBox: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Theme.seatMapInk.opacity(0.05))
            .overlay {
                GeometryReader { geo in
                    let bays = 4
                    let step = geo.size.width / CGFloat(bays)
                    Path { path in
                        for index in 1..<bays {
                            let x = step * CGFloat(index)
                            path.move(to: CGPoint(x: x, y: 5))
                            path.addLine(to: CGPoint(x: x, y: geo.size.height - 5))
                        }
                    }
                    .stroke(Theme.seatMapInk.opacity(0.16), lineWidth: 1)
                }
            }
            .overlay(alignment: .topLeading) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.seatMapInk.opacity(0.35))
                    .padding(4)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Theme.seatMapInk.opacity(0.12), lineWidth: 1)
            }
    }

    /// A lavatory reads as its door: the swept arc is the convention every
    /// cabin layout drawing uses.
    private func lavatoryBox(accessible: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Theme.seatMapInk.opacity(0.05))
            .overlay {
                GeometryReader { geo in
                    // Door swing: a quarter arc struck from the hinge corner.
                    let radius = min(geo.size.width, geo.size.height) * 0.62
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: geo.size.height))
                        path.addArc(
                            center: CGPoint(x: 0, y: geo.size.height),
                            radius: radius,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(0),
                            clockwise: false
                        )
                    }
                    .stroke(Theme.seatMapInk.opacity(0.18), lineWidth: 1)
                }
            }
            .overlay {
                Image(systemName: accessible ? "figure.roll" : "figure.stand")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.seatMapInk.opacity(0.38))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Theme.seatMapInk.opacity(0.12), lineWidth: 1)
            }
    }

    /// Cabins are closed off by a bulkhead and curtain, not a filled grey band.
    /// The curtain folds are what make the divider read as cabin furniture.
    private func bulkhead(_ label: String, isFirst: Bool) -> some View {
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.seatMapInk.opacity(0.10))
                    .frame(height: 7)
                GeometryReader { geo in
                    // Curtain folds, drawn as a shallow run of pleats.
                    let pleat: CGFloat = 7
                    let count = max(1, Int(geo.size.width / pleat))
                    Path { path in
                        for index in 0...count {
                            let x = CGFloat(index) * pleat
                            path.move(to: CGPoint(x: x, y: 1))
                            path.addLine(to: CGPoint(x: x, y: 6))
                        }
                    }
                    .stroke(Theme.seatMapFuselage.opacity(0.7), lineWidth: 1)
                }
                .frame(height: 7)
            }
            Text(label)
                .font(.system(size: 10, weight: .heavy))
                .kerning(1.6)
                .foregroundStyle(Theme.seatMapInk.opacity(0.5))
                .accessibilityAddTraits(.isHeader)
        }
        // Sized to the cabin interior, not the screen: the bulkhead spans the
        // fuselage and stops at the sidewall.
        .frame(width: fuselageWidth - edgeInset * 2)
        .padding(.top, isFirst ? 6 : 18)
        .padding(.bottom, 2)
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
        .padding(.top, 6)
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
                // The door is a bar set into the fuselage wall beside the row
                // it serves, so it lands in the margin instead of over a seat.
                HStack(spacing: 0) {
                    exitDoor
                    Spacer()
                    exitDoor
                }
                .accessibilityHidden(true)
            }
        }
        .background {
            // Report where the wing box belongs, so the planform behind the
            // cabin lines up with the exits rather than guessing.
            if row == plan.wingAnchorRow {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: WingAnchorKey.self,
                        value: geo.frame(in: .named(Self.cabinSpace)).midY
                    )
                }
            }
        }
    }

    private func seatGroup(_ letters: [String], row: Int,
                           cabin: CabinPlan.Cabin, width: CGFloat) -> some View {
        HStack(spacing: seatGap) {
            ForEach(letters, id: \.self) { letter in
                seatCell(row: row, letter: letter, cabin: cabin, width: width)
            }
        }
    }

    /// Red door bars on the fuselage edge, the way airline seat maps mark the
    /// over-wing exits.
    private var exitDoor: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(Color(hex: "C4453B"))
            .frame(width: 5, height: 22)
    }

    // MARK: Seats

    /// A taken seat is an X on the page, not a filled box. It is the single
    /// clearest signal on any real seat map, and it keeps the sold cabin from
    /// reading as heavier than the open one.
    private func takenGlyph(size: CGFloat) -> some View {
        Image(systemName: "xmark")
            .font(.system(size: size, weight: .light))
            .foregroundStyle(Theme.seatMapInk.opacity(0.22))
    }

    @ViewBuilder
    private func seatCell(row: Int, letter: String,
                          cabin: CabinPlan.Cabin, width: CGFloat) -> some View {
        let id = displaySeat(row: row, letter: letter)
        let taken = isTaken(id)
        let locked = cabin.isPremium && !session.isPremiumCabin

        if taken {
            // Not a Button: a sold seat is not a control, and leaving it out of
            // the button tree keeps "tap the first free seat" honest for tests
            // and for VoiceOver alike.
            takenGlyph(size: 17)
                .frame(width: width, height: seatDepth)
                .frame(height: rowPitch)
                .accessibilityLabel(accessibilityLabel(id: id, cabin: cabin,
                                                       taken: true, locked: false))
        } else {
            seatButton(id: id, cabin: cabin, width: width, locked: locked)
        }
    }

    private func seatButton(id: String, cabin: CabinPlan.Cabin,
                            width: CGFloat, locked: Bool) -> some View {
        let isSelected = selected == id

        return Button {
            guard !locked else { return }
            Haptics.tap()
            CabinAudioEngine.shared.playSeatLatch()
            withAnimation(.snappy(duration: 0.25)) { selected = id }
        } label: {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(seatColor(cabin: cabin, dimmed: locked, selected: isSelected))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(seatBorder(cabin: cabin, dimmed: locked,
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
                        .fill(.white.opacity(locked ? 0.3 : 0.55))
                        .frame(width: width * 0.42, height: 3)
                        .padding(.top, 4)
                        .opacity(isSelected ? 0.9 : 1)
                }
                .frame(width: width, height: seatDepth)
                .frame(height: rowPitch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .scaleEffect(isSelected ? 1.06 : 1)
        .animation(.snappy(duration: 0.25), value: isSelected)
        .accessibilityLabel(accessibilityLabel(id: id, cabin: cabin, taken: false, locked: locked))
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

    /// Sold seats never reach here, so the only dimmed state is a premium seat
    /// gated behind the tier the traveler has not reached yet.
    private func seatColor(cabin: CabinPlan.Cabin, dimmed: Bool, selected: Bool) -> Color {
        if selected { return Theme.seatChosen }
        if dimmed { return Theme.seatTakenFill }
        return cabin.isPremium ? Theme.seatFirstGold : Theme.seatOpen
    }

    private func seatBorder(cabin: CabinPlan.Cabin, dimmed: Bool, selected: Bool) -> Color {
        if selected { return .clear }
        if dimmed { return Theme.seatMapInk.opacity(0.05) }
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

    // MARK: Selection callout

    /// The detail card a seat map raises when you pick a seat: which seat,
    /// which cabin, which flight, and what the seat actually buys you.
    private func seatCallout(for id: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(id)
                .font(.system(size: 15, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Theme.seatChosen,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(cabinClass)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.seatMapInk)
                Text("\(session.currentLeg.flightNumber) · \(session.aircraft.name)")
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

    /// What the seat buys you, read off the cabin plan rather than hardcoded
    /// rows, so it stays true when the traveler switches aircraft.
    private func seatPerk(for id: String) -> String {
        guard let row = Int(id.filter(\.isNumber)),
              let cabin = plan.cabin(forRow: row) else { return "Standard seat" }
        if cabin.isPremium { return "Wider recliner, first to board" }
        if plan.exitRows.contains(row) { return "Extra legroom at the exit door" }
        if let wing = plan.wingAnchorRow, (wing...(wing + 3)).contains(row) {
            return "Over the wing, wing in view"
        }
        if cabin.name == "Extra Legroom" { return "Extra legroom" }
        return "Standard seat"
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

// MARK: - Wing placement

/// Carries the measured centre of the over-wing exit rows up to the airframe.
private struct WingAnchorKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next != 0 { value = next }
    }
}

// MARK: - Airframe

/// The aircraft drawn behind the cabin: wing, engines, tailplane, then the
/// fuselage over the top of them.
///
/// Everything is driven off the aircraft's own `CabinPlan` geometry, so the
/// narrowbodies get a modestly swept wing with big nacelles and the supersonic
/// gets a long, highly swept delta and a spike nose. The wing is drawn out past
/// both edges of the canvas on purpose: it is cut by the screen rather than
/// stopping in a stub, which is how a real seat map reads at this zoom.
private struct AirframeCanvas: View {
    let plan: CabinPlan
    let fuselageWidth: CGFloat
    let noseLength: CGFloat
    let tailLength: CGFloat
    let rowPitch: CGFloat
    let wingCenterY: CGFloat

    var body: some View {
        Canvas { context, size in
            let midX = size.width / 2
            let halfBody = fuselageWidth / 2
            let bodyLeft = midX - halfBody
            let bodyRight = midX + halfBody
            // Run the planform past the canvas so the edge does the cutting.
            let bleed: CGFloat = 48

            // Wing box centre: fall back to a sensible spot before the first
            // layout pass reports where the exit rows landed.
            let wingY = wingCenterY > 0 ? wingCenterY : size.height * 0.55

            drawWing(context: context, size: size, bodyLeft: bodyLeft,
                     bodyRight: bodyRight, wingY: wingY, bleed: bleed)
            drawTailplane(context: context, size: size, midX: midX,
                          halfBody: halfBody)
            drawFuselage(context: context, size: size, midX: midX,
                         halfBody: halfBody)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Wing

    private func drawWing(context: GraphicsContext, size: CGSize,
                          bodyLeft: CGFloat, bodyRight: CGFloat,
                          wingY: CGFloat, bleed: CGFloat) {
        // Horizontal run from the fuselage side to past the screen edge.
        let span = bodyLeft + bleed
        // A delta carries its chord along most of the fuselage; a narrowbody
        // wing is a much shorter root.
        let rootChord = rowPitch * (2.6 + plan.wingSpan * 1.6)
        let tipChord = max(8, rootChord * (0.30 - plan.wingSweep * 0.18))
        let sweep = span * plan.wingSweep * 1.15
        let rootLead = wingY - rootChord * 0.45
        let tipLead = rootLead + sweep

        for side in [-1.0, 1.0] {
            let root = side < 0 ? bodyLeft : bodyRight
            let tip = side < 0 ? -bleed : size.width + bleed
            var path = Path()
            path.move(to: CGPoint(x: root, y: rootLead))
            path.addLine(to: CGPoint(x: tip, y: tipLead))
            path.addLine(to: CGPoint(x: tip, y: tipLead + tipChord))
            path.addLine(to: CGPoint(x: root, y: rootLead + rootChord))
            path.closeSubpath()
            context.fill(path, with: .color(Theme.seatMapWing))

            // Nacelle slung under the leading edge, out at the pylon station.
            let engineX = root + (tip - root) * 0.40
            let engineLead = rootLead + (tipLead - rootLead) * 0.40
            let engineLength = rowPitch * (0.9 + plan.engineSize * 3.4)
            let engineWidth = max(9, fuselageWidth * plan.engineSize * 0.85)
            let engine = CGRect(x: engineX - engineWidth / 2,
                                y: engineLead + rootChord * 0.10,
                                width: engineWidth,
                                height: engineLength)
            context.fill(
                Path(roundedRect: engine, cornerRadius: engineWidth / 2),
                with: .color(Theme.seatMapInk.opacity(0.16))
            )
        }
    }

    // MARK: Tailplane

    private func drawTailplane(context: GraphicsContext, size: CGSize,
                               midX: CGFloat, halfBody: CGFloat) {
        let y = size.height - tailLength * 0.72
        let chord = rowPitch * 1.15
        let span = halfBody * 1.55
        let sweep = span * 0.55

        for side in [-1.0, 1.0] {
            let root = midX + halfBody * 0.72 * side
            let tip = root + span * side
            var path = Path()
            path.move(to: CGPoint(x: root, y: y))
            path.addLine(to: CGPoint(x: tip, y: y + sweep))
            path.addLine(to: CGPoint(x: tip, y: y + sweep + chord * 0.34))
            path.addLine(to: CGPoint(x: root, y: y + chord))
            path.closeSubpath()
            context.fill(path, with: .color(Theme.seatMapWing))
        }
    }

    // MARK: Fuselage

    /// Nose taper, constant-section cabin, tailcone. `noseFullness` moves the
    /// shoulder: a blunt narrowbody reaches full width almost immediately, a
    /// supersonic spike carries the taper for several rows.
    private func drawFuselage(context: GraphicsContext, size: CGSize,
                              midX: CGFloat, halfBody: CGFloat) {
        let fullness = plan.noseFullness
        let bodyLeft = midX - halfBody
        let bodyRight = midX + halfBody
        // The tailcone narrows but never closes to a point: that stub is the
        // APU exhaust, and closing it makes the tail read as a dart.
        let tailHalf = halfBody * 0.20
        let tailStart = size.height - tailLength

        var path = Path()
        path.move(to: CGPoint(x: bodyLeft, y: noseLength))
        // Left side of the nose, tip, then right side.
        path.addCurve(
            to: CGPoint(x: midX, y: 0),
            control1: CGPoint(x: bodyLeft, y: noseLength * (1 - fullness * 0.75)),
            control2: CGPoint(x: midX - halfBody * fullness, y: 0)
        )
        path.addCurve(
            to: CGPoint(x: bodyRight, y: noseLength),
            control1: CGPoint(x: midX + halfBody * fullness, y: 0),
            control2: CGPoint(x: bodyRight, y: noseLength * (1 - fullness * 0.75))
        )
        // Constant section down to where the tail starts.
        path.addLine(to: CGPoint(x: bodyRight, y: tailStart))
        path.addQuadCurve(
            to: CGPoint(x: midX + tailHalf, y: size.height),
            control: CGPoint(x: bodyRight, y: size.height - tailLength * 0.28)
        )
        path.addLine(to: CGPoint(x: midX - tailHalf, y: size.height))
        path.addQuadCurve(
            to: CGPoint(x: bodyLeft, y: tailStart),
            control: CGPoint(x: bodyLeft, y: size.height - tailLength * 0.28)
        )
        path.closeSubpath()

        context.fill(path, with: .color(Theme.seatMapFuselage))
        context.stroke(path, with: .color(Theme.seatMapInk.opacity(0.10)), lineWidth: 1)
    }
}
