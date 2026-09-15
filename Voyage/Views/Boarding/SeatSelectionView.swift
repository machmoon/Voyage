import SwiftUI

/// Airline-style seat map, drawn from the aircraft's real cabin plan and its
/// real planform (`AircraftProfile.planform`): flight deck, constant-section
/// cabin, swept wing, tailplane and fin.
///
/// The airframe is drawn at true proportion around the seat grid rather than
/// shrunk to fit the phone. A narrowbody's wing is about four fuselage widths
/// long, so it runs far past both screen edges, and its chord covers the eight
/// or so rows it really does. Scrolling the cabin moves along a real aircraft.
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
    /// the wing is drawn where the exits actually are on this aircraft.
    @State private var exitRowCenters: [Int: CGFloat] = [:]

    private static let cabinSpace = "voyage.cabin"
    fileprivate static let tailClearance: CGFloat = 28

    private var plan: CabinPlan { session.aircraft.cabinPlan }
    private var planform: AirframePlanform { session.aircraft.planform }

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

    /// Points per metre across the aircraft: the drawn fuselage is the real
    /// fuselage width.
    private var xScale: CGFloat { fuselageWidth / CGFloat(planform.fuselageWidth) }

    /// Points per metre along the aircraft: one row pitch is one real seat
    /// pitch.
    private var yScale: CGFloat { rowPitch / CGFloat(AirframePlanform.seatPitch) }

    /// Flight deck and forward galley, ahead of row 1.
    private var noseLength: CGFloat { CGFloat(planform.noseToFirstRow) * yScale }

    /// Aft galley and tailcone, behind the last row.
    private var tailLength: CGFloat { CGFloat(planform.aftOfLastRow) * yScale }

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
                    .onPreferenceChange(ExitRowCentersKey.self) { exitRowCenters = $0 }
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
        .onAppear { preselectRememberedSeat() }
        .onChange(of: session.aircraft) { _, _ in
            // Letters and rows differ between aircraft, so a held seat may not
            // exist on the new one.
            withAnimation(.snappy(duration: 0.25)) { selected = nil }
            preselectRememberedSeat()
        }
    }

    /// Same seat as last time. The remembered seat is only offered when it
    /// was taken on this aircraft and is still open: a seat that is taken
    /// or in a cabin the traveler cannot book leaves the map unselected,
    /// so nothing here changes the "Take seat" contract of the button.
    private func preselectRememberedSeat() {
        guard selected == nil,
              let remembered = SettingsStore.shared.lastSeat(on: session.aircraft),
              isAvailable(remembered) else { return }
        selected = remembered
    }

    /// True when `seatID` exists on this cabin plan, is not taken, and is
    /// in a cabin the traveler can book.
    private func isAvailable(_ seatID: String) -> Bool {
        guard let row = Int(seatID.filter(\.isNumber)) else { return false }
        let letter = seatID.filter(\.isLetter)
        guard let cabin = plan.cabins.first(where: { $0.rows.contains(row) }),
              (cabin.left + cabin.right).contains(letter),
              !(cabin.isPremium && !session.isPremiumCabin) else { return false }
        return !isTaken(seatID)
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

    /// The aircraft itself, drawn behind the cabin and sized to it.
    ///
    /// The canvas is exactly the scroll content's size, so everything past the
    /// screen edge (most of each wing, the stabiliser tips, the engines) is
    /// clipped by the canvas and never reaches layout: no horizontal scroll,
    /// no wider content. It sits in the cabin's background and ignores hits,
    /// so no part of the airframe can take a tap from a seat.
    private var airframe: some View {
        AirframeCanvas(
            planform: planform,
            xScale: xScale,
            yScale: yScale,
            wingAnchorY: wingAnchorY
        )
    }

    /// Midway between the first and last over-wing exit rows. The two rows
    /// can straddle a cabin header, so both are measured.
    private var wingAnchorY: CGFloat {
        let centers = plan.exitRows.compactMap { exitRowCenters[$0] }
        guard !centers.isEmpty else { return 0 }
        return ((centers.min() ?? 0) + (centers.max() ?? 0)) / 2
    }

    // MARK: Cabin

    private var cabin: some View {
        VStack(spacing: 0) {
            flightDeck
            ForEach(Array(plan.cabins.enumerated()), id: \.element.id) { index, cabin in
                bulkhead(cabin.name.uppercased(), isFirst: index == 0)
                columnHeaders(cabin)
                ForEach(cabin.rows, id: \.self) { row in
                    seatRow(row, cabin: cabin)
                }
            }
            // The tailcone, plus a little clear page past the tail end so
            // the last of the airframe never tucks under the Continue card.
            Color.clear.frame(height: tailLength + Self.tailClearance)
        }
    }

    /// The nose is empty cabin-side. The flight deck is drawn with the nose
    /// in `AirframeCanvas`, so this only reserves the space.
    private var flightDeck: some View {
        Color.clear.frame(height: noseLength).accessibilityHidden(true)
    }

    /// The curtain folds are what make the divider read as cabin furniture.
    private func bulkhead(_ label: String, isFirst: Bool) -> some View {
        // A cabin header the way United's seat map labels one: a plain band
        // with the cabin name, no curtain drawing.
        Text(label.capitalized)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.seatMapInk.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Theme.seatMapInk.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityAddTraits(.isHeader)
            .frame(width: fuselageWidth - edgeInset * 2)
            .padding(.top, isFirst ? 2 : 18)
            .padding(.bottom, 6)
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
            // Report where the exits are, so the wing behind the cabin lines
            // up with them rather than guessing.
            if isExit {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ExitRowCentersKey.self,
                        value: [row: geo.frame(in: .named(Self.cabinSpace)).midY]
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
                // The aircraft is named in the header and the flight on the
                // pass. The perk line is dropped when it only repeats the
                // cabin name.
                let perk = seatPerk(for: id)
                if perk.lowercased() != cabinClass.lowercased() {
                    Text(perk)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.seatMapInk.opacity(0.6))
                }
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

    /// One control. The floating callout above already names the seat, the
    /// cabin and the flight, so nothing is repeated here.
    private var selectionCard: some View {
        VStack(spacing: 14) {
            HStack {
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
                            .lineLimit(1)
                        Image(systemName: "arrow.right")
                    }
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
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
}

// MARK: - Wing placement

/// Carries the measured centre of each over-wing exit row up to the airframe.
private struct ExitRowCentersKey: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - Airframe

/// The aircraft drawn behind the cabin: engines, wings and tailplane, then the
/// fuselage over their roots, then the flight deck glazing and the fin.
///
/// Geometry comes from `AirframeOutline`. The nose is placed at the top of the
/// cabin, the tail end at the bottom, and the wing around the measured
/// over-wing exit row.
private struct AirframeCanvas: View {
    let planform: AirframePlanform
    let xScale: CGFloat
    let yScale: CGFloat
    /// Centre of the over-wing exit rows, in the cabin's coordinates.
    let wingAnchorY: CGFloat

    var body: some View {
        Canvas { context, size in
            let outline = AirframeOutline(
                planform: planform,
                midX: size.width / 2,
                xScale: xScale,
                yScale: yScale,
                noseTipY: 1,
                // Before the first layout pass reports the exit row, park the
                // wing mid-cabin rather than at the nose.
                exitY: wingAnchorY > 0 ? wingAnchorY : size.height * 0.45,
                tailEndY: size.height - SeatSelectionView.tailClearance
            )
            let edge = Theme.seatMapInk.opacity(0.14)
            let hairline = StrokeStyle(lineWidth: 1, lineJoin: .round)

            for side: CGFloat in [-1, 1] {
                // Nacelles hang under the wing: drawn first, only the inlet
                // ahead of the leading edge shows, as it does from above.
                for nacelle in outline.nacelles(side: side) {
                    context.fill(nacelle, with: .color(Theme.seatMapNacelle))
                    context.stroke(nacelle, with: .color(edge), style: hairline)
                }
                let wing = outline.wing(side: side)
                context.fill(wing, with: .color(Theme.seatMapWing))
                context.stroke(wing, with: .color(edge), style: hairline)
                context.stroke(outline.wingPanelLines(side: side),
                               with: .color(Theme.seatMapInk.opacity(0.09)),
                               style: StrokeStyle(lineWidth: 0.75, lineCap: .round))

                if let tail = outline.horizontalTail(side: side) {
                    context.fill(tail, with: .color(Theme.seatMapWing))
                    context.stroke(tail, with: .color(edge), style: hairline)
                }
            }

            // A soft shadow lifts the white fuselage off the wing and the page.
            let fuselage = outline.fuselage
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(0.10), radius: 10, y: 2))
                layer.fill(fuselage, with: .color(Theme.seatMapFuselage))
            }
            context.stroke(fuselage, with: .color(edge), style: hairline)

            context.drawLayer { glazing in
                glazing.clip(to: fuselage)
                for pane in outline.windshield {
                    glazing.fill(pane, with: .color(Theme.seatMapInk.opacity(0.82)))
                }
            }

            let fin = outline.fin
            context.fill(fin, with: .color(Theme.seatMapWing))
            context.stroke(fin, with: .color(edge), style: hairline)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
