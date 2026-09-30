import Foundation

// MARK: - Interleaved 2 of 5

/// Interleaved 2 of 5 (ITF), the symbology every airline bag tag carries its
/// license plate in (IATA EBT Implementation Guide 1.2, §2.5: "an interleaved
/// 2 of 5 barcode containing the 10-digit License Plate Number", citing
/// Resolution 740).
///
/// The encoder follows ZXing's `ITFWriter`
/// (github.com/zxing/zxing, core/src/main/java/com/google/zxing/oned/ITFWriter.java):
/// the same digit table, a narrow-narrow-narrow-narrow start, a wide-narrow-
/// narrow stop, and digit pairs whose first digit is written in the five bars
/// and whose second is written in the five spaces between them. The one
/// deliberate difference is the output shape: ZXing returns a pixel-per-module
/// boolean array for a bitmap, and a SwiftUI Canvas wants runs, so this returns
/// one `Element` per bar or space with its width in narrow modules.
enum InterleavedTwoOfFive {
    /// One bar or one space, `modules` narrow units wide.
    struct Element: Equatable {
        let isBar: Bool
        let modules: Int
    }

    enum EncodingError: Error, Equatable {
        case notNumeric
        case oddLength
    }

    /// Narrow (false) or wide (true) for each of a digit's five elements.
    /// ZXing's `PATTERNS`, row for row.
    static let patterns: [[Bool]] = [
        [false, false, true, true, false],   // 0
        [true, false, false, false, true],   // 1
        [false, true, false, false, true],   // 2
        [true, true, false, false, false],   // 3
        [false, false, true, false, true],   // 4
        [true, false, true, false, false],   // 5
        [false, true, true, false, false],   // 6
        [false, false, false, true, true],   // 7
        [true, false, false, true, false],   // 8
        [false, true, false, true, false],   // 9
    ]

    /// Wide elements are three narrow modules, as in ZXing (`W = 3`). The
    /// symbology allows 2 to 3; three is the easiest to see on a phone.
    static let wideModules = 3

    /// Bars and spaces for `digits`, start and stop patterns included.
    /// The sequence always opens and closes on a bar.
    static func encode(_ digits: String) throws -> [Element] {
        let values = digits.compactMap(\.wholeNumberValue)
        guard values.count == digits.count, digits.allSatisfy(\.isASCII) else {
            throw EncodingError.notNumeric
        }
        guard values.count % 2 == 0 else { throw EncodingError.oddLength }

        var elements: [Element] = []
        func append(_ isBar: Bool, wide: Bool) {
            elements.append(Element(isBar: isBar, modules: wide ? wideModules : 1))
        }

        // Start: narrow bar, narrow space, narrow bar, narrow space.
        for i in 0..<4 { append(i % 2 == 0, wide: false) }

        for pair in stride(from: 0, to: values.count, by: 2) {
            let barDigit = patterns[values[pair]]
            let spaceDigit = patterns[values[pair + 1]]
            for j in 0..<5 {
                append(true, wide: barDigit[j])
                append(false, wide: spaceDigit[j])
            }
        }

        // Stop: wide bar, narrow space, narrow bar.
        append(true, wide: true)
        append(false, wide: false)
        append(true, wide: false)
        return elements
    }

    /// Total width in narrow modules, quiet zones excluded.
    static func moduleCount(_ elements: [Element]) -> Int {
        elements.reduce(0) { $0 + $1.modules }
    }
}

// MARK: - License plate

/// The ten-digit bag tag number, the "license plate" of IATA Resolution 751:
/// one leading digit, the three-digit Baggage Tag Issuer Code of the carrier
/// that accepted the bag (Resolution 769; IATA, "Interline Considerations on
/// Baggage Standards", 2020, §3), and a six-digit serial.
///
/// A real United tag reads "4016 582320": leading 4, issuer 016, serial 582320
/// (Wikimedia Commons, "United Airlines - bag tag UA926 San
/// Francisco-Frankfurt 2014-09-15.jpg"). It prints in that same 4 + 6 grouping
/// here.
struct BagTagLicensePlate: Hashable {
    let leadingDigit: Int
    let issuerCode: Int
    let serial: Int

    /// IATA's own BCBP example for this field leads with 0 ("014123456001",
    /// airtechzone.iata.org AIDM 22.1, Baggage Tag Licence Plate Number).
    static let standardLeadingDigit = 0

    /// All ten digits, as the barcode encodes them.
    var digits: String {
        String(leadingDigit) + String(format: "%03d", issuerCode) + String(format: "%06d", serial)
    }

    /// Human-readable form, grouped as printed on real tags: "0905 482913".
    var printed: String {
        let d = digits
        return String(d.prefix(4)) + " " + String(d.suffix(6))
    }

