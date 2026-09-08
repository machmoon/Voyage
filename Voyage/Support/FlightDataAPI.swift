import CoreLocation
import Foundation

/// Stable boundary between Voyage's UI and its source of flight records.
/// The catalog-backed implementation works offline today; a future authenticated
/// provider can conform to this protocol without changing replay views.
protocol FlightDataProviding {
    func itinerary(for entry: LogbookEntry) -> Itinerary
    func replaySnapshot(for entry: LogbookEntry, progress: Double) -> FlightReplaySnapshot
    func routeCoordinates(for entry: LogbookEntry) -> [CLLocationCoordinate2D]
}

struct FlightReplaySnapshot {
    let coordinate: CLLocationCoordinate2D
    let course: Double
    let legIndex: Int
    let legProgress: Double
}

struct FlightDataAPI: FlightDataProviding {
    static let shared = FlightDataAPI()

    /// Memo for the two persisted archives every replay frame reads. See
    /// `ReplayArchiveCache` for why this is not optional.
    private let archives = ReplayArchiveCache()

    func itinerary(for entry: LogbookEntry) -> Itinerary {
        RoutePlanner.itinerary(
            from: entry.origin,
            to: entry.destination,
            flightNumberOverride: entry.flightNumber
        )
    }

    func replaySnapshot(for entry: LogbookEntry, progress: Double) -> FlightReplaySnapshot {
        let clamped = min(1, max(0, progress))
        if let archived = archivedTrajectorySnapshot(for: entry, progress: clamped) {
            return archived
        }
        if let legacy = legacyRouteSnapshot(for: entry, progress: clamped) {
            return legacy
        }

        let itinerary = itinerary(for: entry)
        let totalDuration = max(1, itinerary.totalFocusDuration)
        var remaining = clamped * totalDuration

        for (index, leg) in itinerary.legs.enumerated() {
            if remaining <= leg.duration || index == itinerary.legs.indices.last {
                let legProgress = min(1, max(0, remaining / max(1, leg.duration)))
                let coordinate = GreatCircle.point(
                    from: leg.origin.coordinate,
                    to: leg.destination.coordinate,
                    fraction: legProgress
                )
                let courseSample = min(1, legProgress + 0.002)
                let previousSample = max(0, legProgress - 0.002)
                let course: Double
                if courseSample > legProgress {
                    let ahead = GreatCircle.point(
                        from: leg.origin.coordinate,
                        to: leg.destination.coordinate,
                        fraction: courseSample
                    )
                    course = GreatCircle.bearing(from: coordinate, to: ahead)
                } else {
                    let behind = GreatCircle.point(
                        from: leg.origin.coordinate,
                        to: leg.destination.coordinate,
                        fraction: previousSample
                    )
                    course = GreatCircle.bearing(from: behind, to: coordinate)
                }
                return FlightReplaySnapshot(
                    coordinate: coordinate,
                    course: course,
                    legIndex: index,
                    legProgress: legProgress
                )
            }
            remaining -= leg.duration
        }

        let finalLeg = itinerary.legs[itinerary.legs.count - 1]
        return FlightReplaySnapshot(
            coordinate: finalLeg.destination.coordinate,
            course: GreatCircle.bearing(from: finalLeg.origin.coordinate, to: finalLeg.destination.coordinate),
            legIndex: itinerary.legs.count - 1,
            legProgress: 1
        )
    }

    func routeCoordinates(for entry: LogbookEntry) -> [CLLocationCoordinate2D] {
        if let archivedLegs = validatedArchivedTrajectory(for: entry) {
            let archived = archivedLegs.enumerated().flatMap { legIndex, samples in
                samples.enumerated().compactMap { sampleIndex, sample -> CLLocationCoordinate2D? in
                    if legIndex > 0 && sampleIndex == 0 { return nil }
                    return CLLocationCoordinate2D(
                        latitude: sample.latitude,
                        longitude: sample.longitude
                    )
                }
            }
            if archived.count >= 2 { return archived }
        }

        let legacy = routeSamples(for: entry).sorted { $0.progress < $1.progress }.compactMap { sample -> CLLocationCoordinate2D? in
            let coordinate = CLLocationCoordinate2D(latitude: sample.latitude, longitude: sample.longitude)
            return sample.latitude.isFinite && sample.longitude.isFinite &&
                CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
        }
        if legacy.count >= 2 { return legacy }

        return itinerary(for: entry).legs.enumerated().flatMap { index, leg in
            let points = GreatCircle.points(
                from: leg.origin.coordinate,
                to: leg.destination.coordinate,
                count: 96
            )
            return index == 0 ? points : Array(points.dropFirst())
        }
    }

