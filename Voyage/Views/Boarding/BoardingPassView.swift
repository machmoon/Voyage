import SwiftUI
import SwiftData

/// The boarding pass prints down into view (with the dot-matrix sound to
/// match), then a drag-to-tear gesture along the perforation starts the
/// flight. Tearing IS departing — this is the commitment moment.
///
/// The pass carries one optional line, PURPOSE OF TRIP: what will be done
/// when you land. It replaced the separate check-a-bag step (2026-09-30),
/// because a checked bag is something you hand over and do not see again
/// until landing, the opposite of the thing you will work on. One purpose,
/// stated before the session and recorded after it: planning helps one goal
/// and stops helping across many (Dalton & Spiller 2012, doi:10.1086/664500),
/// and an intention made in advance is what works (Gollwitzer & Sheeran 2006,
/// doi:10.1016/S0065-2601(06)38002-1). FocusFlight prints the task on its
/// pass and Session opens each session with one intention; the open-source
/// precedent is Super Productivity's focus mode, one task per session, typed
/// or picked from suggestions shown before you search
/// (super-productivity/super-productivity, MIT, `src/app/features/focus-mode/
/// focus-mode-task-selector/focus-mode-task-selector.component.html`).
/// Tearing the pass is the commitment, so nothing else is asked: no code, no
/// category, no estimate.
struct BoardingPassView: View {
    @Bindable var session: FlightSession
    let onBoarded: () -> Void

    @State private var purpose = ""
    @FocusState private var purposeFocused: Bool
    @Query(sort: \LogbookEntry.date, order: .reverse) private var entries: [LogbookEntry]
    @State private var membership = Membership.shared
    @State private var showsPaywall = false

    @State private var printed = false
    /// 0→1 feed progress: the pass emerges below the slot in line-feed steps.
    @State private var printProgress: CGFloat = 0
    /// Measured height of the pass, so the feed starts with the paper fully
    /// inside the slot and every line-feed step shows a strip of it. A fixed
    /// travel was wrong both ways: taller passes peeked out before the first
    /// feed, shorter ones stayed hidden for the first three.
    @State private var passHeight: CGFloat = 0
    /// The last line has fed. The housing shows READY for a beat before it
    /// withdraws (`printed`), the way a gate printer sits still for a moment
    /// once the pass is out.
    @State private var feedComplete = false
    @State private var ripped = false
    /// 0→1 progress of sliding a cut across the perforation line.
    @State private var cutProgress: CGFloat = 0
    @State private var lastCutStep = 0
    /// The cut runs from whichever edge the finger starts toward: a slide to
    /// the right parts the seam from the left notch, a slide to the left from
    /// the right one. The stub hinges on the side still attached.
    @State private var cutFromTrailing = false
    @State private var passWidth: CGFloat = 0

    private var leg: FlightLeg { session.itinerary.legs[0] }

    /// Operating carrier from the flight number's airline code ("VOY 1546").
    private var carrierName: String {
        let code = leg.flightNumber.prefix { !$0.isWhitespace }
        return Carrier(rawValue: String(code))?.name.uppercased() ?? "VOYAGE AIR"
    }

    private var gate: String {
        var hash: UInt64 = 5381
        for byte in leg.flightNumber.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        return "B\(hash % 22 + 1)"
    }

    private var carrier: Carrier {
        Carrier(rawValue: String(leg.flightNumber.prefix { !$0.isWhitespace })) ?? .voyageAir
    }

