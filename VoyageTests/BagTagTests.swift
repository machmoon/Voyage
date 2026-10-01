import XCTest
@testable import Voyage

final class BagTagTests: XCTestCase {

    // MARK: Interleaved 2 of 5

    /// "12" by hand from the ITF table: start nnnn, then 1 in the bars
    /// (W n n n W) interleaved with 2 in the spaces (n W n n W), then stop Wnn.
    func testEncodesAPairByInterleavingBarsAndSpaces() throws {
        let elements = try InterleavedTwoOfFive.encode("12")
        let widths = elements.map(\.modules)
        XCTAssertEqual(widths, [1, 1, 1, 1,
                                3, 1, 1, 3, 1, 1, 1, 1, 3, 3,
                                3, 1, 1])
        // Bars and spaces strictly alternate, opening and closing on a bar.
        for (i, element) in elements.enumerated() {
            XCTAssertEqual(element.isBar, i % 2 == 0, "element \(i)")
        }
        XCTAssertTrue(elements.last!.isBar)
    }

    /// ZXing's ITFWriter allocates `9 + 9 * length` modules at a 3:1 ratio;
    /// a ten-digit plate must come out the same width.
    func testTenDigitPlateMatchesZXingModuleCount() throws {
        let elements = try InterleavedTwoOfFive.encode("0868482913")
        XCTAssertEqual(InterleavedTwoOfFive.moduleCount(elements), 9 + 9 * 10)
        // 4 start + 10 digits x 5 elements + 3 stop.
        XCTAssertEqual(elements.count, 4 + 50 + 3)
    }

    /// Every digit's pattern has exactly two wide elements of five: that is
    /// what makes it "2 of 5".
    func testEveryDigitHasExactlyTwoWideElements() {
        XCTAssertEqual(InterleavedTwoOfFive.patterns.count, 10)
        for (digit, pattern) in InterleavedTwoOfFive.patterns.enumerated() {
            XCTAssertEqual(pattern.count, 5)
            XCTAssertEqual(pattern.filter { $0 }.count, 2, "digit \(digit)")
        }
        XCTAssertEqual(Set(InterleavedTwoOfFive.patterns).count, 10, "patterns must be distinct")
    }

    /// Round trip through an independent decoder, including the real United
    /// plate from the Wikimedia Commons photo.
    func testRoundTripsThroughADecoder() throws {
        for digits in ["0000000000", "4016582320", "0868482913", "9876543210", "12"] {
            let elements = try InterleavedTwoOfFive.encode(digits)
            XCTAssertEqual(decode(elements), digits)
        }
    }

    func testRejectsOddLengthAndNonDigits() {
        XCTAssertThrowsError(try InterleavedTwoOfFive.encode("123")) { error in
            XCTAssertEqual(error as? InterleavedTwoOfFive.EncodingError, .oddLength)
        }
        XCTAssertThrowsError(try InterleavedTwoOfFive.encode("12A4")) { error in
            XCTAssertEqual(error as? InterleavedTwoOfFive.EncodingError, .notNumeric)
        }
        // Arabic-Indic digits have a whole-number value but are not ITF digits.
        XCTAssertThrowsError(try InterleavedTwoOfFive.encode("١٢"))
    }

    // MARK: License plate

    private let booked = Date(timeIntervalSince1970: 1_790_000_000)

    func testPlateIsTenDigitsWithIssuerCodeInPositionsTwoToFour() {
        let plate = BagTagLicensePlate.make(flightNumber: "VOY 1566", seat: "C10", bookedAt: booked)
        XCTAssertEqual(plate.digits.count, 10)
        XCTAssertTrue(plate.digits.allSatisfy(\.isNumber))
        XCTAssertEqual(plate.digits.first, "0")
        XCTAssertEqual(String(plate.digits.dropFirst().prefix(3)), "868")
        XCTAssertEqual(plate.printed, String(plate.digits.prefix(4)) + " " + String(plate.digits.suffix(6)))
    }

    func testIssuerCodeFollowsTheFirstLegCarrier() {
        for carrier in Carrier.allCases {
            let plate = BagTagLicensePlate.make(flightNumber: carrier.flightNumberText(101),
                                                seat: "A1", bookedAt: booked)
            XCTAssertEqual(plate.issuerCode, carrier.baggageTagIssuerCode)
        }
    }

