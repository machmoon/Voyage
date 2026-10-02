import Foundation
import EventKit

// What customs may ask about: the traveler's own study material, gathered on
// this iPhone and handed to the on-device model as data. Nothing here makes a
// network call, and nothing gathered here is stored or logged.
//
// Two kinds of input:
// - the flight itself (its bag-tag tasks), which is always there;
// - further sources, each one `StudyContextSource`. Version 1 has one, the
//   calendar. A Canvas iCal feed or Google Drive is another conformer later,
//   added to `StudyContextSources.live` and nowhere else.
//
// The budget matters: the on-device model has 4,096 tokens for instructions,
// prompt and output together (Apple TN3193), so every snippet is trimmed and
// the total is capped here, before any prompt is written.

// MARK: - Shape

/// One piece of study material, in the traveler's own words.
struct StudySnippet: Equatable, Sendable {
    enum Origin: String, Sendable {
        /// A checked bag on this flight.
        case bagTag
        /// A calendar event near the flight.
        case calendar
    }

    let origin: Origin
    let title: String
    /// Extra words the traveler wrote, such as an event's notes. Optional.
    let detail: String?
}

/// Everything customs knows about what was studied, in priority order: the
/// flight's own bags first, then the nearest calendar events.
struct StudyContext: Equatable, Sendable {
    static let maximumSnippets = 8
    static let maximumTitleLength = 120
    static let maximumDetailLength = 160

    let snippets: [StudySnippet]

    static let empty = StudyContext(snippets: [])

    var isEmpty: Bool { snippets.isEmpty }

    /// Every word the context contains, for the grounding rules
    /// (`BriefingRules.numbersAreGrounded`, `mentionsABag`).
    var texts: [String] {
        snippets.flatMap { [$0.title] + ($0.detail.map { [$0] } ?? []) }
    }

    /// Trims, drops empty and duplicate titles, and caps the list. Order is
    /// kept, so whatever the caller put first survives the cap.
    init(snippets: [StudySnippet]) {
        var seen = Set<String>()
        var kept: [StudySnippet] = []
        for snippet in snippets {
            let title = Self.clean(snippet.title, limit: Self.maximumTitleLength)
            guard !title.isEmpty, seen.insert(title.lowercased()).inserted else { continue }
            let detail = snippet.detail.map { Self.clean($0, limit: Self.maximumDetailLength) }
            kept.append(StudySnippet(origin: snippet.origin, title: title,
                                     detail: detail?.isEmpty == false ? detail : nil))
            if kept.count == Self.maximumSnippets { break }
        }
        self.snippets = kept
    }

    /// One line per snippet, numbered, as the prompt carries it.
    var promptLines: String {
        snippets.enumerated().map { index, snippet in
            let label = snippet.origin == .bagTag ? "Task" : "Calendar"
            let detail = snippet.detail.map { " (\($0))" } ?? ""
            return "\(index + 1). \(label): \(snippet.title)\(detail)"
        }
        .joined(separator: "\n")
    }

    /// Collapses whitespace, removes links (a meeting URL in an event's notes
    /// is not study material and costs tokens), and cuts to `limit`.
    static func clean(_ text: String, limit: Int) -> String {
        let words = text
            .split(whereSeparator: \.isWhitespace)
            .filter { !$0.contains("://") && !$0.hasPrefix("www.") }
        return String(words.joined(separator: " ").prefix(limit))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The flight's bags, then each source in turn. A source that has nothing
    /// (no permission, no events) simply adds nothing.
    static func assemble(tasks: [String],
                         window: DateInterval,
                         sources: [StudyContextSource]) async -> StudyContext {
        var snippets = tasks.map { StudySnippet(origin: .bagTag, title: $0, detail: nil) }
        for source in sources {
            snippets += await source.snippets(near: window)
        }
        return StudyContext(snippets: snippets)
    }
}

// MARK: - Sources

/// One place study material can come from. Calendar today; a Canvas iCal
/// feed or Google Drive later. A source never asks for permission itself:
/// customs asks once, up front, and a source without access returns nothing.
protocol StudyContextSource: Sendable {
    func snippets(near flight: DateInterval) async -> [StudySnippet]
}

enum StudyContextSources {
    /// The sources production reads, in the order their snippets are kept.
    static func live() -> [StudyContextSource] {
        [CalendarStudySource(store: EventKitCalendarStore())]
    }
}

// MARK: - Calendar

/// A calendar event, reduced to what customs reads: title and notes only.
/// Attendees, location and URL are never read.
struct CalendarEvent: Equatable, Sendable {
    let title: String
    let notes: String?
    let start: Date
    let end: Date
}

/// The seam over EventKit, so tests never touch the traveler's calendar.
protocol CalendarEventStore: Sendable {
    /// Whether full read access was granted. Customs never asks from here.
    var canRead: Bool { get }
    func events(in interval: DateInterval) -> [CalendarEvent]
}

/// Events overlapping the flight or near it: a lecture just before boarding,
/// tomorrow's exam. Nearest first, so the cap keeps the relevant ones.
struct CalendarStudySource: StudyContextSource {
    /// How far before departure and after arrival to look. A class earlier
    /// that day, an exam the next day or the day after.
    static let lookBehind: TimeInterval = 12 * 3600
    static let lookAhead: TimeInterval = 48 * 3600
    static let maximumEvents = 5

    let store: CalendarEventStore

    func snippets(near flight: DateInterval) async -> [StudySnippet] {
        guard store.canRead else { return [] }
        let search = DateInterval(start: flight.start.addingTimeInterval(-Self.lookBehind),
                                  end: flight.end.addingTimeInterval(Self.lookAhead))
        return store.events(in: search)
            .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { Self.distance($0, from: flight) < Self.distance($1, from: flight) }
            .prefix(Self.maximumEvents)
            .map { StudySnippet(origin: .calendar, title: $0.title, detail: $0.notes) }
    }

    /// Zero for an event that overlaps the flight, otherwise the gap to it.
    static func distance(_ event: CalendarEvent, from flight: DateInterval) -> TimeInterval {
        if event.end < flight.start { return flight.start.timeIntervalSince(event.end) }
        if event.start > flight.end { return event.start.timeIntervalSince(flight.end) }
        return 0
    }
}

/// EventKit, read-only. `EKEventStore` is documented as safe to use from any
/// thread once created; the store is made per read so nothing holds the
/// traveler's calendar between customs visits.
struct EventKitCalendarStore: CalendarEventStore {
    var canRead: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    func events(in interval: DateInterval) -> [CalendarEvent] {
        guard canRead else { return [] }
        let store = EKEventStore()
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
        return store.events(matching: predicate).map {
            CalendarEvent(title: $0.title ?? "", notes: $0.notes, start: $0.startDate, end: $0.endDate)
        }
    }

    /// Asked once, at the first customs, behind Voyage's own explanation.
    /// iOS 17's full-access request: reading events needs full access, and
    /// Voyage never writes.
    static func requestAccess() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return true
        case .notDetermined: return (try? await EKEventStore().requestFullAccessToEvents()) ?? false
        default: return false
        }
    }
}
