import Foundation

/// Abstraction over wall-clock time so FlightSession can be unit-tested
/// without waiting on real timers.
protocol VoyageClock: Sendable {
    var now: Date { get }
}

struct SystemClock: VoyageClock {
    var now: Date { Date() }
}

/// Mutable clock for tests. Thread-safe so timer callbacks and test code
/// can share it safely.
final class ManualClock: VoyageClock, @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date

    init(now: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self._now = now
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return _now
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        _now = _now.addingTimeInterval(interval)
        lock.unlock()
    }

    func set(_ date: Date) {
        lock.lock()
        _now = date
        lock.unlock()
    }
}
