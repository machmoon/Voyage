import SwiftData
import XCTest
@testable import Voyage

/// Runtime representation of Voyage's committed pre-digital-twin model. Its
/// entity name is deliberately `LogbookEntry`, matching the production model,
/// so this creates a genuine old-schema SQLite store for migration testing.
private enum LegacyLogbookSchema {
    @Model
    final class LogbookEntry {
        var date: Date
        var originCode: String
        var destinationCode: String
        var connectionCode: String?
        var flightNumber: String
        var seat: String
        var miles: Double
        var focusSeconds: TimeInterval
        var completed: Bool
        var intentions: [String]
        var intentionsCompleted: [Bool]

        init(
            date: Date,
            originCode: String,
            destinationCode: String,
            connectionCode: String?,
            flightNumber: String,
            seat: String,
            miles: Double,
            focusSeconds: TimeInterval,
            completed: Bool,
            intentions: [String],
            intentionsCompleted: [Bool]
        ) {
            self.date = date
            self.originCode = originCode
            self.destinationCode = destinationCode
            self.connectionCode = connectionCode
            self.flightNumber = flightNumber
            self.seat = seat
            self.miles = miles
            self.focusSeconds = focusSeconds
            self.completed = completed
            self.intentions = intentions
            self.intentionsCompleted = intentionsCompleted
        }
    }
}

@MainActor
final class LogbookMigrationTests: XCTestCase {
    func testPreDigitalTwinStoreLightweightMigratesAndNewOptionalColumnsRemainWritable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "VoyageMigrationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "Logbook.store")
        let originalDate = Date(timeIntervalSince1970: 1_700_000_000)

        do {
            let legacyContainer = try ModelContainer(
                for: LegacyLogbookSchema.LogbookEntry.self,
                configurations: ModelConfiguration(url: storeURL)
            )
            let legacyContext = ModelContext(legacyContainer)
            legacyContext.insert(
                LegacyLogbookSchema.LogbookEntry(
                    date: originalDate,
                    originCode: "SFO",
                    destinationCode: "YQR",
                    connectionCode: "YYZ",
                    flightNumber: "AC 740",
                    seat: "A8",
                    miles: 1_500,
                    focusSeconds: 8_000,
                    completed: true,
                    intentions: ["Read chapter 4"],
                    intentionsCompleted: [true]
                )
            )
            try legacyContext.save()
        }

        do {
            let migratedContainer = try ModelContainer(
                for: Voyage.LogbookEntry.self,
                configurations: ModelConfiguration(url: storeURL)
            )
            let migratedContext = ModelContext(migratedContainer)
            let entries = try migratedContext.fetch(FetchDescriptor<Voyage.LogbookEntry>())
            let entry = try XCTUnwrap(entries.first)

            XCTAssertEqual(entries.count, 1)
            XCTAssertEqual(entry.date, originalDate)
            XCTAssertEqual(entry.originCode, "SFO")
            XCTAssertEqual(entry.destinationCode, "YQR")
            XCTAssertEqual(entry.connectionCode, "YYZ")
            XCTAssertEqual(entry.flightNumber, "AC 740")
            XCTAssertEqual(entry.seat, "A8")
            XCTAssertEqual(entry.intentions, ["Read chapter 4"])
            XCTAssertEqual(entry.intentionsCompleted, [true])
            XCTAssertNil(entry.shareCaption)
            XCTAssertNil(entry.aircraftRaw)
            XCTAssertNil(entry.weatherSnapshotData)
            XCTAssertNil(entry.departureProfileRaw)
            XCTAssertNil(entry.worldRevision)
            XCTAssertNil(entry.routeSamplesData)
            XCTAssertNil(entry.departureCorridorID)
            XCTAssertNil(entry.arrivalCorridorID)
            XCTAssertNil(entry.environmentSnapshotData)
            XCTAssertNil(entry.trajectorySamplesData)
            XCTAssertEqual(entry.aircraft, .voyageClassic)
            XCTAssertTrue(entry.routeSamples.isEmpty)
            XCTAssertTrue(entry.environmentSnapshots.isEmpty)
            XCTAssertTrue(entry.trajectoryLegSamples.isEmpty)

            let weather = WeatherSnapshot.fallback(for: Airport.byCode("SFO"), condition: .fog)
            let legacyRoute = [
                ReplayRouteSample(latitude: 37.6213, longitude: -122.3790, progress: 0),
                ReplayRouteSample(latitude: 50.4319, longitude: -104.6658, progress: 1),
            ]
            let trajectory = [
                FlightTrajectorySample(
                    elapsed: 0,
                    latitude: 37.6213,
                    longitude: -122.3790,
                    altitudeMeters: 0,
                    courseDegrees: 45,
                    pitchDegrees: 0,
                    bankDegrees: 0,
                    routeProgress: 0
                ),
                FlightTrajectorySample(
                    elapsed: 100,
                    latitude: 43.6777,
                    longitude: -79.6248,
                    altitudeMeters: 0,
                    courseDegrees: 45,
                    pitchDegrees: 0,
                    bankDegrees: 0,
                    routeProgress: 1
                ),
            ]
            entry.shareCaption = "Migrated flight"
            entry.aircraftRaw = AircraftProfile.boeing737800.rawValue
            entry.weatherSnapshotData = try JSONEncoder().encode(weather)
            entry.departureProfileRaw = DepartureProfile.sfoBay.rawValue
            entry.worldRevision = FlightVisualEngine.trajectoryRevision
            entry.routeSamplesData = try JSONEncoder().encode(legacyRoute)
            entry.departureCorridorID = "SFO-DEP-28"
            entry.arrivalCorridorID = "YQR-ARR-31"
            entry.environmentSnapshotData = try JSONEncoder().encode([
                FlightEnvironmentSnapshot(
                    frozenAt: originalDate,
                    departureWeather: weather,
                    arrivalWeather: nil
                ),
            ])
            entry.trajectorySamplesData = try JSONEncoder().encode([trajectory])
            try migratedContext.save()
        }

        do {
            let reopenedContainer = try ModelContainer(
                for: Voyage.LogbookEntry.self,
                configurations: ModelConfiguration(url: storeURL)
            )
            let reopenedContext = ModelContext(reopenedContainer)
            let entry = try XCTUnwrap(
                try reopenedContext.fetch(FetchDescriptor<Voyage.LogbookEntry>()).first
            )

            XCTAssertEqual(entry.shareCaption, "Migrated flight")
            XCTAssertEqual(entry.aircraft, .boeing737800)
            XCTAssertEqual(entry.weatherSnapshot?.condition, .fog)
            XCTAssertEqual(entry.departureProfile, .sfoBay)
            XCTAssertEqual(entry.trajectoryRevision, FlightVisualEngine.trajectoryRevision)
            XCTAssertEqual(entry.routeSamples.count, 2)
            XCTAssertEqual(entry.departureCorridorID, "SFO-DEP-28")
            XCTAssertEqual(entry.arrivalCorridorID, "YQR-ARR-31")
            XCTAssertEqual(entry.environmentSnapshots.count, 1)
            XCTAssertEqual(entry.trajectoryLegSamples.count, 1)
            XCTAssertEqual(entry.trajectoryLegSamples.first?.count, 2)
        }
    }
}