    /// Spoken form for VoiceOver: digit by digit, the way an agent reads a tag.
    var spoken: String {
        digits.map(String.init).joined(separator: " ")
    }

    /// The tag for a booking. Deterministic, so the same booking reprints the
    /// same number if the traveler steps back and forward, and arrival can
    /// quote the claim number without it being stored anywhere.
    static func make(flightNumber: String, seat: String, bookedAt: Date) -> BagTagLicensePlate {
        let carrierCode = flightNumber.prefix { !$0.isWhitespace }
        let carrier = Carrier(rawValue: String(carrierCode)) ?? .voyageAir
        let seed = fnv1a("\(flightNumber)|\(seat)|\(Int(bookedAt.timeIntervalSince1970))")
        return BagTagLicensePlate(
            leadingDigit: standardLeadingDigit,
            issuerCode: carrier.baggageTagIssuerCode,
            serial: Int(seed % 1_000_000)
        )
    }

    /// FNV-1a, as `RoutePlanner.fallbackFlightNumber` uses: stable across
    /// launches, unlike `String.hashValue`.
    static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}

extension Carrier {
    /// Three-digit Baggage Tag Issuer Code for the license plate.
    ///
    /// The carriers are fictional, so these must not be a real airline's
    /// number: 006 is Delta and 016 is United, and a tag reading "0016..."
    /// would claim United's identity the same way a two-letter designator
    /// would (see the note on `Carrier`). Each value below is absent from the
    /// 525 three-digit airline prefixes in ShereSoft/AirlineCollection
    /// (src/AirlineCollection/AirlineCollection/AirlineCollection.cs, checked
    /// 2026-09-24). That list is not IATA's register, so treat these as
    /// "not a known carrier" rather than "guaranteed unassigned".
    var baggageTagIssuerCode: Int {
        switch self {
        case .harborline: return 905
        case .ridgeway: return 913
        case .voyageAir: return 868
        case .baywater: return 920
        case .northline: return 931
        case .lantern: return 950
        }
    }
}

// MARK: - Tag content

/// Everything printed on the tag, derived from the booking.
///
/// Routing follows the IATA EBT Implementation Guide 1.2, Annex I (RP 1754)
/// "Routing Area": the final destination at the top, then each transfer point
/// below it, with the flight number and date beside every airport code. The
/// flight beside a code is the one that carries the bag *into* that airport,
/// as on the Northwest PDX-DTW-FRA tag on Wikimedia Commons, where FRA sits
/// over NW 52 and DTW over NW 374.
struct BagTagContent {
    struct RoutingLine: Hashable {
        let airportCode: String
        let flightNumber: String
        let isFinal: Bool
    }

    let plate: BagTagLicensePlate
    let issuingCarrierName: String
    let originCode: String
    let destinationCode: String
    let destinationCity: String
    /// Final destination first, then transfer points from last to first.
    let routing: [RoutingLine]
    /// "24SEP", the airline date form.
    let dateText: String
    let seat: String

    init(itinerary: Itinerary, seat: String, bookedAt: Date, calendar: Calendar = .current) {
        let first = itinerary.legs[0]
        plate = BagTagLicensePlate.make(flightNumber: first.flightNumber, seat: seat, bookedAt: bookedAt)
        let carrierCode = first.flightNumber.prefix { !$0.isWhitespace }
        issuingCarrierName = (Carrier(rawValue: String(carrierCode)) ?? .voyageAir).name.uppercased()
        originCode = itinerary.origin.code
        destinationCode = itinerary.destination.code
        destinationCity = itinerary.destination.city.uppercased()
        routing = itinerary.legs.enumerated().reversed().map { index, leg in
            RoutingLine(airportCode: leg.destination.code,
                        flightNumber: leg.flightNumber,
                        isFinal: index == itinerary.legs.count - 1)
        }
        dateText = Self.airlineDate(bookedAt, calendar: calendar)
        self.seat = seat
    }

    /// Day and three-letter month, English regardless of locale, as tags and
    /// boarding passes print it: "24SEP".
    static func airlineDate(_ date: Date, calendar: Calendar = .current) -> String {
        let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN",
                      "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
        let parts = calendar.dateComponents([.day, .month], from: date)
        let day = parts.day ?? 1
        let month = months[((parts.month ?? 1) - 1) % 12]
        return String(format: "%02d", day) + month
    }
}

// MARK: - One tag per task

/// Tag stock. Standard is free, always. Priority (a red PRIORITY band and a
/// FIRST routing block, like the tags carriers issue premium passengers) and
/// carrier livery are Voyage First additions; nothing free moves behind them.
enum BagTagStyle: String, CaseIterable, Identifiable {
    case standard, priority, livery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Standard"
        case .priority: return "Priority"
        case .livery: return "Livery"
        }
    }

    var requiresVoyageFirst: Bool { self != .standard }
}

