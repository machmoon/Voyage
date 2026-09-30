import SwiftUI
import SwiftData

/// Optional intentions step: "check a bag" with up to three things you're
/// working on this flight. A bag-drop kiosk prints a thermal airline tag for
/// the booking, and the traveler writes the contents on it by hand. Checking
/// the bag peels off the claim check, the way an agent hands it across the
/// counter, and the tag rides the belt away. Fully skippable; recent bags come
/// back as one-tap chips so regulars never retype them.
///
/// History: this step used to draw three c. 1965 paper luggage labels and
/// rejected the thermal IATA strip, whose proportion is one enormous airport
/// code. The tag below keeps the strip and gives the student's words their own
/// handwritten block on it instead. Format sources are cited in `BagTag.swift`
/// and `BagTagView.swift`.
struct CheckBagView: View {
    @Bindable var session: FlightSession
    let onContinue: () -> Void

    @State private var items = ["", "", ""]
    @FocusState private var focusedIndex: Int?
    @Query(sort: \LogbookEntry.date, order: .reverse) private var entries: [LogbookEntry]
    @State private var focus = FocusIntegration.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Print feed, as on the boarding pass.
    @State private var printProgress: CGFloat = 0
    @State private var tagHeight: CGFloat = 0
    @State private var feedComplete = false
    @State private var printed = false

    // Peel and send-off.
    @State private var peelProgress: CGFloat = 0
    @State private var lastPeelStep = 0
    @State private var peeled = false
    @State private var sentOff = false
    @State private var stubWidth: CGFloat = 0

    // One tag per task: printed as each line is entered, fanned below.
    @State private var printedSlots: [Int] = []
    @State private var codeOverrides: [Int: String] = [:]
    @State private var editingSlot: Int?
    @State private var codeDraft = ""
    @State private var membership = Membership.shared
    @State private var showsPaywall = false

    private var tag: BagTagContent {
        BagTagContent(itinerary: session.itinerary, seat: session.seat, bookedAt: session.bookedAt)
    }