    /// Revision-1 samples are authoritative: they include runway roll,
    /// departure turns, altitude-aware route position, approach and rollout.
    /// Corrupt archives fall through to the legacy route or Great Circle.
    private func archivedTrajectorySnapshot(
        for entry: LogbookEntry,
        progress: Double
    ) -> FlightReplaySnapshot? {
        guard let legs = validatedArchivedTrajectory(for: entry) else { return nil }

        let durations = legs.map { max(0.001, $0.last?.elapsed ?? 0.001) }
        let total = durations.reduce(0, +)
        var requested = progress * total
        for (legIndex, samples) in legs.enumerated() {
            let duration = durations[legIndex]
            if requested <= duration || legIndex == legs.indices.last {
                let elapsed = min(duration, max(0, requested))
                let pair = boundingSamples(samples, elapsed: elapsed)
                let span = max(0.000_001, pair.upper.elapsed - pair.lower.elapsed)
                let fraction = min(1, max(0, (elapsed - pair.lower.elapsed) / span))
                let coordinate = GreatCircle.point(
                    from: CLLocationCoordinate2D(
                        latitude: pair.lower.latitude,
                        longitude: pair.lower.longitude
                    ),
                    to: CLLocationCoordinate2D(
                        latitude: pair.upper.latitude,
                        longitude: pair.upper.longitude
                    ),
                    fraction: fraction
                )
                return FlightReplaySnapshot(
                    coordinate: coordinate,
                    course: interpolatedDegrees(
                        pair.lower.courseDegrees,
                        pair.upper.courseDegrees,
                        fraction: fraction
                    ),
                    legIndex: legIndex,
                    legProgress: pair.lower.routeProgress
                        + (pair.upper.routeProgress - pair.lower.routeProgress) * fraction
                )
            }
            requested -= duration
        }
        return nil
    }

    /// Treat the persisted trajectory as one atomic archive. A corrupt or
    /// partially decoded connection must never have its surviving legs filtered
    /// and reindexed, because that can replay leg 2 as if it departed at leg 1.
    ///
    /// Memoized: the work below is what made replay expensive, and a rejected
    /// archive is just as worth caching as an accepted one, since a corrupt row
    /// would otherwise be re-decoded and re-rejected on every frame.
    private func validatedArchivedTrajectory(
        for entry: LogbookEntry
    ) -> [[FlightTrajectorySample]]? {
        archives.trajectory(for: entry) { computeValidatedArchivedTrajectory(for: entry) }
    }

    /// The uncached body. Only `validatedArchivedTrajectory` may call this.
    private func computeValidatedArchivedTrajectory(
        for entry: LogbookEntry
    ) -> [[FlightTrajectorySample]]? {
        guard entry.trajectoryRevision == FlightVisualEngine.trajectoryRevision,
              let expectedEndpoints = expectedArchivedLegEndpoints(for: entry) else {
            return nil
        }

        let archivedLegs = entry.trajectoryLegSamples
        guard !archivedLegs.isEmpty, archivedLegs.count == expectedEndpoints.count else {
            return nil
        }

        for (index, samples) in archivedLegs.enumerated() {
            guard samples.count >= 2,
                  let first = samples.first,
                  let last = samples.last,
                  abs(first.elapsed) <= 0.001,
                  last.elapsed > first.elapsed,
                  first.routeProgress >= 0,
                  first.routeProgress <= 0.02,
                  last.routeProgress >= 0.98,
                  last.routeProgress <= 1,
                  samples.allSatisfy(isValidArchivedSample),
                  zip(samples, samples.dropFirst()).allSatisfy({ previous, next in
                      next.elapsed > previous.elapsed &&
                          next.routeProgress >= previous.routeProgress
                  }) else {
                return nil
            }

            let endpoints = expectedEndpoints[index]
            let start = CLLocation(latitude: first.latitude, longitude: first.longitude)
            let end = CLLocation(latitude: last.latitude, longitude: last.longitude)
            guard start.distance(from: endpoints.origin.location) <= 15_000,
                  end.distance(from: endpoints.destination.location) <= 15_000 else {
                return nil
            }
        }

        return archivedLegs
    }