/// The three-letter code printed big on a task's tag, the way a bag tag
/// prints its destination airport. "Organic chem problem set" is OCP.
enum TaskCode {
    static let stopWords: Set<String> = ["the", "a", "an", "of", "for", "and", "to"]
    private static let vowels: Set<Character> = ["A", "E", "I", "O", "U"]

    /// First letters of up to three significant words; with fewer than three,
    /// filled from the words' next consonants (last word first), then vowels.
    /// Uppercase ASCII only. A code that collides with `avoiding` or with a
    /// catalog airport has its last letter bumped (A→B…Z→A) until it is free.
    static func make(from title: String, avoiding: Set<String> = []) -> String {
        let words = title
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .uppercased()
            .split { !($0.isASCII && $0.isLetter) }
            .map(String.init)
        let significant = words.filter { !stopWords.contains($0.lowercased()) }
        let source = significant.isEmpty ? words : significant

        var letters = Array(source.prefix(3).compactMap(\.first))
        if letters.count < 3 {
            // Fill from what follows each word's initial, last word first
            // ("Read ch" is RCH, "Essay" is ESS): consonants, then vowels.
            let rest = source.prefix(3).reversed().flatMap { $0.dropFirst() }
            for c in rest where !vowels.contains(c) && letters.count < 3 { letters.append(c) }
            for c in rest where vowels.contains(c) && letters.count < 3 { letters.append(c) }
        }
        while letters.count < 3 { letters.append("X") }
        var code = String(letters.prefix(3))

        let taken = avoiding.union(airportCodes)
        var attempts = 0
        while taken.contains(code) && attempts < 26 {
            code = bumped(code)
            attempts += 1
        }
        return code
    }

    /// Codes for a list of tasks, each avoiding the ones before it. Codes the
    /// traveler already edited (`existing`, same index) are kept.
    static func codes(for titles: [String], existing: [String] = []) -> [String] {
        var used: Set<String> = []
        return titles.enumerated().map { index, title in
            if index < existing.count, let kept = sanitized(existing[index]), !used.contains(kept) {
                used.insert(kept)
                return kept
            }
            let code = make(from: title, avoiding: used)
            used.insert(code)
            return code
        }
    }

    /// A hand-edited code: three ASCII letters, uppercased, or nil.
    static func sanitized(_ raw: String) -> String? {
        let letters = raw.uppercased().filter { $0.isASCII && $0.isLetter }
        return letters.count == 3 ? letters : nil
    }

    private static let airportCodes = Set(Airport.all.map(\.code))

    private static func bumped(_ code: String) -> String {
        var chars = Array(code)
        let last = chars[2].asciiValue ?? 65
        chars[2] = Character(UnicodeScalar(last >= 90 ? 65 : last + 1))
        return String(chars)
    }
}

/// One checked bag: one task, its code, and its own plate. Consecutive
/// serials, like tags printed one after another at a counter.
struct TaskBagTag: Hashable, Identifiable {
    let index: Int
    let count: Int
    let title: String
    var code: String
    let plate: BagTagLicensePlate
    var style: BagTagStyle
    var id: Int { index }

    /// "BAG 2 OF 3"
    var bagLine: String { "BAG \(index + 1) OF \(count)" }

    /// "Bag 2 of 3, O C P, Organic chem problem set"
    var accessibilityLabel: String {
        "Bag \(index + 1) of \(count), \(code.map(String.init).joined(separator: " ")), \(title)"
    }

    static func tags(titles: [String], codes: [String], base: BagTagLicensePlate,
                     style: BagTagStyle = .standard) -> [TaskBagTag] {
        let resolved = TaskCode.codes(for: titles, existing: codes)
        return titles.enumerated().map { index, title in
            TaskBagTag(index: index, count: titles.count, title: title, code: resolved[index],
                       plate: BagTagLicensePlate(leadingDigit: base.leadingDigit,
                                                 issuerCode: base.issuerCode,
                                                 serial: (base.serial + index) % 1_000_000),
                       style: style)
        }
    }
}

/// Bags left on the carousel: tasks from recent flights that were checked but
/// not claimed. They ride the next flight, first in the recent-bag chips.
enum MishandledBags {
    static func pending(in entries: [LogbookEntry], lookback: Int = 10) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for entry in entries.prefix(lookback) {
            for (index, intention) in entry.intentions.enumerated() {
                let claimed = index < entry.intentionsCompleted.count && entry.intentionsCompleted[index]
                let key = intention.lowercased()
                guard !claimed, !seen.contains(key) else { continue }
                seen.insert(key)
                result.append(intention)
            }
            // A bag claimed later removes it from the carousel.
            for (index, intention) in entry.intentions.enumerated()
            where index < entry.intentionsCompleted.count && entry.intentionsCompleted[index] {
                seen.insert(intention.lowercased())
            }
        }
        return result
    }
}