    private var packedCount: Int {
        items.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    /// Bags left on the carousel last time. They ride this flight, first.
    private var mishandled: Set<String> {
        Set(MishandledBags.pending(in: Array(entries)).map { $0.lowercased() })
    }

    private var filledSlots: [Int] {
        items.indices.filter { !items[$0].trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// The printed tags, one per filled line, in slot order.
    private var taskTags: [TaskBagTag] {
        let slots = filledSlots.filter { printedSlots.contains($0) }
        let titles = slots.map { items[$0].trimmingCharacters(in: .whitespaces) }
        return TaskBagTag.tags(titles: titles,
                               codes: slots.map { codeOverrides[$0] ?? "" },
                               base: tag.plate,
                               style: session.bagTagStyle)
    }

    private var carrier: Carrier {
        Carrier(rawValue: String(session.itinerary.legs[0].flightNumber.prefix { !$0.isWhitespace })) ?? .voyageAir
    }

    /// Up to six distinct intentions from recent flights, mishandled bags
    /// first, then newest first, excluding ones already packed this time.
    private var recentBags: [String] {
        var seen = Set(items.map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        var result: [String] = []
        for bag in MishandledBags.pending(in: Array(entries)) where !seen.contains(bag.lowercased()) {
            seen.insert(bag.lowercased())
            result.append(bag)
            if result.count == 6 { return result }
        }
        for entry in entries.prefix(20) {
            for intention in entry.intentions {
                let key = intention.lowercased()
                if !seen.contains(key) {
                    seen.insert(key)
                    result.append(intention)
                    if result.count == 6 { return result }
                }
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Scrolls so the tag, chips and Focus note all stay reachable when
            // the keyboard is up or text is large.
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 4) {
                        Text("Check a bag")
                            .font(.title2.bold())
                            .foregroundStyle(Theme.seatMapInk)
                        Text("Write up to three things to finish on this flight.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.seatMapInk.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 14)

                    printerAndTag

                    if !taskTags.isEmpty {
                        TaskTagFan(tags: taskTags, carrier: carrier) { tag in
                            let slot = filledSlots.filter { printedSlots.contains($0) }[tag.index]
                            codeDraft = tag.code
                            editingSlot = slot
                        }
                        .padding(.top, 18)
                        .opacity(sentOff ? 0 : 1)
                        .offset(y: sentOff ? 400 : 0)
                        .animation(.easeIn(duration: 0.45), value: sentOff)
                    }

                    if membership.isConfigured && !taskTags.isEmpty {
                        stylePicker
                            .padding(.top, 12)
                    }

                    if !recentBags.isEmpty {
                        recentBagsRow
                            .padding(.top, 16)
                    }

                    focusNote
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .contentMargins(.bottom, 16, for: .scrollContent)
            // At large text sizes the list scrolls under the footer. Fading
            // its last 28pt says "there is more below" instead of looking like
            // the footer cut it off (QA/e2e-ax-05-checkbag.png).
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 28)
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button {
                    if packedCount > 0 {
                        checkBags()
                    } else {
                        session.intentions = []
                        Haptics.success()
                        CabinAudioEngine.shared.playScanBeep()
                        onContinue()
                    }
                } label: {
                    // "Skip for now" and "Check N bags" are load-bearing: the
                    // UI tests tap them by label. Do not rename them without
                    // updating VoyageUITests.
                    Text(packedCount > 0
                         ? "Check \(packedCount) \(packedCount == 1 ? "bag" : "bags")"
                         : "Skip for now")
                }
                .buttonStyle(VoyageAccentButtonStyle())
                .disabled(peeled)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
        .onAppear {
            if items.allSatisfy(\.isEmpty), !session.intentions.isEmpty {
                // Stepping back from the pass keeps what was written.
                for (i, intention) in session.intentions.prefix(3).enumerated() { items[i] = intention }
            }
            startPrinting()
            printedSlots = filledSlots
            Task {
                await focus.refresh()
            }
        }
        .onChange(of: items) { _, _ in
            // A cleared line takes its tag off the fan.
            printedSlots.removeAll { !filledSlots.contains($0) }
        }
        .alert("Tag code", isPresented: Binding(get: { editingSlot != nil },
                                                set: { if !$0 { editingSlot = nil } })) {
            TextField("Three letters", text: $codeDraft)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("Print") {
                if let slot = editingSlot, let code = TaskCode.sanitized(codeDraft) {
                    withAnimation(.snappy) { codeOverrides[slot] = code }
                    Haptics.softTick()
                }
                editingSlot = nil
            }
            Button("Cancel", role: .cancel) { editingSlot = nil }
        } message: {
            Text("Three letters, like an airport code.")
        }
        .firstClassPaywall(isPresented: $showsPaywall)
    }

    /// Prints one task's tag onto the fan: a short feed and a tick per line.
    private func printTaskTag(_ slot: Int) {
        guard !items[slot].trimmingCharacters(in: .whitespaces).isEmpty,
              !printedSlots.contains(slot) else { return }
        CabinAudioEngine.shared.playPrinter(feedSchedule: [0.07, 0.07, 0.09])
        Haptics.softTick()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.68)) {
            printedSlots.append(slot)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            Haptics.tap()
        }
    }

    /// Standard stock is free; priority and livery are Voyage First, and
    /// tapping a locked one opens the paywall (trigger 3 in SPEC.md).
    private var stylePicker: some View {
        HStack(spacing: 8) {
            ForEach(BagTagStyle.allCases) { style in
                let locked = style.requiresVoyageFirst && !membership.isFirstClass
                let chosen = session.bagTagStyle == style
                Button {
                    if locked {
                        _ = membership.requireFirstClass(from: "bag-tag-\(style.rawValue)", paywall: $showsPaywall)
                        return
                    }
                    Haptics.tap()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { session.bagTagStyle = style }
                } label: {
                    HStack(spacing: 4) {
                        if locked { Image(systemName: "lock.fill").font(.system(size: 9, weight: .bold)) }
                        Text(style.title)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(chosen ? .white : Theme.seatMapInk.opacity(locked ? 0.45 : 0.8))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(chosen ? Theme.accent : Theme.seatMapInk.opacity(0.06), in: Capsule())
                }
                .accessibilityIdentifier("bag-tag-style-\(style.rawValue)")
                .accessibilityLabel(locked ? "\(style.title) tag, Voyage First" : "\(style.title) tag")
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Printer and tag

    private var printerAndTag: some View {
        VStack(spacing: 0) {
            if !printed {
                BagDropPrinterHousing(working: !feedComplete && printProgress > 0,
                                      feedComplete: feedComplete)
                    .frame(maxWidth: 340)
                    .padding(.horizontal, 20)
                    .zIndex(2)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            tagStrip
                .frame(maxWidth: 300)
                .padding(.horizontal, 28)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tagHeight = $0 }
                // Feeds out of the slot: offset up by its own height, masked
                // at the slot, the mask opening once it is out. The same one
                // identity trick as `BoardingPassView.passCard`.
                .offset(y: -tagHeight * (1 - printProgress))
                .opacity(tagHeight > 0 ? 1 : 0)
                .mask(alignment: .top) {
                    Rectangle()
                        .padding(.horizontal, -60)
                        .padding(.bottom, -900)
                        .padding(.top, printed ? -600 : 0)
                }
                .padding(.top, printed ? 0 : -7)
                // Onto the belt: the tag drops away once the stub is off.
                .offset(y: sentOff ? 900 : 0)
                .rotationEffect(.degrees(sentOff ? 4 : 0), anchor: .top)
                .animation(sentOff ? .easeIn(duration: 0.45 * Self.peelTimeScale) : nil, value: sentOff)
                .zIndex(1)
        }
        .animation(.smooth(duration: 0.5), value: printed)
    }

    private var tagStrip: some View {
        VStack(spacing: 0) {
            BagTagBody(content: tag, bagCount: max(packedCount, 1)) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(0..<3, id: \.self) { index in
                        bagField(index)
                    }
                }
            }
            .background(Color(.systemBackground))
            .clipShape(BagTagPaper())
            .overlay(alignment: .bottom) { perforation }
            .compositingGroup()
            .shadow(color: .black.opacity(0.12), radius: 10, y: 5)

            claimStub
        }
        // Thermal stock is white paper in any appearance, like the pass.
        .environment(\.colorScheme, .light)
        .allowsHitTesting(!peeled)
    }

    /// The die-cut line between the tag and the claim check.
    private var perforation: some View {
        Line()
            .stroke(Color.primary.opacity(peeled ? 0 : 0.35),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .frame(height: 1)
            .padding(.horizontal, 6)
            .accessibilityHidden(true)
    }

    /// One handwritten line on the tag per bag.
    private func bagField(_ index: Int) -> some View {
        let filled = !items[index].trimmingCharacters(in: .whitespaces).isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            // The placeholder is load-bearing: MarketingCaptureUITests finds
            // the fields by it.
            TextField("Bag \(index + 1), e.g. Review chapter 4", text: $items[index])
                .font(.custom("Noteworthy-Bold", size: 17, relativeTo: .body))
                .foregroundStyle(Theme.accent)
                .tint(Theme.accent)
                .focused($focusedIndex, equals: index)
                .submitLabel(index < 2 ? .next : .done)
                .onSubmit {
                    printTaskTag(index)
                    focusedIndex = index < 2 ? index + 1 : nil
                }
                .padding(.top, 4)
            Rectangle()
                .fill(filled ? Theme.accent.opacity(0.7) : Color.primary.opacity(0.18))
                .frame(height: 1)
        }
    }

    // MARK: Claim check

    /// Peels from whichever edge the finger pulls toward, lifting on the
    /// opposite corner, with a ratchet tick every stretch of adhesive, like
    /// the pass's perforation.
    private var claimStub: some View {
        let progress = min(1, max(0, peelProgress))
        let peelAngle = peeled ? -14.0 : Double(progress * -8)
        return BagTagClaimStub(content: tag, peelable: packedCount > 0 && printed && !peeled)
            .background(Color(.systemBackground))
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { stubWidth = $0 }
            .compositingGroup()
            .shadow(color: .black.opacity(0.12 + 0.2 * progress), radius: 6 + 8 * progress, y: 3 + 5 * progress)
            .rotation3DEffect(.degrees(Double(progress) * 22 + (peeled ? 30 : 0)),
                              axis: (x: 0, y: 1, z: 0.2), anchor: .leading, perspective: 0.5)
            .rotationEffect(.degrees(peelAngle), anchor: .bottomLeading)
            .offset(x: peeled ? 260 : progress * 18, y: peeled ? -520 : -progress * 10)
            .animation(peeled ? .easeIn(duration: 0.5 * Self.peelTimeScale) : nil, value: peeled)
            // Opaque while it crosses the tag, gone only once it is clear,
            // as the pass's stub does (`BoardingPassView.stubPiece`): fading
            // in flight showed it as a ghost over the handwriting.
            .opacity(peeled ? 0 : 1)
            .animation(peeled ? .easeIn(duration: 0.12 * Self.peelTimeScale)
                        .delay(0.38 * Self.peelTimeScale) : nil, value: peeled)
            .contentShape(Rectangle())
            .gesture(peelGesture)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("bag-tag-claim-stub")
            .accessibilityLabel("Claim check, tag number \(tag.plate.spoken)")
            .accessibilityHint(packedCount > 0 ? "Slide across to peel it off and check your bags" : "")
            .accessibilityAction(named: Text("Peel claim check")) {
                guard packedCount > 0 else { return }
                checkBags()
            }
            .accessibilityHidden(peeled)
    }

    private var peelSpan: CGFloat { max(160, stubWidth * 0.7) }

    private var peelGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard printed, !peeled, packedCount > 0 else { return }
                guard abs(value.translation.width) > abs(value.translation.height) * 0.6 else { return }
                let p = max(0, value.translation.width) / peelSpan
                peelProgress = max(peelProgress, min(1, p))
                let step = Int(peelProgress / 0.12)
                if step > lastPeelStep {
                    lastPeelStep = step
                    CabinAudioEngine.shared.playTearTick()
                    Haptics.ratchet()
                }
                if peelProgress > 0.9 { checkBags() }
            }
            .onEnded { _ in
                guard !peeled else { return }
                // Not pulled far enough: the adhesive holds and it lies back down.
                withAnimation(.spring(duration: 0.4)) { peelProgress = 0 }
                lastPeelStep = 0
            }
    }

    /// Stub off, scan, tag onto the belt, then the boarding pass.
    private func checkBags() {
        guard !peeled else { return }
        focusedIndex = nil
        let slots = filledSlots
        session.intentions = slots.map { items[$0].trimmingCharacters(in: .whitespaces) }
        session.tagCodes = TaskCode.codes(for: session.intentions,
                                          existing: slots.map { codeOverrides[$0] ?? "" })
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { printedSlots = slots }
        peeled = true
        Haptics.rip()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(Double(reduceMotion ? 100 : 380) * Self.peelTimeScale)))
            CabinAudioEngine.shared.playScanBeep()
            Haptics.success()
            sentOff = true
            try? await Task.sleep(for: .milliseconds(Int(Double(reduceMotion ? 150 : 480) * Self.peelTimeScale)))
            onContinue()
        }
    }

    /// `-VoyageSlowPeel` (DEBUG only) runs the peel and send-off eight times
    /// slower, so `BagTagScreenshotUITests` can photograph them: XCUITest
    /// screenshots arrive later than the whole 0.9 s sequence.
    static let peelTimeScale: Double = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-VoyageSlowPeel") ? 8 : 1
        #else
        1
        #endif
    }()

