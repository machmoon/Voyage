import Foundation

/// The if-then plan written when a departure is scheduled: "When it's 7:00
/// PM at the library, I'll board VOY 212 to Denver."
///
/// Implementation intentions ("When situation X arises, I will do Y") had a
/// medium-to-large effect on goal attainment across 94 independent tests,
/// d = .65 (Gollwitzer & Sheeran 2006, Advances in Experimental Social
/// Psychology 38). The plan is prefilled from the scheduled time and the
/// place the traveler picks, stays editable, and is read back on the boarding
/// pass and in the boarding reminder.
enum DeparturePlace: String, CaseIterable, Identifiable, Codable {
    case library, home, cafe, campus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: return "Library"
        case .home: return "Home"
        case .cafe: return "Café"
        case .campus: return "Campus"
        }
    }

    /// "at the library", "at home".
    var phrase: String {
        switch self {
        case .library: return "at the library"
        case .home: return "at home"
        case .cafe: return "at the café"
        case .campus: return "on campus"
        }
    }

    var symbol: String {
        switch self {
        case .library: return "books.vertical.fill"
        case .home: return "house.fill"
        case .cafe: return "cup.and.saucer.fill"
        case .campus: return "building.columns.fill"
        }
    }
}

enum DeparturePlan {
    /// "When it's 7:00 PM at the library, I'll board VOY 212 to Denver."
    static func sentence(departure: Date, place: DeparturePlace, flightNumber: String,
                         destination: Airport, locale: Locale = Locale(identifier: "en_US"),
                         timeZone: TimeZone = .current) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.locale = locale
        style.timeZone = timeZone
        let time = departure.formatted(style)
        return "When it's \(time) \(place.phrase), I'll board \(flightNumber) to \(destination.city)."
    }

    /// The boarding reminder's body: the plan, read back.
    static func reminderBody(plan: String?) -> String {
        let fallback = "Your flight departs in 10 minutes. Boarding closes 15 minutes after departure."
        guard let plan = plan?.trimmingCharacters(in: .whitespacesAndNewlines), !plan.isEmpty else {
            return fallback
        }
        return "Your plan: \(plan) Departs in 10 minutes."
    }
}