    private func expectedArchivedLegEndpoints(
        for entry: LogbookEntry
    ) -> [(origin: Airport, destination: Airport)]? {
        guard let origin = Airport.all.first(where: { $0.code == entry.originCode }),
              let destination = Airport.all.first(where: { $0.code == entry.destinationCode }),
              origin != destination else {
            return nil
        }

        guard let connectionCode = entry.connectionCode else {
            return [(origin, destination)]
        }
        guard let connection = Airport.all.first(where: { $0.code == connectionCode }),
              connection != origin,
              connection != destination else {
            return nil
        }
        return [(origin, connection), (connection, destination)]
    }

    private func isValidArchivedSample(_ sample: FlightTrajectorySample) -> Bool {
        let coordinate = CLLocationCoordinate2D(
            latitude: sample.latitude,
            longitude: sample.longitude
        )
        return sample.elapsed.isFinite && sample.elapsed >= 0 &&
            sample.latitude.isFinite && sample.longitude.isFinite &&
            sample.altitudeMeters.isFinite && sample.courseDegrees.isFinite &&
            sample.pitchDegrees.isFinite && sample.bankDegrees.isFinite &&
            sample.routeProgress.isFinite && (0...1).contains(sample.routeProgress) &&
            CLLocationCoordinate2DIsValid(coordinate)
    }

    private func legacyRouteSnapshot(
        for entry: LogbookEntry,
        progress: Double
    ) -> FlightReplaySnapshot? {
        let samples = routeSamples(for: entry).filter {
            $0.progress.isFinite && $0.latitude.isFinite && $0.longitude.isFinite &&
                CLLocationCoordinate2DIsValid(
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                )
        }.sorted { $0.progress < $1.progress }
        guard samples.count >= 2 else { return nil }

        let upperIndex = samples.firstIndex { $0.progress >= progress } ?? samples.count - 1
        let lowerIndex = max(0, upperIndex - 1)
        let lower = samples[lowerIndex]
        let upper = samples[upperIndex]
        let span = max(0.000_001, upper.progress - lower.progress)
        let fraction = min(1, max(0, (progress - lower.progress) / span))
        let start = CLLocationCoordinate2D(latitude: lower.latitude, longitude: lower.longitude)
        let end = CLLocationCoordinate2D(latitude: upper.latitude, longitude: upper.longitude)
        let coordinate = GreatCircle.point(from: start, to: end, fraction: fraction)
        let itinerary = itinerary(for: entry)
        let totalDuration = max(1, itinerary.totalFocusDuration)
        var remaining = progress * totalDuration
        var legIndex = 0
        for (index, leg) in itinerary.legs.enumerated() {
            legIndex = index
            if remaining <= leg.duration { break }
            remaining -= leg.duration
        }
        let leg = itinerary.legs[min(legIndex, itinerary.legs.count - 1)]
        return FlightReplaySnapshot(
            coordinate: coordinate,
            course: GreatCircle.bearing(from: start, to: end),
            legIndex: legIndex,
            legProgress: min(1, max(0, remaining / max(1, leg.duration)))
        )
    }

    private func boundingSamples(
        _ samples: [FlightTrajectorySample],
        elapsed: TimeInterval
    ) -> (lower: FlightTrajectorySample, upper: FlightTrajectorySample) {
        let upperIndex = samples.firstIndex { $0.elapsed >= elapsed } ?? samples.count - 1
        let lowerIndex = max(0, upperIndex - 1)
        return (samples[lowerIndex], samples[upperIndex])
    }