    // MARK: Printing

    /// Gaps between line feeds, irregular like the pass's gate printer.
    static let feedSchedule: [Double] = [0.16, 0.12, 0.12, 0.22, 0.12, 0.14, 0.2]

    private func startPrinting() {
        guard !printed else { return }
        if reduceMotion {
            printProgress = 1
            feedComplete = true
            printed = true
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            let schedule = Self.feedSchedule
            CabinAudioEngine.shared.playPrinter(feedSchedule: schedule)
            for (line, gap) in schedule.enumerated() {
                withAnimation(.easeOut(duration: 0.12)) {
                    printProgress = CGFloat(line + 1) / CGFloat(schedule.count)
                }
                Haptics.softTick()
                try? await Task.sleep(for: .milliseconds(Int(gap * 1000)))
            }
            feedComplete = true
            try? await Task.sleep(for: .milliseconds(220))
            printed = true
        }
    }

    // MARK: Chips and Focus

    private var focusNote: some View {
        HStack(spacing: 8) {
            Image(systemName: focus.boardingStatusSymbol)
                .voyageFont(11, weight: .bold)
                .foregroundStyle(Theme.accent)
            Text(focus.boardingStatusText)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.seatMapInk.opacity(0.65))
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.seatMapInk.opacity(0.05), in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
    }

    /// One-tap chips for bags you've flown with before.
    private var recentBagsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(recentBags, id: \.self) { bag in
                    Button {
                        guard let slot = items.firstIndex(where: {
                            $0.trimmingCharacters(in: .whitespaces).isEmpty
                        }) else { return }
                        Haptics.tap()
                        items[slot] = bag
                        printTaskTag(slot)
                    } label: {
                        Label(bag, systemImage: mishandled.contains(bag.lowercased())
                              ? "exclamationmark.arrow.triangle.2.circlepath" : "plus")
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Theme.accent.opacity(0.12), in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .accessibilityLabel("Recent bags")
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