    func testPlateIsStableForABookingAndDiffersBetweenBookings() {
        let a = BagTagLicensePlate.make(flightNumber: "VOY 1566", seat: "C10", bookedAt: booked)
        let again = BagTagLicensePlate.make(flightNumber: "VOY 1566", seat: "C10", bookedAt: booked)
        XCTAssertEqual(a, again, "stepping back and forward must reprint the same tag")

        let otherSeat = BagTagLicensePlate.make(flightNumber: "VOY 1566", seat: "D10", bookedAt: booked)
        let otherTime = BagTagLicensePlate.make(flightNumber: "VOY 1566", seat: "C10",
                                                bookedAt: booked.addingTimeInterval(60))
        XCTAssertNotEqual(a.serial, otherSeat.serial)
        XCTAssertNotEqual(a.serial, otherTime.serial)
    }

    /// The fictional carriers must never print a real airline's issuer code.
    /// 001 American, 006 Delta, 016 United, 037 US Airways, 125 British
    /// Airways, 014 Air Canada: the carriers the owner's audience would know.
    func testIssuerCodesAreDistinctAndAvoidWellKnownCarriers() {
        let codes = Carrier.allCases.map(\.baggageTagIssuerCode)
        XCTAssertEqual(Set(codes).count, codes.count)
        for code in codes {
            XCTAssertTrue((100...999).contains(code))
            XCTAssertFalse([1, 6, 14, 16, 37, 125].contains(code))
        }
    }

    // MARK: Tag content

    func testNonstopRoutingIsTheDestinationAlone() {
        let itinerary = RoutePlanner.itinerary(from: Airport.byCode("BOS"), to: Airport.byCode("JFK"))
        let tag = BagTagContent(itinerary: itinerary, seat: "C10", bookedAt: booked)
        XCTAssertEqual(tag.routing.map(\.airportCode), ["JFK"])
        XCTAssertEqual(tag.routing.first?.isFinal, true)
        XCTAssertEqual(tag.destinationCode, "JFK")
    }

    /// Final destination on top, then the transfer point, each with the flight
    /// that carries the bag into it.
    func testConnectionRoutingListsFinalDestinationThenVia() {
        let itinerary = RoutePlanner.itinerary(from: Airport.byCode("SFO"), to: Airport.byCode("YQR"))
        XCTAssertTrue(itinerary.isConnection)
        let tag = BagTagContent(itinerary: itinerary, seat: "C10", bookedAt: booked)
        XCTAssertEqual(tag.routing.map(\.airportCode), ["YQR", "YVR"])
        XCTAssertEqual(tag.routing.map(\.isFinal), [true, false])
        XCTAssertEqual(tag.routing[0].flightNumber, itinerary.legs[1].flightNumber)
        XCTAssertEqual(tag.routing[1].flightNumber, itinerary.legs[0].flightNumber)
    }

    func testAirlineDateIsDayThenEnglishMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 4))!
        XCTAssertEqual(BagTagContent.airlineDate(date, calendar: calendar), "04SEP")
    }

    // MARK: Helpers

    /// Independent ITF decoder: classifies each run as narrow or wide, strips
    /// start and stop, and reads each ten-element group back into two digits.
    private func decode(_ elements: [InterleavedTwoOfFive.Element]) -> String? {
        guard elements.count >= 7 else { return nil }
        let start = elements.prefix(4).map(\.modules)
        let stop = elements.suffix(3).map(\.modules)
        guard start == [1, 1, 1, 1], stop[0] > 1, stop[1] == 1, stop[2] == 1 else { return nil }
        let body = Array(elements.dropFirst(4).dropLast(3))
        guard body.count % 10 == 0 else { return nil }
        let table: [[Bool]: Int] = [
            [false, false, true, true, false]: 0, [true, false, false, false, true]: 1,
            [false, true, false, false, true]: 2, [true, true, false, false, false]: 3,
            [false, false, true, false, true]: 4, [true, false, true, false, false]: 5,
            [false, true, true, false, false]: 6, [false, false, false, true, true]: 7,
            [true, false, false, true, false]: 8, [false, true, false, true, false]: 9,
        ]
        var out = ""
        for group in stride(from: 0, to: body.count, by: 10) {
            let chunk = body[group..<group + 10]
            let bars = chunk.enumerated().filter { $0.offset % 2 == 0 }.map { $0.element.modules > 1 }
            let spaces = chunk.enumerated().filter { $0.offset % 2 == 1 }.map { $0.element.modules > 1 }
            guard let a = table[bars], let b = table[spaces] else { return nil }
            out += "\(a)\(b)"
        }
        return out
    }
}

