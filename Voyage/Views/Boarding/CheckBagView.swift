import SwiftUI
import SwiftData

/// Optional intentions step: "check a bag" with up to three things you're
/// working on this flight. You write each one, and its long, skinny airline
/// tag appears beside the others, one tag per task. No kiosk, no printer and
/// no stub to peel: writing is the whole ritual, and one tap on "Check N
/// bags" sends the tags off down the belt (Pat, 2026-09-30: "keep it simple
/// and satisfying, just write, no need to tear"). Fully skippable; recent
/// bags come back as one-tap chips.
///
/// The tag is `TaskBagTagView`, laid out on IATA Resolution 740 stock (see
/// its doc comment for the sources).
struct CheckBagView: View {
    @Bindable var session: FlightSession
    let onContinue: () -> Void

    @State private var items = ["", "", ""]
    @FocusState private var focusedIndex: Int?
    @Query(sort: \LogbookEntry.date, order: .reverse) private var entries: [LogbookEntry]
    @State private var focus = FocusIntegration.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Send-off.
    @State private var checked = false
    @State private var sentOff = false
    @Query(sort: \LogbookEntry.date) private var allEntries: [LogbookEntry]

    // One tag per task: written as each line is entered, hung below.
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

    /// The written tags, one per filled line, in slot order.
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
            ScrollViewReader { proxy in
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

                    writingCard
                        .padding(.horizontal, 20)

                    tagRack
                        .padding(.top, 6)
                        .id("tag-rack")

                    if membership.isConfigured && !taskTags.isEmpty {
                        stylePicker
                            .padding(.top, 12)
                    }

                    if !recentBags.isEmpty {
                        recentBagsRow
                            .padding(.top, 16)
                    }

                    // Only the one reminder that asks for an action: Focus
                    // is set up for Voyage but not on. "Focus is on" and the
                    // first-time setup line live in Settings → Flight Focus.
                    if focus.filterConfigured && !focus.systemFocusEnabled {
                        focusNote
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                    }
                }
            }
            .onChange(of: printedSlots) { old, new in
                // A new tag hangs below the fold: bring it up above the
                // button, so what was just written is in view.
                guard new.count > old.count else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    withAnimation(.smooth(duration: 0.6)) { proxy.scrollTo("tag-rack", anchor: .bottom) }
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
                .disabled(checked)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
        .onAppear {
            if items.allSatisfy(\.isEmpty), !session.intentions.isEmpty {
                // Stepping back from the pass keeps what was written.
                for (i, intention) in session.intentions.prefix(3).enumerated() { items[i] = intention }
            }
            printedSlots = filledSlots
            Task {
                await focus.refresh()
            }
        }
        .onChange(of: focusedIndex) { old, _ in
            // Leaving a line writes its tag, whether by return or by tapping
            // the next line.
            if let old { writeTaskTag(old) }
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
            Button("Save") {
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

    /// Hangs one task's tag on the rack: it springs in with one soft tick.
    private func writeTaskTag(_ slot: Int) {
        guard !items[slot].trimmingCharacters(in: .whitespaces).isEmpty,
              !printedSlots.contains(slot) else { return }
        Haptics.softTick()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
            printedSlots.append(slot)
        }
    }

    /// Standard stock is free; priority is earned at Gold and livery at
    /// Platinum, and Voyage First opens both early. Tapping a locked one
    /// opens the paywall (trigger 3 in SPEC.md).
    private var stylePicker: some View {
        HStack(spacing: 8) {
            ForEach(BagTagStyle.allCases) { style in
                // Earned by flying (priority at Gold, livery at Platinum) or
                // opened early by Voyage First.
                let locked = !style.isUnlocked(tier: LogbookStats.tier(allEntries),
                                               isFirstMember: membership.isFirstClass)
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
                        if locked {
                            Text(style.earnedAt.rawValue)
                                .font(.system(size: 9, weight: .heavy))
                                .opacity(0.7)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(chosen ? .white : Theme.seatMapInk.opacity(locked ? 0.45 : 0.8))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(chosen ? Theme.accent : Theme.seatMapInk.opacity(0.06), in: Capsule())
                }
                .accessibilityIdentifier("bag-tag-style-\(style.rawValue)")
                .accessibilityLabel(locked ? "\(style.title) tag, free at \(style.earnedAt.rawValue) or with Voyage First" : "\(style.title) tag")
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Writing card

    /// Three lines on a plain white card, one per bag.
    private var writingCard: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { index in
                bagField(index)
                if index < 2 {
                    Rectangle().fill(Theme.seatMapInk.opacity(0.08)).frame(height: 1)
                        .padding(.leading, 44)
                }
            }
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .environment(\.colorScheme, .light)
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }

    /// One line per bag: its number, the field, and a tag glyph once its tag
    /// is written.
    private func bagField(_ index: Int) -> some View {
        let isPrinted = printedSlots.contains(index)
            && !items[index].trimmingCharacters(in: .whitespaces).isEmpty
        return HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(isPrinted ? .white : Theme.seatMapInk.opacity(0.5))
                .frame(width: 22, height: 22)
                .background(isPrinted ? Theme.accent : Theme.seatMapInk.opacity(0.07), in: Circle())
            // The placeholder is load-bearing: the UI tests find the fields
            // by it.
            TextField("Bag \(index + 1), e.g. Review chapter 4", text: $items[index])
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.seatMapInk)
                .tint(Theme.accent)
                .focused($focusedIndex, equals: index)
                .submitLabel(.done)
                .onSubmit {
                    // Return writes the tag and drops the keyboard, so the
                    // tag is seen appearing rather than under the keys.
                    writeTaskTag(index)
                    focusedIndex = nil
                }
            if isPrinted {
                Image(systemName: "tag.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 46)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isPrinted)
    }

    // MARK: Tag rack

    private static let tagWidth: CGFloat = 104

    /// The written tags hanging side by side, one per task. Each springs in
    /// as its line is written; checking the bags drops them onto the belt,
    /// one after another.
    @ViewBuilder
    private var tagRack: some View {
        let tags = taskTags
        // Empty until the first line is written: the tag appearing is the
        // explanation, so there is no placeholder saying one will.
        if !tags.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                ForEach(tags) { taskTag in
                    tagColumn(taskTag)
                        .transition(.asymmetric(
                            insertion: reduceMotion ? .opacity
                                : .scale(scale: 0.9, anchor: .top).combined(with: .opacity),
                            removal: .scale(scale: 0.85).combined(with: .opacity)))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: tags.map(\.id))
            .onTapGesture { focusedIndex = nil }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("task-tag-rack")
        }
    }

    private func tagColumn(_ taskTag: TaskBagTag) -> some View {
        let order = Double(taskTag.index)
        return TaskBagTagView(tag: taskTag, carrier: carrier, content: tag, showsStub: false,
                              width: Self.tagWidth) {
            codeDraft = taskTag.code
            editingSlot = filledSlots.filter { printedSlots.contains($0) }[taskTag.index]
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
        .frame(width: Self.tagWidth)
        // Hung, not stacked: a hair of swing, alternating, like tags on a rail.
        .rotationEffect(.degrees(sentOff ? 5 : (taskTag.index.isMultiple(of: 2) ? -0.8 : 0.8)), anchor: .top)
        .offset(y: sentOff ? 1_000 : 0)
        .animation(sentOff ? .easeIn(duration: 0.5 * Self.sendOffTimeScale)
                    .delay(0.09 * order * Self.sendOffTimeScale) : .spring(response: 0.6, dampingFraction: 0.6),
                   value: sentOff)
    }

    /// Scan, tags onto the belt, then the boarding pass.
    private func checkBags() {
        guard !checked else { return }
        checked = true
        focusedIndex = nil
        let slots = filledSlots
        session.intentions = slots.map { items[$0].trimmingCharacters(in: .whitespaces) }
        session.tagCodes = TaskCode.codes(for: session.intentions,
                                          existing: slots.map { codeOverrides[$0] ?? "" })
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { printedSlots = slots }
        CabinAudioEngine.shared.playScanBeep()
        Haptics.success()
        sentOff = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(Double(reduceMotion ? 150 : 560) * Self.sendOffTimeScale)))
            onContinue()
        }
    }

    /// `-VoyageSlowPeel` (DEBUG only; the name predates the peel's removal)
    /// runs the send-off eight times slower, so `BagTagScreenshotUITests` can
    /// photograph it: XCUITest screenshots arrive later than the sequence.
    static let sendOffTimeScale: Double = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-VoyageSlowPeel") ? 8 : 1
        #else
        1
        #endif
    }()

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
                        writeTaskTag(slot)
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
