import AppIntents
import Foundation

// MARK: - Pending shortcut departure

/// Stores a destination chosen via Siri / Shortcuts until Home picks it up.
enum PendingDepartureStore {
    private static let key = "voyage.pendingDepartureCode"

    static var destinationCode: String? {
        get { UserDefaults.standard.string(forKey: key) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
}

// MARK: - Airport entity

struct AirportEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Airport")
    static var defaultQuery = AirportEntityQuery()

    var id: String
    var city: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id)", subtitle: "\(city)")
    }

    init(airport: Airport) {
        id = airport.code
        city = airport.city
    }
}

struct AirportEntityQuery: EntityStringQuery {
    func entities(for identifiers: [AirportEntity.ID]) async throws -> [AirportEntity] {
        identifiers.compactMap { code in
            Airport.all.first { $0.code == code }.map(AirportEntity.init)
        }
    }

    func entities(matching string: String) async throws -> [AirportEntity] {
        let query = string.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return Airport.all.map(AirportEntity.init) }
        return Airport.all.filter {
            $0.code.lowercased().contains(query) || $0.city.lowercased().contains(query)
        }.map(AirportEntity.init)
    }

    func suggestedEntities() async throws -> [AirportEntity] {
        let home = SettingsStore.shared.homeAirport
        return Airport.all.filter { $0 != home }.map(AirportEntity.init)
    }
}

// MARK: - Depart intent

struct DepartFlightIntent: AppIntent {
    static var title: LocalizedStringResource = "Depart on a focus flight"
    static var description = IntentDescription("Book a focus flight to an airport and open Voyage to board.")
    static var openAppWhenRun = true

    @Parameter(title: "Destination")
    var destination: AirportEntity

    func perform() async throws -> some IntentResult {
        PendingDepartureStore.destinationCode = destination.id
        return .result(dialog: "Heading to \(destination.city). Choose your seat in Voyage.")
    }
}

// MARK: - Shortcuts

struct VoyageShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: DepartFlightIntent(),
            phrases: [
                "Depart on a \(.applicationName) flight",
                "Start a focus flight in \(.applicationName)",
                "Fly with \(.applicationName)"
            ],
            shortTitle: "Depart",
            systemImageName: "airplane.departure"
        )
    }
}