final class PassPurposeTests: XCTestCase {
    func testStandardStockIsFreeAndTheRestAreVoyageFirst() {
        XCTAssertFalse(PassStyle.standard.requiresVoyageFirst)
        XCTAssertTrue(PassStyle.priority.requiresVoyageFirst)
        XCTAssertTrue(PassStyle.livery.requiresVoyageFirst)
    }

    /// Every paid stock is also earned free by flying: priority at Gold,
    /// livery at Platinum. Voyage First only opens them early.
    func testPaidStockIsEarnedByStatus() {
        XCTAssertTrue(PassStyle.standard.isUnlocked(tier: .member, isFirstMember: false))
        XCTAssertFalse(PassStyle.priority.isUnlocked(tier: .silver, isFirstMember: false))
        XCTAssertTrue(PassStyle.priority.isUnlocked(tier: .gold, isFirstMember: false))
        XCTAssertFalse(PassStyle.livery.isUnlocked(tier: .gold, isFirstMember: false))
        XCTAssertTrue(PassStyle.livery.isUnlocked(tier: .platinum, isFirstMember: false))
        for style in PassStyle.allCases {
            XCTAssertTrue(style.isUnlocked(tier: .member, isFirstMember: true))
        }
    }

    @MainActor
    func testUnclaimedBagsRideTheNextFlight() {
        func entry(_ intentions: [String], _ done: [Bool]) -> LogbookEntry {
            LogbookEntry(originCode: "SFO", destinationCode: "LAX", flightNumber: "VOY 1", seat: "C1",
                         miles: 1, focusSeconds: 1, completed: true,
                         intentions: intentions, intentionsCompleted: done)
        }
        // Newest first, as the check-in query sorts.
        let entries = [
            entry(["Essay", "Lab report"], [true, false]),
            entry(["Essay", "Flashcards"], [false, false]),
        ]
        XCTAssertEqual(CarriedPurposes.pending(in: entries), ["Lab report", "Flashcards"])
    }

    /// "Let it go" at landing ends a purpose; "Bring it next trip" keeps it.
    @MainActor
    func testDroppedPurposesDoNotComeBack() {
        let carried = LogbookEntry(originCode: "SFO", destinationCode: "LAX", flightNumber: "VOY 1", seat: "C1",
                                   miles: 1, focusSeconds: 1, completed: true,
                                   intentions: ["Lab report"], intentionsCompleted: [false])
        let dropped = LogbookEntry(originCode: "SFO", destinationCode: "LAX", flightNumber: "VOY 2", seat: "C1",
                                   miles: 1, focusSeconds: 1, completed: true,
                                   intentions: ["Flashcards"], intentionsCompleted: [false])
        dropped.intentionsDropped = [true]
        XCTAssertEqual(CarriedPurposes.pending(in: [dropped, carried]), ["Lab report"])
        // A later flight that finishes it takes it off the list too.
        let finished = LogbookEntry(originCode: "SFO", destinationCode: "LAX", flightNumber: "VOY 3", seat: "C1",
                                    miles: 1, focusSeconds: 1, completed: true,
                                    intentions: ["lab report"], intentionsCompleted: [true])
        XCTAssertEqual(CarriedPurposes.pending(in: [finished, dropped, carried]), [])
    }

    func testReceiptPurposeLine() {
        XCTAssertNil(FlightReceiptView.makePurposeLine(intentions: [], completed: []))
        XCTAssertEqual(FlightReceiptView.makePurposeLine(intentions: ["Essay"], completed: [true]), "Essay ✓")
        XCTAssertEqual(FlightReceiptView.makePurposeLine(intentions: ["Essay"], completed: [false]), "Essay · not yet")
        XCTAssertEqual(FlightReceiptView.makePurposeLine(intentions: ["Essay", "Lab"], completed: [true, false]),
                       "1/2 bags claimed at arrival")
    }
}