    private var trimmedPurpose: String { purpose.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Up to four purposes to reuse with one tap: unfinished ones you chose
    /// to bring along first, then recent ones, never the one already written.
    private var recentPurposes: [String] {
        var seen: Set<String> = [trimmedPurpose.lowercased()]
        var result: [String] = []
        let candidates = CarriedPurposes.pending(in: Array(entries))
            + entries.prefix(20).flatMap(\.intentions)
        for candidate in candidates where !seen.contains(candidate.lowercased()) {
            seen.insert(candidate.lowercased())
            result.append(candidate)
            if result.count == 4 { break }
        }
        return result
    }

    private var carried: Set<String> {
        Set(CarriedPurposes.pending(in: Array(entries)).map { $0.lowercased() })
    }

    private var cabinClass: String {
        guard let row = Int(session.seat.filter(\.isNumber)) else { return "MAIN" }
        return (1...2).contains(row) ? "FIRST" : "MAIN"
    }


    var body: some View {
        ZStack {
            // Solid backdrop so the perforation punch-outs match exactly.
            Theme.boardingBackdrop
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 12)

                // The printer prints the pass, then slides up and vanishes,
                // leaving just the ticket. Removed (not hidden) so nothing
                // lingers; the layout animates so the ticket settles smoothly.
                if !printed {
                    printerHousing
                        .zIndex(2)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // The pass feeds out of the housing's slot, one line at a time.
                // A small negative top inset tucks the emerging edge under the
                // housing lip so it reads as coming *through* the slot.
                //
                // One view, one identity, for the whole sequence: the paper is
                // offset up by its own height and masked at the slot while it
                // prints, and the mask simply opens once it is out. Branching on
                // `printed` here built a second copy of the pass and crossfaded
                // the two under the retreating housing, which showed as a ghost
                // ticket bleeding through the real one (QA/printframes/p12.png).
                passCard
                    .padding(.horizontal, 28)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { passHeight = $0 }
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { passWidth = $0 }
                    .offset(y: -passHeight * (1 - printProgress))
                    // Not a frame before the measurement lands: an unmeasured
                    // pass would sit fully out of the slot for one layout pass.
                    .opacity(passHeight > 0 ? 1 : 0)
                    // Flush with the slot on top; generous elsewhere so the
                    // paper's shadow is never clipped and the torn stub can fall.
                    .mask(alignment: .top) {
                        Rectangle()
                            .padding(.horizontal, -60)
                            .padding(.bottom, -700)
                            .padding(.top, printed ? -400 : 0)
                    }
                    .padding(.top, -7)
                    // Above the button and hint below it, so the falling stub
                    // passes over them rather than under their text.
                    .zIndex(1)

                // The if-then plan written when this departure was scheduled
                // (`DeparturePlan`), read back at the gate.
                if printed, let plan = session.departurePlan {
                    Label {
                        Text(plan)
                            .font(.custom("Noteworthy-Bold", size: 15, relativeTo: .footnote))
                            .foregroundStyle(.white.opacity(0.9))
                            .multilineTextAlignment(.leading)
                    } icon: {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.horizontal, 34)
                    .padding(.top, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .accessibilityLabel("Your plan: \(plan)")
                    .accessibilityIdentifier("boarding-pass-plan")
                }

                if printed && !ripped && !recentPurposes.isEmpty {
                    recentPurposesRow
                        .padding(.top, 14)
                        .transition(.opacity)
                }

                if printed && !ripped && membership.isConfigured {
                    stylePicker
                        .padding(.top, 10)
                        .transition(.opacity)
                }

                Spacer()

                // Always in the layout once printed, faded rather than removed:
                // removing the button on rip let the spacers rebalance and the
                // whole pass jumped 26pt in the frame the stub let go
                // (QA/video/tear-2026-09-15).
                if printed {
                    Button {
                        rip()
                    } label: {
                        Text("Tear & board")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 28)
                            .frame(height: 52)
                            .background(Theme.accent, in: Capsule())
                    }
                    .accessibilityLabel("Tear and board")
                    .accessibilityHint("Tears the boarding pass stub and departs")
                    .opacity(ripped ? 0 : 1)
                    .allowsHitTesting(!ripped)
                    .accessibilityHidden(ripped)
                    .animation(.easeOut(duration: 0.2), value: ripped)
                    .transition(.opacity)
                }

                Text("Or slide along the dotted line.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(printed && !ripped && cutProgress == 0 ? 0.55 : 0))
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                    .animation(.smooth(duration: 0.3), value: printed)
                    .animation(.smooth(duration: 0.2), value: ripped)
                    .animation(.smooth(duration: 0.2), value: cutProgress == 0)
                    .accessibilityHidden(true)
            }
            .animation(.smooth(duration: 0.5), value: printed)
        }
        // The pass stays put while the purpose is typed; Done drops the
        // keyboard and the Tear button is back.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {
            if purpose.isEmpty, let first = session.intentions.first { purpose = first }
            startPrinting()
        }
        .firstClassPaywall(isPresented: $showsPaywall)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text("Tear & board")) {
            guard printed, !ripped else { return }
            rip()
        }
    }

    /// Gaps between line feeds — irregular, like a real gate printer that
    /// pauses on dense lines. The sound engine plays a burst per feed from
    /// this same schedule, so what you hear is what you see.
    static let feedSchedule: [Double] = [0.20, 0.15, 0.15, 0.30, 0.16, 0.16, 0.32, 0.18, 0.22]

    /// The gate printer the pass feeds out of: an ink-blue housing (the app's
    /// surface palette, not heavy black chrome) with a status light that pulses
    /// while printing, and a recessed slot along its bottom lip that the ticket
    /// emerges through. `working` glows the slot's print-head bar.
    private var printerHousing: some View {
        let working = !feedComplete && printProgress > 0
        return ZStack(alignment: .bottom) {
            // Machine body
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(
                    LinearGradient(colors: [Theme.surfaceElevated, Theme.surfaceDark],
                                   startPoint: .top, endPoint: .bottom)
                )
                .frame(height: 58)
                .overlay(alignment: .top) {
                    HStack(spacing: 8) {
                        // Print-status light: accent while feeding, calm when done.
                        Circle()
                            .fill(feedComplete ? Color(hex: "6FCF97") : Theme.accent)
                            .frame(width: 7, height: 7)
                            .shadow(color: (feedComplete ? Color(hex: "6FCF97") : Theme.accent)
                                .opacity(working ? 0.9 : 0.4),
                                    radius: working ? 5 : 2)
                            .opacity(working ? 1 : 0.85)
                        Text(feedComplete ? "READY" : "PRINTING")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .kerning(1.2)
                            .foregroundStyle(.white.opacity(0.35))
                        Spacer()
                        // Paper-feed vents.
                        HStack(spacing: 3) {
                            ForEach(0..<3, id: \.self) { _ in
                                Capsule().fill(.white.opacity(0.09)).frame(width: 16, height: 3)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 11)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)

            // Recessed slot along the bottom lip — the mouth the pass feeds from.
            Capsule()
                .fill(.black.opacity(0.7))
                .frame(height: 6)
                .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
                .overlay(
                    Capsule()
                        .fill(Theme.accent.opacity(working ? 0.85 : 0))
                        .frame(height: 3)
                        .blur(radius: 2)
                        .padding(.horizontal, 40)
                        .animation(.smooth(duration: 0.5), value: feedComplete)
                )
                .padding(.horizontal, 6)
                .offset(y: 4)
        }
        .padding(.horizontal, 22)
        .accessibilityHidden(true)
    }

    /// Discrete line feeds — advance, settle, advance — driven by
    /// `feedSchedule`, with a haptic tick per line and the printer audio
    /// running off the identical timing.
    private func startPrinting() {
        guard !printed else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            let schedule = Self.feedSchedule
            CabinAudioEngine.shared.playPrinter(feedSchedule: schedule)
            for (line, gap) in schedule.enumerated() {
                // No bounce: a feed roller only ever turns forward, and any
                // overshoot here read as the paper sliding back into the slot.
                withAnimation(.easeOut(duration: 0.12)) {
                    printProgress = CGFloat(line + 1) / CGFloat(schedule.count)
                }
                Haptics.softTick()
                try? await Task.sleep(for: .milliseconds(Int(gap * 1000)))
            }
            // A beat with the paper fully out and the light green before the
            // housing withdraws, so the release reads as a step, not a cut.
            feedComplete = true
            try? await Task.sleep(for: .milliseconds(260))
            printed = true
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

    /// Main ticket body with its own fill/shadow. The bottom edge stays a clean
    /// cut after the rip — ragged paper teeth read as debris at this size.
    private var bodyPiece: some View {
        VStack(spacing: 0) {
            passBody
            perforation
        }
        .background(Color(.systemBackground))
        .clipShape(PassBodyPaper())
        .compositingGroup()
        .shadow(color: .black.opacity(ripped ? 0.35 : 0.45), radius: ripped ? 16 : 22, y: 12)
        // Losing the stub takes weight off the bottom of the sheet, so the body
        // settles a little as it goes rather than hanging in mid-air.
        .offset(y: ripped ? 12 : 0)
        .animation(.spring(duration: 0.45, bounce: 0.18), value: ripped)
    }

    /// Classic paper ticket: ink on white, no colored chrome.
    private var passBody: some View {
        VStack(spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    FieldLabel("Boarding pass")
                    HStack(spacing: 6) {
                        Text(carrierName)
                            .font(.system(size: 15, weight: .heavy))
                            .kerning(2)
                        if session.passStyle == .priority {
                            Text("PRIORITY")
                                .font(.system(size: 8, weight: .black))
                                .kerning(1.2)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Self.priorityRed, in: RoundedRectangle(cornerRadius: 3))
                                .accessibilityLabel("Priority")
                        }
                    }
                }
                Spacer()
                Text(leg.flightNumber)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.itinerary.origin.code)
                        .font(.system(size: 38, weight: .heavy, design: .monospaced))
                    Text(session.itinerary.origin.city)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer()
                VStack(spacing: 3) {
                    Image(systemName: "airplane")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.accent)
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }

            // spacing: 0 let neighbouring columns touch. At the default text
            // size "FOCUSED FLYER" ends 2pt before "MAIN" starts; at
            // accessibilityLarge they render as the single word
            // "FOCUSED FLYERMAIN" (QA/e2e-ax-06-boarding-pass.png).
            // Only fields the session actually holds. A passenger name, a
            // gate and a boarding call would be invented, and an invented
            // field is the kind of detail that reads as a prop.
            purposeRow

            HStack(spacing: 12) {
                passField("Class", cabinClass)
                passField("Focus", session.itinerary.totalFocusDuration.shortDurationText)
            }
        }
        .padding(22)
        .overlay(alignment: .leading) {
            if session.passStyle == .livery {
                LinearGradient(colors: carrier.livery, startPoint: .top, endPoint: .bottom)
                    .frame(width: 6)
                    .accessibilityHidden(true)
            }
        }
        .padding(.bottom, ripped ? 4 : 0)
    }

    static let priorityRed = Color(hex: "D2232A")

    /// PURPOSE OF TRIP, written by hand on the printed pass. Editable until
    /// the pass is torn; empty is fine and simply skips the loop at landing.
    private var purposeRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            FieldLabel("Purpose of trip")
            TextField("What will be done when you land?", text: $purpose)
                .font(.custom("Noteworthy-Bold", size: 18, relativeTo: .body))
                .foregroundStyle(Theme.passportInk)
                .tint(Theme.accent)
                .focused($purposeFocused)
                .submitLabel(.done)
                .onSubmit { purposeFocused = false }
                .disabled(!printed || ripped)
                .accessibilityIdentifier("boarding-pass-purpose")
                .accessibilityLabel("Purpose of trip")
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One-tap chips for purposes you have flown with before, unfinished
    /// ones you chose to bring along first (Session's past intentions,
    /// Super Productivity's suggestions shown before you search).
    private var recentPurposesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(recentPurposes, id: \.self) { item in
                    Button {
                        Haptics.tap()
                        purpose = item
                        purposeFocused = false
                    } label: {
                        Label(item, systemImage: carried.contains(item.lowercased())
                              ? "arrow.uturn.forward" : "plus")
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.white.opacity(0.12), in: Capsule())
                    }
                    .accessibilityLabel(carried.contains(item.lowercased())
                                        ? "Bring along: \(item)" : "Reuse: \(item)")
                }
            }
            .padding(.horizontal, 28)
        }
        .accessibilityLabel("Recent purposes")
    }

    /// Pass stock. Standard is free; priority is earned at Gold and livery
    /// at Platinum, and Voyage First opens both early. Tapping a locked one
    /// opens the paywall (trigger 3 in SPEC.md, moved here from the bag tags).
    private var stylePicker: some View {
        HStack(spacing: 8) {
            ForEach(PassStyle.allCases) { style in
                let locked = !style.isUnlocked(tier: session.tier, isFirstMember: membership.isFirstClass)
                let chosen = session.passStyle == style
                Button {
                    if locked {
                        _ = membership.requireFirstClass(from: "pass-style-\(style.rawValue)", paywall: $showsPaywall)
                        return
                    }
                    Haptics.tap()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { session.passStyle = style }
                } label: {
                    HStack(spacing: 4) {
                        if locked { Image(systemName: "lock.fill").font(.system(size: 9, weight: .bold)) }
                        Text(style.title)
                        if locked {
                            Text(style.earnedAt.rawValue)
                                .font(.system(size: 9, weight: .heavy))
                                .opacity(0.7)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(chosen ? .white : .white.opacity(locked ? 0.45 : 0.75))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(chosen ? Theme.accent : .white.opacity(0.08), in: Capsule())
                }
                .accessibilityIdentifier("pass-style-\(style.rawValue)")
                .accessibilityLabel(locked ? "\(style.title) pass, free at \(style.earnedAt.rawValue) or with Voyage First" : "\(style.title) pass")
            }
        }
        .frame(maxWidth: .infinity)
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

    /// Height of the scored strip at the bottom of the body. The seam with the
    /// stub is this strip's bottom edge, and everything below — dashes, notches,
    /// the opening cut — is drawn against it, because paper tears *along* its
    /// perforation, not somewhere near it.
    private let perforationStripHeight: CGFloat = 18

    /// The tear line itself: a dashed score sitting on the seam, punched at both
    /// ends by notches. Slide a finger along it and the seam opens behind your
    /// fingertip. After the rip the dashes are gone with the stub and the body
    /// keeps the two bitten half-notches, exactly like a torn ticket.
    private var perforation: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let seamY = geo.size.height
            ZStack(alignment: .topLeading) {
                if !ripped {
                    let cutX = w * min(1, cutProgress)
                    // Dashes ride just above the seam so the full stroke stays on
                    // the paper — the line you see is the line it parts along.
                    // The whole seam is gone the instant the stub tears off:
                    // no fade, no notch left behind on the moving body. Dashes
                    // behind the fingertip are gone too: that stretch is cut.
                    // The uncut stretch only, with the dash phase pinned to the
                    // full line so the remaining dashes stay put as it shortens.
                    let start = cutFromTrailing ? 14 : max(14, cutX)
                    let end = cutFromTrailing ? min(w - 14, w - cutX) : w - 14
                    if end > start {
                        Path { path in
                            path.move(to: CGPoint(x: start, y: seamY - 2))
                            path.addLine(to: CGPoint(x: end, y: seamY - 2))
                        }
                        .stroke(Theme.boardingBackdrop,
                                style: StrokeStyle(lineWidth: 3, lineCap: .butt, dash: [9, 6],
                                                   dashPhase: start - 14))
                        .transition(.identity)
                    }

                    // Punched at both ends of the score, centered on the seam: the
                    // body clips the top half, the stub carries the bottom half.
                    notch.position(x: 0, y: seamY).transition(.identity)
                    notch.position(x: w, y: seamY).transition(.identity)
                }
            }
            // Tall, generous hit area so the horizontal slide is easy to catch.
            .contentShape(Rectangle().inset(by: -16))
            .gesture(cutGesture())
        }
        .frame(height: perforationStripHeight)
        .background(Color(.systemBackground))
        .accessibilityLabel("Tear line. Slide across to tear.")
    }

    private var notch: some View {
        Circle()
            .fill(Theme.boardingBackdrop)
            .frame(width: 20, height: 20)
    }

    /// Swipe distance to run the cut fully across: most of the pass's width,
    /// so the opening in the seam stays under the fingertip.
    private var cutSpan: CGFloat { max(200, passWidth * 0.82) }

    /// Swipe sideways — anywhere along the perforation *or* across the stub tab
    /// below it — to run the cut: the seam parts as you go, ratcheting one
    /// perforation at a time, and rips once the cut reaches the far edge.
    private func cutGesture() -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard printed, !ripped else { return }
                // Sideways travel parts the paper; ignore a mostly-vertical drag.
                guard abs(value.translation.width) > abs(value.translation.height) * 0.6 else { return }
                if cutProgress == 0 { cutFromTrailing = value.translation.width < 0 }
                let travel = cutFromTrailing ? -value.translation.width : value.translation.width
                let p = max(0, travel) / cutSpan
                // Monotonic: a wiggle can't un-cut what you've already parted.
                cutProgress = max(cutProgress, min(1, p))
                let step = Int(cutProgress / 0.09)
                if step > lastCutStep {
                    lastCutStep = step
                    CabinAudioEngine.shared.playTearTick()
                    Haptics.ratchet()
                }
                if cutProgress > 0.92 { rip() }
            }
            .onEnded { _ in
                guard !ripped else { return }
                if cutProgress < 0.92 {
                    // Cut wasn't run all the way across — the paper closes back up.
                    withAnimation(.spring(duration: 0.4)) { cutProgress = 0 }
                    lastCutStep = 0
                }
            }
    }

    // MARK: Stub + tear gesture

    private var stubPiece: some View {
        // As the cut runs across, the stub loosens a touch; the real motion is
        // the fly-off on rip. It never tracks the finger vertically.
        let progress = min(1, max(0, cutProgress))
        // The cut side drops away from the seam while the uncut side holds it,
        // so the stub swings on the attached corner and a wedge of backdrop
        // opens behind the finger.
        let hinge: UnitPoint = cutFromTrailing ? .topLeading : .topTrailing
        let sign: Double = cutFromTrailing ? -1 : 1
        let dragY = ripped ? 420 : progress * 3
        let angle = sign * (ripped ? 9.0 : Double(progress * 4.5))
        let curl = ripped ? 18.0 : Double(progress * 6)

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
            // The other half of each punched notch. At rest these sit exactly on
            // the body's own half, completing one circle across the seam; once
            // the stub drops they travel with it, as the paper actually would.
            .overlay {
                GeometryReader { geo in
                    notch.position(x: 0, y: 0)
                    notch.position(x: geo.size.width, y: 0)
                }
                .allowsHitTesting(false)
            }
            .compositingGroup()
            .shadow(
                color: .black.opacity(progress > 0 || ripped ? 0.28 + 0.22 * progress : 0.08),
                radius: progress > 0 || ripped ? 10 + 8 * progress : 2,
                y: progress > 0 || ripped ? 6 + 6 * progress : 1
            )
            .contentShape(Rectangle())
            .rotation3DEffect(.degrees(curl), axis: (x: 1, y: 0, z: 0),
                              anchor: .top, perspective: 0.55)
            .rotationEffect(.degrees(angle), anchor: hinge)
            .offset(y: dragY)
            .animation(ripped ? .easeIn(duration: 0.6) : nil, value: ripped)
            // Opaque for the fall, gone only once it is well clear of the
            // pass. Fading during the fall showed the stub as grey paper
            // against the navy backdrop.
            .opacity(ripped ? 0 : 1)
            .animation(ripped ? .easeIn(duration: 0.15).delay(0.45) : nil, value: ripped)
            .gesture(cutGesture())
            .accessibilityHidden(ripped)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("boarding-pass-stub")
            .accessibilityLabel("Boarding pass stub, seat \(session.seat)")
            .accessibilityHint("Slide across to tear and board")
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

    private func rip() {
        guard !ripped else { return }
        purposeFocused = false
        session.intentions = trimmedPurpose.isEmpty ? [] : [trimmedPurpose]
        ripped = true
        Haptics.rip()
        CabinAudioEngine.shared.playRip()
        Task { @MainActor in
            // Let the stub clear the screen and the torn pass settle before
            // departing; also gives the rip one-shot time to finish before
            // depart starts ambience. At 430 ms the stub was gone in three
            // frames and the curtain cut in before the eye had registered the
            // tear (QA/video/tear-raw.mp4, 35.0 to 35.6 s).
            try? await Task.sleep(for: .milliseconds(800))
            onBoarded()
        }
    }
}

// MARK: - Paper shapes

/// Main pass silhouette: rounded top, flat bottom where the stub separates.
private struct PassBodyPaper: Shape {
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 22
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
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

extension Carrier {
    /// Livery colours for the fictional carriers, used by the livery pass
    /// stock. Chosen to be none of the real US legacy carriers' marks
    /// (SPEC.md (e)).
    var livery: [Color] {
        switch self {
        case .harborline: return [Color(hex: "0F6E6E"), Color(hex: "13A3A3")]
        case .ridgeway: return [Color(hex: "5B3A8C"), Color(hex: "8C5BD6")]
        case .voyageAir: return [Color(hex: "1D2F5C"), Color(hex: "5E8FFF")]
        case .baywater: return [Color(hex: "0E4D92"), Color(hex: "2E86C1")]
        case .northline: return [Color(hex: "2F4F3A"), Color(hex: "4E8A5F")]
        case .lantern: return [Color(hex: "B3541E"), Color(hex: "E3893B")]
        }
    }
}