    private func interpolatedDegrees(_ start: Double, _ end: Double, fraction: Double) -> Double {
        var delta = (end - start).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        let value = start + delta * fraction
        return (value.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }

    /// The pre-trajectory route trace, memoized for the same reason as the
    /// archive: it is the fallback `replaySnapshot` takes for older logbook
    /// rows, so on those flights it is the per-frame decode.
    private func routeSamples(for entry: LogbookEntry) -> [ReplayRouteSample] {
        archives.routeSamples(for: entry)
    }
}

/// Memo for the two persisted archives `replaySnapshot` reads on every frame.
///
/// `LogbookEntry.trajectoryLegSamples` and `LogbookEntry.routeSamples` are
/// computed properties that run `JSONDecoder` on *every* access, and
/// `validatedArchivedTrajectory` then walks every decoded sample. Replay reads
/// a snapshot from a SwiftUI view body that a `CADisplayLink` invalidates 60 to
/// 120 times a second, so before this existed a two-leg flight re-decoded and
/// re-validated roughly 120 KB of JSON on every frame, on the main thread.
///
/// Invalidation is by value, not by trust: each slot remembers the exact `Data`
/// it decoded and is only reused when the entry still holds that same blob. A
/// row whose archive is rewritten therefore re-decodes rather than replaying a
/// stale trajectory, and an `ObjectIdentifier` that happens to be reused by a
/// freshly allocated entry cannot serve the previous entry's route.
///
/// Bounded: a week replay walks at most seven entries, and the whole map is
/// dropped rather than aged, because a replay screen's working set turns over
/// completely rather than gradually.
private final class ReplayArchiveCache: @unchecked Sendable {
    /// A decoded value together with the blob it came from.
    private struct Slot<Value> {
        let source: Data?
        let value: Value
    }

    /// Guards both maps. Held only around the map reads and writes, never
    /// across a decode, so a cold miss cannot serialize other callers.
    private let lock = NSLock()
    private var trajectories: [ObjectIdentifier: Slot<[[FlightTrajectorySample]]?>] = [:]
    private var routes: [ObjectIdentifier: Slot<[ReplayRouteSample]>] = [:]

    private static let capacity = 8

    #if DEBUG
    /// Counts real decodes so tests can pin cache behaviour instead of timing
    /// it. Guarded by `lock` like the maps it describes.
    private var _decodeCount = 0
    var decodeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _decodeCount
    }

    func resetDecodeCount() {
        lock.lock()
        _decodeCount = 0
        lock.unlock()
    }
    #endif

    func trajectory(
        for entry: LogbookEntry,
        decode: () -> [[FlightTrajectorySample]]?
    ) -> [[FlightTrajectorySample]]? {
        let key = ObjectIdentifier(entry)
        let source = entry.trajectorySamplesData

        lock.lock()
        if let cached = trajectories[key], cached.source == source {
            lock.unlock()
            return cached.value
        }
        lock.unlock()

        let value = decode()

        lock.lock()
        #if DEBUG
        _decodeCount += 1
        #endif
        if trajectories.count >= Self.capacity { trajectories.removeAll(keepingCapacity: true) }
        trajectories[key] = Slot(source: source, value: value)
        lock.unlock()
        return value
    }

    func routeSamples(for entry: LogbookEntry) -> [ReplayRouteSample] {
        let key = ObjectIdentifier(entry)
        let source = entry.routeSamplesData

        lock.lock()
        if let cached = routes[key], cached.source == source {
            lock.unlock()
            return cached.value
        }
        lock.unlock()

        let value = entry.routeSamples

        lock.lock()
        #if DEBUG
        _decodeCount += 1
        #endif
        if routes.count >= Self.capacity { routes.removeAll(keepingCapacity: true) }
        routes[key] = Slot(source: source, value: value)
        lock.unlock()
        return value
    }
}

#if DEBUG
extension FlightDataAPI {
    /// Test-only window onto the memo, so cache behaviour can be asserted
    /// directly rather than inferred from a wall clock on a shared machine.
    var archiveDecodeCount: Int { archives.decodeCount }
    func resetArchiveDecodeCount() { archives.resetDecodeCount() }
}
#endif
