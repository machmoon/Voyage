import Foundation
import CoreLocation
import simd

// MARK: - Public renderer contract

/// Phase boundaries for one leg. The production schedule keeps low-altitude
/// motion at a believable rate while `shortFlights` preserves Voyage's fast QA
/// tour. Every value is expressed as elapsed seconds from the start of the leg.
struct FlightPhaseSchedule: Equatable, Codable {
    let legDuration: TimeInterval
    let takeoffEnd: TimeInterval
    let climbEnd: TimeInterval
    let descentStart: TimeInterval
    let landingStart: TimeInterval

    var legEnd: TimeInterval { legDuration }
    var takeoffDuration: TimeInterval { takeoffEnd }
    var climbDuration: TimeInterval { max(0, climbEnd - takeoffEnd) }
    var cruiseDuration: TimeInterval { max(0, descentStart - climbEnd) }
    var descentDuration: TimeInterval { max(0, landingStart - descentStart) }
    var landingDuration: TimeInterval { max(0, legEnd - landingStart) }
    /// Elapsed leg time at which the nose begins its smooth rotation.
    var rotationStart: TimeInterval { takeoffEnd * 0.68 }

    static func make(legDuration rawDuration: TimeInterval,
                     aircraft: AircraftProfile,
                     shortFlights: Bool) -> FlightPhaseSchedule {
        let duration = max(0.1, rawDuration)

        if shortFlights {
            // These are the existing QA boundaries. The clamps match
            // FlightSession's behavior for synthetic, very short unit-test legs.
            let takeoffEnd = min(5, duration * 0.15)
            let climbEnd = min(16, max(takeoffEnd + 0.01, duration * 0.35))
            let landingStart = max(climbEnd, duration - 15)
            let descentStart = max(
                climbEnd,
                min(landingStart, duration - min(180, duration * 0.45))
            )
            return FlightPhaseSchedule(
                legDuration: duration,
                takeoffEnd: takeoffEnd,
                climbEnd: climbEnd,
                descentStart: descentStart,
                landingStart: landingStart
            )
        }

        let roll: TimeInterval
        switch aircraft {
        case .voyageClassic: roll = 30
        case .boeing737800: roll = 35
        case .airbusA320neo: roll = 33
        }

        let climb = min(20 * 60, max(8 * 60, duration * 0.18))
        let descent = min(25 * 60, max(10 * 60, duration * 0.22))
        let landing: TimeInterval = 30
        let minimumCruise = min(90, max(1, duration * 0.04))
        let requested = roll + climb + descent + landing + minimumCruise

        // Catalog legs all fit the requested schedule. This proportional path
        // exists for previews/tests that deliberately create tiny legs.
        let scale = requested > duration ? max(0.001, duration / requested) : 1
        let scaledRoll = roll * scale
        let scaledClimb = climb * scale
        let scaledDescent = descent * scale
        let scaledLanding = landing * scale

        return FlightPhaseSchedule(
            legDuration: duration,
            takeoffEnd: scaledRoll,
            climbEnd: scaledRoll + scaledClimb,
            descentStart: max(scaledRoll + scaledClimb, duration - scaledDescent - scaledLanding),
            landingStart: max(scaledRoll + scaledClimb, duration - scaledLanding)
        )
    }

    func phase(at rawElapsed: TimeInterval) -> LegPhase {
        let elapsed = min(legEnd, max(0, rawElapsed))
        if elapsed < takeoffEnd { return .takeoffRoll }
        if elapsed < climbEnd { return .climb }
        if elapsed < descentStart { return .cruise }
        if elapsed < landingStart { return .descent }
        return .landing
    }

    /// Normalized progress inside the phase containing `elapsed`.
    func progress(at rawElapsed: TimeInterval) -> Double {
        let elapsed = min(legEnd, max(0, rawElapsed))
        let bounds: (TimeInterval, TimeInterval)
        switch phase(at: elapsed) {
        case .takeoffRoll: bounds = (0, takeoffEnd)
        case .climb: bounds = (takeoffEnd, climbEnd)
        case .cruise: bounds = (climbEnd, descentStart)
        case .descent: bounds = (descentStart, landingStart)
        case .landing: bounds = (landingStart, legEnd)
        }
        guard bounds.1 > bounds.0 else { return 1 }
        return min(1, max(0, (elapsed - bounds.0) / (bounds.1 - bounds.0)))
    }
}

/// A WGS-84 point used in authored runway/corridor data and persistence.
struct FlightGeodeticPoint: Equatable, Codable {
    let latitude: Double
    let longitude: Double
    let altitudeMeters: Double

    init(latitude: Double, longitude: Double, altitudeMeters: Double = 0) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitudeMeters = altitudeMeters
    }

    init(coordinate: CLLocationCoordinate2D, altitudeMeters: Double = 0) {
        self.init(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            altitudeMeters: altitudeMeters
        )
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// One usable runway direction. `threshold` is where the takeoff roll or
/// landing flare begins; `oppositeThreshold` is the rollout direction.
struct RunwayProfile: Identifiable, Equatable, Codable {
    let airportCode: String
    let designator: String
    let threshold: FlightGeodeticPoint
    let oppositeThreshold: FlightGeodeticPoint
    let elevationMeters: Double
    let usableLengthMeters: Double
    let defaultPriority: Int

    var id: String { "\(airportCode)-\(designator)" }
    var trueHeadingDegrees: Double {
        GreatCircle.bearing(from: threshold.coordinate, to: oppositeThreshold.coordinate)
    }

    func point(along fraction: Double, heightAboveRunwayMeters: Double = 0) -> FlightGeodeticPoint {
        let value = min(1, max(0, fraction))
        let coordinate = GreatCircle.point(
            from: threshold.coordinate,
            to: oppositeThreshold.coordinate,
            fraction: value
        )
        let runwayAltitude = threshold.altitudeMeters
            + (oppositeThreshold.altitudeMeters - threshold.altitudeMeters) * value
        return FlightGeodeticPoint(
            coordinate: coordinate,
            altitudeMeters: runwayAltitude + heightAboveRunwayMeters
        )
    }
}

struct FlightPathControlPoint: Equatable, Codable {
    let point: FlightGeodeticPoint
    /// Human-readable role for replay diagnostics and fixture review.
    let role: String
}

/// Airport-local control points selected once when the trajectory is built.
/// They intentionally describe representative operations, not a live clearance.
struct AirportCorridor: Identifiable, Equatable, Codable {
    enum Operation: String, Equatable, Codable {
        case departure
        case arrival
    }

    let id: String
    let airportCode: String
    let runwayID: String
    let operation: Operation
    let controlPoints: [FlightPathControlPoint]
}

/// Weather frozen before departure. Supplying this immutable value makes live
/// rendering, screenshots, and replay choose identical runways and atmosphere.
struct FlightEnvironmentSnapshot: Equatable, Codable {
    let frozenAt: Date
    let departureWeather: WeatherSnapshot?
    let arrivalWeather: WeatherSnapshot?
    let routeWeather: [WeatherSnapshot]

    init(frozenAt: Date,
         departureWeather: WeatherSnapshot? = nil,
         arrivalWeather: WeatherSnapshot? = nil,
         routeWeather: [WeatherSnapshot] = []) {
        self.frozenAt = frozenAt
        self.departureWeather = departureWeather
        self.arrivalWeather = arrivalWeather
        self.routeWeather = routeWeather
    }

    static func fallback(for leg: FlightLeg, frozenAt: Date) -> FlightEnvironmentSnapshot {
        func clear(_ airport: Airport) -> WeatherSnapshot {
            WeatherSnapshot(
                airportCode: airport.code,
                observedAt: frozenAt,
                condition: .clear,
                windDirectionDegrees: nil,
                windSpeedKnots: nil,
                visibilityMiles: 10,
                cloudBaseFeet: nil,
                temperatureCelsius: nil,
                source: "deterministic on-device fallback"
            )
        }
        return FlightEnvironmentSnapshot(
            frozenAt: frozenAt,
            departureWeather: clear(leg.origin),
            arrivalWeather: clear(leg.destination)
        )
    }

    func weather(at rawRouteProgress: Double) -> WeatherSnapshot? {
        let progress = min(1, max(0, rawRouteProgress))
        if progress <= 0.1 { return departureWeather ?? routeWeather.first ?? arrivalWeather }
        if progress >= 0.9 { return arrivalWeather ?? routeWeather.last ?? departureWeather }
        guard !routeWeather.isEmpty else {
            return progress < 0.5
                ? (departureWeather ?? arrivalWeather)
                : (arrivalWeather ?? departureWeather)
        }
        let routeProgress = (progress - 0.1) / 0.8
        let index = Int((routeProgress * Double(routeWeather.count - 1)).rounded())
        return routeWeather[min(routeWeather.count - 1, max(0, index))]
    }
}

/// Aircraft reference pose at one deterministic trajectory instant.
struct AircraftPose: Equatable {
    let coordinate: CLLocationCoordinate2D
    let altitudeMeters: Double
    let courseDegrees: Double
    let pitchDegrees: Double
    let bankDegrees: Double
    let groundSpeedMetersPerSecond: Double

    var altitudeFeet: Double { altitudeMeters * 3.280_839_895 }

    /// Heading, pitch, and roll composed in aircraft order. Renderers that use
    /// Euler camera controls should consume the degree fields instead.
    var orientation: simd_quatd {
        let yaw = simd_quatd(
            angle: -courseDegrees.radians,
            axis: SIMD3<Double>(0, 1, 0)
        )
        let pitch = simd_quatd(
            angle: pitchDegrees.radians,
            axis: SIMD3<Double>(1, 0, 0)
        )
        let roll = simd_quatd(
            angle: -bankDegrees.radians,
            axis: SIMD3<Double>(0, 0, 1)
        )
        return simd_normalize(yaw * pitch * roll)
    }

    static func == (lhs: AircraftPose, rhs: AircraftPose) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.altitudeMeters == rhs.altitudeMeters
            && lhs.courseDegrees == rhs.courseDegrees
            && lhs.pitchDegrees == rhs.pitchDegrees
            && lhs.bankDegrees == rhs.bankDegrees
            && lhs.groundSpeedMetersPerSecond == rhs.groundSpeedMetersPerSecond
    }
}

/// Renderer-independent passenger camera.
struct PassengerCameraPose: Equatable {
    let coordinate: CLLocationCoordinate2D
    let altitudeMeters: Double
    let headingDegrees: Double
    /// Elevation relative to the local horizon: 0° is level and negative is
    /// down. A Google orbit camera converts this to `tilt = 90 + pitchDegrees`.
    let pitchDegrees: Double
    let rollDegrees: Double
    let rangeMeters: Double
    /// Vertical field of view. Renderers with a non-square viewport derive
    /// their horizontal field of view from this value and the viewport aspect.
    let fieldOfViewDegrees: Double
    let side: WindowSide

    func horizontalFieldOfViewDegrees(forAspectRatio aspectRatio: Double) -> Double {
        let safeAspectRatio = max(0.001, abs(aspectRatio))
        let verticalRadians = min(179, max(0.001, fieldOfViewDegrees)).radians
        return (2 * atan(tan(verticalRadians / 2) * safeAspectRatio)).degrees
    }

    /// Target for orbit-style map cameras whose coordinate describes the point
    /// being viewed rather than the physical camera location.
    var lookAtCoordinate: CLLocationCoordinate2D {
        FlightGeodesy.offset(
            from: FlightGeodeticPoint(
                coordinate: coordinate,
                altitudeMeters: altitudeMeters
            ),
            eastMeters: sin(headingDegrees.radians) * cos(pitchDegrees.radians) * rangeMeters,
            northMeters: cos(headingDegrees.radians) * cos(pitchDegrees.radians) * rangeMeters,
            upMeters: sin(pitchDegrees.radians) * rangeMeters
        ).coordinate
    }

    var lookAtAltitudeMeters: Double {
        altitudeMeters + sin(pitchDegrees.radians) * rangeMeters
    }

    static func == (lhs: PassengerCameraPose, rhs: PassengerCameraPose) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.altitudeMeters == rhs.altitudeMeters
            && lhs.headingDegrees == rhs.headingDegrees
            && lhs.pitchDegrees == rhs.pitchDegrees
            && lhs.rollDegrees == rhs.rollDegrees
            && lhs.rangeMeters == rhs.rangeMeters
            && lhs.fieldOfViewDegrees == rhs.fieldOfViewDegrees
            && lhs.side == rhs.side
    }
}

struct FlightVisualState: Equatable {
    let elapsed: TimeInterval
    let phase: LegPhase
    let phaseProgress: Double
    let routeProgress: Double
    let aircraft: AircraftPose
    let camera: PassengerCameraPose
    let departureRunwayID: String
    let arrivalRunwayID: String
    let environment: FlightEnvironmentSnapshot
}

/// Compact persisted samples for deterministic replay and backwards-compatible
/// logbook migration. The full spline is regenerated from its catalog revision.
struct FlightTrajectorySample: Equatable, Codable {
    let elapsed: TimeInterval
    let latitude: Double
    let longitude: Double
    let altitudeMeters: Double
    let courseDegrees: Double
    let pitchDegrees: Double
    let bankDegrees: Double
    let routeProgress: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Deterministic engine

enum FlightVisualEngine {
    static let trajectoryRevision = "real-world-twin-2"

    static func trajectory(for leg: FlightLeg,
                           aircraft: AircraftProfile,
                           environment: FlightEnvironmentSnapshot,
                           shortFlights: Bool) -> FlightTrajectory {
        FlightTrajectory(
            leg: leg,
            aircraft: aircraft,
            environment: environment,
            shortFlights: shortFlights
        )
    }

    static func runways(for airport: Airport) -> [RunwayProfile] {
        FlightRunwayCatalog.runwaysByAirport[airport.code] ?? []
    }

    /// Stable runway choice from immutable inputs. Wind is meteorological
    /// (direction it comes from); route alignment and catalog priority break ties.
    static func selectRunway(for airport: Airport,
                             routeCourseDegrees: Double,
                             weather: WeatherSnapshot?,
                             aircraft: AircraftProfile) -> RunwayProfile {
        let candidates = runways(for: airport)
        precondition(!candidates.isEmpty, "Missing runway data for \(airport.code)")

        let requiredLength: Double
        switch aircraft {
        case .voyageClassic: requiredLength = 1_800
        case .boeing737800: requiredLength = 2_300
        case .airbusA320neo: requiredLength = 2_100
        }

        func score(_ runway: RunwayProfile) -> Double {
            let routeDelta = abs(shortestAngle(
                from: runway.trueHeadingDegrees,
                to: routeCourseDegrees
            ))
            let lengthPenalty = runway.usableLengthMeters < requiredLength
                ? -20_000 - (requiredLength - runway.usableLengthMeters) * 10
                : min(12, (runway.usableLengthMeters - requiredLength) / 100)
            let priority = Double(runway.defaultPriority) * 1.4

            guard let direction = weather?.windDirectionDegrees,
                  let speed = weather?.windSpeedKnots,
                  speed > 1 else {
                return lengthPenalty + priority - routeDelta * 0.18
            }
            let windDelta = shortestAngle(
                from: runway.trueHeadingDegrees,
                to: Double(direction)
            ).radians
            let headwind = Double(speed) * cos(windDelta)
            let crosswind = abs(Double(speed) * sin(windDelta))
            return lengthPenalty + priority + headwind * 7 - crosswind * 1.8 - routeDelta * 0.08
        }

        return candidates.enumerated().max { lhs, rhs in
            let lhsScore = score(lhs.element)
            let rhsScore = score(rhs.element)
            if abs(lhsScore - rhsScore) > 0.000_001 { return lhsScore < rhsScore }
            // Catalog order is a final deterministic tiebreaker.
            return lhs.offset > rhs.offset
        }!.element
    }

    fileprivate static func shortestAngle(from: Double, to: Double) -> Double {
        var delta = (to - from).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }
}

struct FlightTrajectory {
    let leg: FlightLeg
    let aircraft: AircraftProfile
    let environment: FlightEnvironmentSnapshot
    let schedule: FlightPhaseSchedule
    let departureRunway: RunwayProfile
    let arrivalRunway: RunwayProfile
    let departureCorridor: AirportCorridor
    let arrivalCorridor: AirportCorridor

    private let path: FlightSplinePath
    private let distanceTiming: FlightDistanceTiming

    init(leg: FlightLeg,
         aircraft: AircraftProfile,
         environment: FlightEnvironmentSnapshot,
         shortFlights: Bool) {
        let schedule = FlightPhaseSchedule.make(
            legDuration: leg.duration,
            aircraft: aircraft,
            shortFlights: shortFlights
        )
        let departureCourse = GreatCircle.bearing(
            from: leg.origin.coordinate,
            to: leg.destination.coordinate
        )
        let arrivalCourse = GreatCircle.bearing(
            from: GreatCircle.point(
                from: leg.origin.coordinate,
                to: leg.destination.coordinate,
                fraction: 0.98
            ),
            to: leg.destination.coordinate
        )

        let departureRunway = FlightVisualEngine.selectRunway(
            for: leg.origin,
            routeCourseDegrees: departureCourse,
            weather: environment.departureWeather,
            aircraft: aircraft
        )
        let arrivalRunway = FlightVisualEngine.selectRunway(
            for: leg.destination,
            routeCourseDegrees: arrivalCourse,
            weather: environment.arrivalWeather,
            aircraft: aircraft
        )

        let departureCorridor = Self.makeDepartureCorridor(
            runway: departureRunway,
            routeCourse: departureCourse
        )
        let arrivalCorridor = Self.makeArrivalCorridor(runway: arrivalRunway)
        let built = Self.buildPath(
            leg: leg,
            aircraft: aircraft,
            departureRunway: departureRunway,
            arrivalRunway: arrivalRunway,
            departureCorridor: departureCorridor,
            arrivalCorridor: arrivalCorridor,
            schedule: schedule,
            shortFlights: shortFlights
        )
        let path = FlightSplinePath(
            points: built.points,
            tangentOverrides: built.tangentOverrides
        )
        let boundaryDistances = [
            0,
            path.knotDistance(at: built.takeoffEndIndex),
            path.knotDistance(at: built.climbEndIndex),
            path.knotDistance(at: built.descentStartIndex),
            path.knotDistance(at: built.landingStartIndex),
            path.totalDistanceMeters
        ]
        let boundaryTimes = [
            0,
            schedule.takeoffEnd,
            schedule.climbEnd,
            schedule.descentStart,
            schedule.landingStart,
            schedule.legEnd
        ]
        let desiredSpeeds = [
            0,
            aircraft.rotationKnots * 0.514_444,
            235,
            225,
            aircraft.flightTwinTouchdownSpeedMetersPerSecond,
            0
        ]

        self.leg = leg
        self.aircraft = aircraft
        self.environment = environment
        self.schedule = schedule
        self.departureRunway = departureRunway
        self.arrivalRunway = arrivalRunway
        self.departureCorridor = departureCorridor
        self.arrivalCorridor = arrivalCorridor
        self.path = path
        self.distanceTiming = FlightDistanceTiming(
            times: boundaryTimes,
            distances: boundaryDistances,
            desiredSpeeds: desiredSpeeds
        )
    }

    func state(at rawElapsed: TimeInterval,
               seat: String,
               reduceMotion: Bool = false) -> FlightVisualState {
        let elapsed = min(schedule.legEnd, max(0, rawElapsed))
        let distanceSample = distanceTiming.sample(at: elapsed)
        let routeProgress = min(
            1,
            max(0, distanceSample.distanceMeters / max(1, path.totalDistanceMeters))
        )
        let pathSample = path.sample(at: distanceSample.distanceMeters)
        let point = FlightGeodesy.geodetic(fromECEF: pathSample.ecef)
        let localTangent = FlightGeodesy.enuVector(
            fromECEFVector: pathSample.tangent,
            at: point
        )
        let horizontal = hypot(localTangent.x, localTangent.y)
        let course = FlightVisualEngine.normalizedDegrees(
            atan2(localTangent.x, localTangent.y).degrees
        )
        let flightPathPitch = atan2(localTangent.z, max(0.000_001, horizontal)).degrees
        let phase = schedule.phase(at: elapsed)
        let phaseProgress = schedule.progress(at: elapsed)
        let pitch = aircraftPitch(
            flightPathPitch: flightPathPitch,
            phase: phase,
            phaseProgress: phaseProgress,
            elapsed: elapsed
        )
        let bank = bankDegrees(
            atDistance: distanceSample.distanceMeters,
            speed: distanceSample.speedMetersPerSecond,
            reduceMotion: reduceMotion
        )
        let aircraftPose = AircraftPose(
            coordinate: point.coordinate,
            altitudeMeters: point.altitudeMeters,
            courseDegrees: course,
            pitchDegrees: reduceMotion ? min(8, max(-5, pitch)) : min(12, max(-8, pitch)),
            bankDegrees: bank,
            groundSpeedMetersPerSecond: max(0, distanceSample.speedMetersPerSecond)
        )
        let camera = passengerCamera(
            aircraftPose: aircraftPose,
            seat: seat,
            routeProgress: routeProgress,
            reduceMotion: reduceMotion
        )
        return FlightVisualState(
            elapsed: elapsed,
            phase: phase,
            phaseProgress: phaseProgress,
            routeProgress: routeProgress,
            aircraft: aircraftPose,
            camera: camera,
            departureRunwayID: departureRunway.id,
            arrivalRunwayID: arrivalRunway.id,
            environment: environment
        )
    }

    func replaySamples(count requestedCount: Int = 96,
                       seat: String) -> [FlightTrajectorySample] {
        let count = max(2, requestedCount)
        let boundaries = [
            0,
            schedule.rotationStart,
            schedule.takeoffEnd,
            schedule.climbEnd,
            schedule.descentStart,
            schedule.landingStart,
            schedule.legEnd,
        ]
        let segments = zip(boundaries, boundaries.dropFirst()).filter { $0.1 > $0.0 }

        let elapsedValues: [TimeInterval]
        if count < segments.count + 1 {
            elapsedValues = (0..<count).map {
                schedule.legEnd * Double($0) / Double(count - 1)
            }
        } else {
            // Dense runway samples preserve acceleration and rollout even on a
            // six-hour leg; terminal corridors receive the next-highest share,
            // while steady cruise is deliberately sparse.
            let desiredIntervals = segments.enumerated().map { index, segment -> Double in
                let duration = segment.1 - segment.0
                switch index {
                case 0, 1: return min(40, max(1, ceil(duration / 1)))
                case 2: return min(48, max(1, ceil(duration / 20)))
                case 3: return min(64, max(1, ceil(duration / 300)))
                case 4: return min(48, max(1, ceil(duration / 30)))
                default: return min(35, max(1, ceil(duration / 1)))
                }
            }
            var intervals = Array(repeating: 1, count: segments.count)
            let remaining = count - 1 - intervals.count
            if remaining > 0 {
                let weights = desiredIntervals.map { max(0, $0 - 1) }
                let weightTotal = max(1, weights.reduce(0, +))
                let exactShares = weights.map { Double(remaining) * $0 / weightTotal }
                for index in intervals.indices {
                    intervals[index] += Int(floor(exactShares[index]))
                }
                var unallocated = count - 1 - intervals.reduce(0, +)
                let priority = intervals.indices.sorted {
                    let lhsRemainder = exactShares[$0] - floor(exactShares[$0])
                    let rhsRemainder = exactShares[$1] - floor(exactShares[$1])
                    if lhsRemainder == rhsRemainder { return $0 < $1 }
                    return lhsRemainder > rhsRemainder
                }
                var priorityIndex = 0
                while unallocated > 0 {
                    intervals[priority[priorityIndex % priority.count]] += 1
                    priorityIndex += 1
                    unallocated -= 1
                }
            }

            var values = [segments[0].0]
            for (index, segment) in segments.enumerated() {
                for step in 1...intervals[index] {
                    let amount = Double(step) / Double(intervals[index])
                    values.append(segment.0 + (segment.1 - segment.0) * amount)
                }
            }
            elapsedValues = values
        }

        return elapsedValues.map { elapsed in
            let state = state(at: elapsed, seat: seat)
            return FlightTrajectorySample(
                elapsed: elapsed,
                latitude: state.aircraft.coordinate.latitude,
                longitude: state.aircraft.coordinate.longitude,
                altitudeMeters: state.aircraft.altitudeMeters,
                courseDegrees: state.aircraft.courseDegrees,
                pitchDegrees: state.aircraft.pitchDegrees,
                bankDegrees: state.aircraft.bankDegrees,
                routeProgress: state.routeProgress
            )
        }
    }

    private func bankDegrees(atDistance distance: Double,
                             speed: Double,
                             reduceMotion: Bool) -> Double {
        guard speed > 35 else { return 0 }
        let lookDistance = min(8_000, max(600, speed * 8))
        let beforeDistance = max(0, distance - lookDistance)
        let afterDistance = min(path.totalDistanceMeters, distance + lookDistance)
        guard afterDistance - beforeDistance > 10 else { return 0 }

        let before = path.sample(at: beforeDistance)
        let after = path.sample(at: afterDistance)
        let beforePoint = FlightGeodesy.geodetic(fromECEF: before.ecef)
        let afterPoint = FlightGeodesy.geodetic(fromECEF: after.ecef)
        let beforeENU = FlightGeodesy.enuVector(fromECEFVector: before.tangent, at: beforePoint)
        let afterENU = FlightGeodesy.enuVector(fromECEFVector: after.tangent, at: afterPoint)
        let beforeCourse = atan2(beforeENU.x, beforeENU.y).degrees
        let afterCourse = atan2(afterENU.x, afterENU.y).degrees
        let turn = FlightVisualEngine.shortestAngle(from: beforeCourse, to: afterCourse).radians
        let curvature = turn / (afterDistance - beforeDistance)
        let coordinatedBank = atan(speed * speed * curvature / 9.806_65).degrees
        let limit = reduceMotion ? 5.0 : 22.0
        return min(limit, max(-limit, coordinatedBank))
    }

    /// Flight-path angle supplies the baseline attitude. During rotation and
    /// flare, angle of attack is necessarily non-zero even before vertical
    /// speed changes, so a smooth aerodynamic offset supplies the familiar
    /// 11° nose rise without moving the camera below/above the runway surface.
    private func aircraftPitch(flightPathPitch: Double,
                               phase: LegPhase,
                               phaseProgress: Double,
                               elapsed: TimeInterval) -> Double {
        switch phase {
        case .takeoffRoll:
            let rotationSpan = max(0.000_001, schedule.takeoffEnd - schedule.rotationStart)
            let rotationProgress = (elapsed - schedule.rotationStart) / rotationSpan
            return flightPathPitch
                + (11 - flightPathPitch) * smoothstep(0, 1, rotationProgress)
        case .climb:
            let rotationBlend = 1 - smoothstep(0, 0.14, phaseProgress)
            return flightPathPitch + (11 - flightPathPitch) * rotationBlend
        case .cruise:
            return flightPathPitch
        case .descent:
            let flareBlend = smoothstep(0.9, 1, phaseProgress)
            return flightPathPitch + (3.5 - flightPathPitch) * flareBlend
        case .landing:
            let flareBlend = 1 - smoothstep(0, 0.22, phaseProgress)
            return flightPathPitch + (3.5 - flightPathPitch) * flareBlend
        }
    }

    private func smoothstep(_ lower: Double, _ upper: Double, _ value: Double) -> Double {
        let amount = min(1, max(0, (value - lower) / max(0.000_001, upper - lower)))
        return amount * amount * (3 - 2 * amount)
    }

    private func passengerCamera(aircraftPose: AircraftPose,
                                 seat: String,
                                 routeProgress: Double,
                                 reduceMotion: Bool) -> PassengerCameraPose {
        let side = WindowSide(seat: seat)
        let sideSign = side == .left ? -1.0 : 1.0
        let row = Int(seat.filter(\.isNumber)) ?? 8
        let forwardOffset = Double(8 - min(30, max(1, row))) * 0.79
        let lateralOffset = sideSign * 2.05

        let heading = aircraftPose.courseDegrees.radians
        let horizontalForward = SIMD3<Double>(sin(heading), cos(heading), 0)
        let horizontalRight = SIMD3<Double>(cos(heading), -sin(heading), 0)
        let worldUp = SIMD3<Double>(0, 0, 1)
        let pitch = aircraftPose.pitchDegrees.radians
        let bank = aircraftPose.bankDegrees.radians
        let bodyForward = horizontalForward * cos(pitch) + worldUp * sin(pitch)
        let pitchedUp = worldUp * cos(pitch) - horizontalForward * sin(pitch)
        let bodyRight = horizontalRight * cos(bank) - pitchedUp * sin(bank)
        let bodyUp = horizontalRight * sin(bank) + pitchedUp * cos(bank)

        // The eye is fixed to the airframe: row, side, and window height all
        // rotate with aircraft pitch and bank rather than remaining world-up.
        let eyeOffset = bodyForward * forwardOffset
            + bodyRight * lateralOffset
            + bodyUp * aircraft.windowHeight
        let cameraPoint = FlightGeodesy.offset(
            from: FlightGeodeticPoint(
                coordinate: aircraftPose.coordinate,
                altitudeMeters: aircraftPose.altitudeMeters
            ),
            eastMeters: eyeOffset.x,
            northMeters: eyeOffset.y,
            upMeters: eyeOffset.z
        )

        // Rotate the passenger's fixed side-and-slightly-down view through the
        // same aircraft body basis used for the eye position.
        let sideLook = 88.0.radians
        // Aimed just under the horizon rather than down at the ground: a
        // passenger looking out a window sees mostly sky and horizon, and the
        // steeper the look-down the more the view reads as an aerial map.
        // 2.5° is also where the provider tilt clamp (87.5°) sits, so anything
        // flatter than this is thrown away by the map camera anyway.
        let downLook = (reduceMotion ? 2.0 : 2.5).radians
        let localForward = cos(sideLook) * cos(downLook)
        let localRight = sideSign * sin(sideLook) * cos(downLook)
        let localUp = -sin(downLook)
        let view = simd_normalize(
            bodyForward * localForward + bodyRight * localRight + bodyUp * localUp
        )
        let cameraHeading = FlightVisualEngine.normalizedDegrees(atan2(view.x, view.y).degrees)
        let cameraPitch = atan2(view.z, hypot(view.x, view.y)).degrees

        // Orbit-style map cameras describe a point being viewed rather than
        // the physical eye position. Pick a slant range that reconstructs the
        // passenger's true height above the local airport reference. This is
        // ~20–30 m on a runway—not the old 2 km minimum that turned the
        // tarmac view into an aerial flyover. Interpolating the endpoint
        // elevations keeps both takeoff and touchdown exact and continuous.
        let referenceElevation = departureRunway.elevationMeters
            + (arrivalRunway.elevationMeters - departureRunway.elevationMeters) * routeProgress
        let heightAboveReference = max(
            aircraft.windowHeight,
            cameraPoint.altitudeMeters - referenceElevation
        )
        let providerTilt = min(87.5, max(0, 90 + cameraPitch))
        let verticalRangeFraction = max(0.043_619, cos(providerTilt.radians))
        let range = min(450_000, max(4, heightAboveReference / verticalRangeFraction))

        return PassengerCameraPose(
            coordinate: cameraPoint.coordinate,
            altitudeMeters: cameraPoint.altitudeMeters,
            headingDegrees: cameraHeading,
            pitchDegrees: cameraPitch,
            rollDegrees: reduceMotion ? aircraftPose.bankDegrees * 0.2 : aircraftPose.bankDegrees,
            rangeMeters: range,
            fieldOfViewDegrees: 64,
            side: side
        )
    }

    private struct BuiltPath {
        let points: [FlightGeodeticPoint]
        let tangentOverrides: [Int: SIMD3<Double>]
        let takeoffEndIndex: Int
        let climbEndIndex: Int
        let descentStartIndex: Int
        let landingStartIndex: Int
    }

    private static func buildPath(leg: FlightLeg,
                                  aircraft: AircraftProfile,
                                  departureRunway: RunwayProfile,
                                  arrivalRunway: RunwayProfile,
                                  departureCorridor: AirportCorridor,
                                  arrivalCorridor: AirportCorridor,
                                  schedule: FlightPhaseSchedule,
                                  shortFlights: Bool) -> BuiltPath {
        var points: [FlightGeodeticPoint] = []
        var tangentOverrides: [Int: SIMD3<Double>] = [:]
        func append(_ point: FlightGeodeticPoint, tangent: SIMD3<Double>? = nil) {
            if let tangent { tangentOverrides[points.count] = tangent }
            points.append(point)
        }
        func appendRunwayPoint(_ runway: RunwayProfile, fraction: Double) {
            let point = runway.point(along: fraction)
            append(point, tangent: runwayTangent(for: runway, at: point))
        }

        let rotationSpeed = aircraft.rotationKnots * 0.514_444
        let takeoffTravel = min(
            departureRunway.usableLengthMeters * 0.82,
            0.5 * rotationSpeed * schedule.takeoffDuration
        )
        let takeoffFraction = min(0.82, max(0.01, takeoffTravel / departureRunway.usableLengthMeters))

        // Start already aligned on the runway; there is intentionally no taxi.
        appendRunwayPoint(departureRunway, fraction: 0)
        appendRunwayPoint(departureRunway, fraction: takeoffFraction * 0.28)
        appendRunwayPoint(departureRunway, fraction: takeoffFraction * 0.62)
        appendRunwayPoint(departureRunway, fraction: takeoffFraction)
        let takeoffEndIndex = points.count - 1
        let liftoffTravel = min(360, max(180, takeoffTravel * 0.2))
        let liftoffFraction = min(
            0.94,
            takeoffFraction + liftoffTravel / departureRunway.usableLengthMeters
        )
        append(departureRunway.point(along: liftoffFraction, heightAboveRunwayMeters: 18))
        departureCorridor.controlPoints.forEach { append($0.point) }

        let routeDistance = max(1, leg.origin.location.distance(from: leg.destination.location))
        let climbTravel = shortFlights
            ? min(routeDistance * 0.16, max(15_000, schedule.climbDuration * 180))
            : min(routeDistance * 0.34, max(85_000, schedule.climbDuration * 205))
        let descentTravel = shortFlights
            ? min(routeDistance * 0.18, max(25_000, schedule.descentDuration * 190))
            : min(routeDistance * 0.34, max(110_000, schedule.descentDuration * 210))
        var departureFraction = min(0.38, climbTravel / routeDistance)
        var arrivalFraction = min(0.38, descentTravel / routeDistance)
        if departureFraction + arrivalFraction > 0.76 {
            let scale = 0.76 / (departureFraction + arrivalFraction)
            departureFraction *= scale
            arrivalFraction *= scale
        }

        let cruiseAltitude = 10_972.8 // FL360
        append(FlightGeodeticPoint(
            coordinate: GreatCircle.point(
                from: leg.origin.coordinate,
                to: leg.destination.coordinate,
                fraction: departureFraction
            ),
            altitudeMeters: cruiseAltitude
        ))
        let climbEndIndex = points.count - 1

        let descentFraction = max(departureFraction, 1 - arrivalFraction)
        let cruiseSpan = max(0, descentFraction - departureFraction)
        let cruisePointCount = max(10, min(72, Int(routeDistance / 80_000)))
        if cruiseSpan > 0.000_001 {
            for index in 1...cruisePointCount {
                let amount = Double(index) / Double(cruisePointCount)
                let fraction = departureFraction + cruiseSpan * amount
                append(FlightGeodeticPoint(
                    coordinate: GreatCircle.point(
                        from: leg.origin.coordinate,
                        to: leg.destination.coordinate,
                        fraction: fraction
                    ),
                    altitudeMeters: cruiseAltitude
                ))
            }
        }
        let descentStartIndex = points.count - 1

        arrivalCorridor.controlPoints.forEach { append($0.point) }
        appendRunwayPoint(arrivalRunway, fraction: 0)
        let landingStartIndex = points.count - 1
        let rolloutTravel = min(
            arrivalRunway.usableLengthMeters * 0.72,
            0.5 * aircraft.flightTwinTouchdownSpeedMetersPerSecond * schedule.landingDuration
        )
        let rolloutFraction = min(0.72, max(0.01, rolloutTravel / arrivalRunway.usableLengthMeters))
        appendRunwayPoint(arrivalRunway, fraction: rolloutFraction * 0.28)
        appendRunwayPoint(arrivalRunway, fraction: rolloutFraction * 0.64)
        appendRunwayPoint(arrivalRunway, fraction: rolloutFraction)

        return BuiltPath(
            points: points,
            tangentOverrides: tangentOverrides,
            takeoffEndIndex: takeoffEndIndex,
            climbEndIndex: climbEndIndex,
            descentStartIndex: descentStartIndex,
            landingStartIndex: landingStartIndex
        )
    }

    private static func runwayTangent(for runway: RunwayProfile,
                                      at point: FlightGeodeticPoint) -> SIMD3<Double> {
        let heading = runway.trueHeadingDegrees.radians
        let slope = (runway.oppositeThreshold.altitudeMeters - runway.threshold.altitudeMeters)
            / max(1, runway.usableLengthMeters)
        let forward = FlightGeodesy.offset(
            from: point,
            eastMeters: sin(heading),
            northMeters: cos(heading),
            upMeters: slope
        )
        return simd_normalize(FlightGeodesy.ecef(forward) - FlightGeodesy.ecef(point))
    }

    private static func makeDepartureCorridor(runway: RunwayProfile,
                                              routeCourse: Double) -> AirportCorridor {
        let heading = runway.trueHeadingDegrees
        let turn = FlightVisualEngine.shortestAngle(from: heading, to: routeCourse)
        let sfoScale = runway.airportCode == "SFO" ? 1.0 : 0.82
        let specs: [(Double, Double, Double, String)] = [
            (2_000, heading, 120, "runway extension"),
            (8_000, heading + turn * 0.16, 850, "initial climb"),
            (20_000 * sfoScale, heading + turn * 0.42, 2_400, "departure turn"),
            (42_000 * sfoScale, heading + turn * 0.72, 4_800, "terminal exit")
        ]
        let origin = runway.oppositeThreshold
        let controls = specs.map { distance, course, altitude, role in
            FlightPathControlPoint(
                point: FlightGeodesy.offset(
                    from: origin,
                    eastMeters: sin(course.radians) * distance,
                    northMeters: cos(course.radians) * distance,
                    upMeters: altitude - origin.altitudeMeters
                ),
                role: role
            )
        }
        return AirportCorridor(
            id: "\(runway.id)-departure-v1",
            airportCode: runway.airportCode,
            runwayID: runway.id,
            operation: .departure,
            controlPoints: controls
        )
    }

    private static func makeArrivalCorridor(runway: RunwayProfile) -> AirportCorridor {
        let reciprocal = runway.trueHeadingDegrees + 180
        let specs: [(Double, Double, String)] = [
            (65_000, 6_000, "terminal entry"),
            (32_000, 3_000, "approach capture"),
            (14_000, 1_250, "final approach"),
            (5_000, 360, "short final"),
            (1_300, 90, "flare setup")
        ]
        let controls = specs.map { distance, altitude, role in
            FlightPathControlPoint(
                point: FlightGeodesy.offset(
                    from: runway.threshold,
                    eastMeters: sin(reciprocal.radians) * distance,
                    northMeters: cos(reciprocal.radians) * distance,
                    upMeters: altitude - runway.threshold.altitudeMeters
                ),
                role: role
            )
        }
        return AirportCorridor(
            id: "\(runway.id)-arrival-v1",
            airportCode: runway.airportCode,
            runwayID: runway.id,
            operation: .arrival,
            controlPoints: controls
        )
    }
}

// MARK: - WGS-84 and spline math

enum FlightGeodesy {
    private static let semiMajorAxis = 6_378_137.0
    private static let flattening = 1.0 / 298.257_223_563
    private static let eccentricitySquared = flattening * (2 - flattening)

    static func ecef(_ point: FlightGeodeticPoint) -> SIMD3<Double> {
        let latitude = point.latitude.radians
        let longitude = point.longitude.radians
        let sinLatitude = sin(latitude)
        let cosLatitude = cos(latitude)
        let radius = semiMajorAxis / sqrt(1 - eccentricitySquared * sinLatitude * sinLatitude)
        return SIMD3<Double>(
            (radius + point.altitudeMeters) * cosLatitude * cos(longitude),
            (radius + point.altitudeMeters) * cosLatitude * sin(longitude),
            (radius * (1 - eccentricitySquared) + point.altitudeMeters) * sinLatitude
        )
    }

    static func geodetic(fromECEF value: SIMD3<Double>) -> FlightGeodeticPoint {
        let longitude = atan2(value.y, value.x)
        let horizontal = hypot(value.x, value.y)
        var latitude = atan2(value.z, horizontal * (1 - eccentricitySquared))
        var altitude = 0.0
        for _ in 0..<8 {
            let sinLatitude = sin(latitude)
            let radius = semiMajorAxis / sqrt(1 - eccentricitySquared * sinLatitude * sinLatitude)
            altitude = horizontal / max(1e-9, cos(latitude)) - radius
            latitude = atan2(
                value.z,
                horizontal * (1 - eccentricitySquared * radius / (radius + altitude))
            )
        }
        return FlightGeodeticPoint(
            latitude: latitude.degrees,
            longitude: longitude.degrees,
            altitudeMeters: altitude
        )
    }

    static func offset(from origin: FlightGeodeticPoint,
                       eastMeters: Double,
                       northMeters: Double,
                       upMeters: Double) -> FlightGeodeticPoint {
        let latitude = origin.latitude.radians
        let longitude = origin.longitude.radians
        let east = SIMD3<Double>(-sin(longitude), cos(longitude), 0)
        let north = SIMD3<Double>(
            -sin(latitude) * cos(longitude),
            -sin(latitude) * sin(longitude),
            cos(latitude)
        )
        let up = SIMD3<Double>(
            cos(latitude) * cos(longitude),
            cos(latitude) * sin(longitude),
            sin(latitude)
        )
        return geodetic(
            fromECEF: ecef(origin) + east * eastMeters + north * northMeters + up * upMeters
        )
    }

    static func enu(of point: FlightGeodeticPoint,
                    relativeTo origin: FlightGeodeticPoint) -> SIMD3<Double> {
        enuVector(fromECEFVector: ecef(point) - ecef(origin), at: origin)
    }

    static func enuVector(fromECEFVector value: SIMD3<Double>,
                          at origin: FlightGeodeticPoint) -> SIMD3<Double> {
        let latitude = origin.latitude.radians
        let longitude = origin.longitude.radians
        let east = SIMD3<Double>(-sin(longitude), cos(longitude), 0)
        let north = SIMD3<Double>(
            -sin(latitude) * cos(longitude),
            -sin(latitude) * sin(longitude),
            cos(latitude)
        )
        let up = SIMD3<Double>(
            cos(latitude) * cos(longitude),
            cos(latitude) * sin(longitude),
            sin(latitude)
        )
        return SIMD3<Double>(simd_dot(value, east), simd_dot(value, north), simd_dot(value, up))
    }
}

private struct FlightSplinePath {
    struct Sample {
        let ecef: SIMD3<Double>
        let tangent: SIMD3<Double>
    }

    private struct Segment {
        let start: SIMD3<Double>
        let end: SIMD3<Double>
        let startTangent: SIMD3<Double>
        let endTangent: SIMD3<Double>
        let chordSpan: Double
        let arcDistances: [Double]

        var length: Double { arcDistances.last ?? 0 }

        init(start: SIMD3<Double>,
             end: SIMD3<Double>,
             startTangent: SIMD3<Double>,
             endTangent: SIMD3<Double>,
             chordSpan: Double) {
            self.start = start
            self.end = end
            self.startTangent = startTangent
            self.endTangent = endTangent
            self.chordSpan = chordSpan

            let resolution = 128
            var distances = [0.0]
            for index in 1...resolution {
                let lower = Double(index - 1) / Double(resolution)
                let upper = Double(index) / Double(resolution)
                let middle = (lower + upper) * 0.5
                let lowerSpeed = simd_length(Self.derivative(
                    start: start,
                    end: end,
                    startTangent: startTangent,
                    endTangent: endTangent,
                    chordSpan: chordSpan,
                    t: lower
                ))
                let middleSpeed = simd_length(Self.derivative(
                    start: start,
                    end: end,
                    startTangent: startTangent,
                    endTangent: endTangent,
                    chordSpan: chordSpan,
                    t: middle
                ))
                let upperSpeed = simd_length(Self.derivative(
                    start: start,
                    end: end,
                    startTangent: startTangent,
                    endTangent: endTangent,
                    chordSpan: chordSpan,
                    t: upper
                ))
                let intervalLength = (upper - lower)
                    * (lowerSpeed + 4 * middleSpeed + upperSpeed) / 6
                distances.append(distances.last! + intervalLength)
            }
            self.arcDistances = distances
        }

        func sample(atArcDistance rawDistance: Double) -> Sample {
            let distance = min(length, max(0, rawDistance))
            let t = parameter(atArcDistance: distance)
            let derivative = Self.derivative(
                start: start,
                end: end,
                startTangent: startTangent,
                endTangent: endTangent,
                chordSpan: chordSpan,
                t: t
            )
            let tangent = simd_length_squared(derivative) > 1e-18
                ? simd_normalize(derivative)
                : startTangent
            return Sample(
                ecef: Self.position(
                    start: start,
                    end: end,
                    startTangent: startTangent,
                    endTangent: endTangent,
                    chordSpan: chordSpan,
                    t: t
                ),
                tangent: tangent
            )
        }

        private func parameter(atArcDistance distance: Double) -> Double {
            if distance <= 0 { return 0 }
            if distance >= length { return 1 }
            var low = 0
            var high = arcDistances.count - 1
            while low + 1 < high {
                let middle = (low + high) / 2
                if arcDistances[middle] <= distance { low = middle } else { high = middle }
            }
            let resolution = Double(arcDistances.count - 1)
            let lowerT = Double(low) / resolution
            let upperT = Double(high) / resolution
            let arcSpan = max(1e-12, arcDistances[high] - arcDistances[low])
            var t = lowerT
                + (upperT - lowerT) * (distance - arcDistances[low]) / arcSpan

            // Two bounded Newton refinements invert the numerical arc table to
            // sub-meter precision without ever leaving its monotone bracket.
            for _ in 0..<2 {
                let partial = arcLength(from: lowerT, to: t)
                let error = arcDistances[low] + partial - distance
                let speed = max(1e-9, simd_length(Self.derivative(
                    start: start,
                    end: end,
                    startTangent: startTangent,
                    endTangent: endTangent,
                    chordSpan: chordSpan,
                    t: t
                )))
                t = min(upperT, max(lowerT, t - error / speed))
            }
            return t
        }

        private func arcLength(from lower: Double, to upper: Double) -> Double {
            guard upper > lower else { return 0 }
            let middle = (lower + upper) * 0.5
            let speeds = [lower, middle, upper].map { value in
                simd_length(Self.derivative(
                    start: start,
                    end: end,
                    startTangent: startTangent,
                    endTangent: endTangent,
                    chordSpan: chordSpan,
                    t: value
                ))
            }
            return (upper - lower) * (speeds[0] + 4 * speeds[1] + speeds[2]) / 6
        }

        private static func position(start: SIMD3<Double>,
                                     end: SIMD3<Double>,
                                     startTangent: SIMD3<Double>,
                                     endTangent: SIMD3<Double>,
                                     chordSpan: Double,
                                     t: Double) -> SIMD3<Double> {
            let t2 = t * t
            let t3 = t2 * t
            let h00 = 2 * t3 - 3 * t2 + 1
            let h10 = t3 - 2 * t2 + t
            let h01 = -2 * t3 + 3 * t2
            let h11 = t3 - t2
            return start * h00
                + startTangent * (chordSpan * h10)
                + end * h01
                + endTangent * (chordSpan * h11)
        }

        private static func derivative(start: SIMD3<Double>,
                                       end: SIMD3<Double>,
                                       startTangent: SIMD3<Double>,
                                       endTangent: SIMD3<Double>,
                                       chordSpan: Double,
                                       t: Double) -> SIMD3<Double> {
            let t2 = t * t
            return start * (6 * t2 - 6 * t)
                + startTangent * (chordSpan * (3 * t2 - 4 * t + 1))
                + end * (-6 * t2 + 6 * t)
                + endTangent * (chordSpan * (3 * t2 - 2 * t))
        }
    }

    private let segments: [Segment]
    private let segmentKnotDistances: [Double]
    private let originalKnotDistances: [Double]
    let totalDistanceMeters: Double

    init(points: [FlightGeodeticPoint],
         tangentOverrides: [Int: SIMD3<Double>] = [:]) {
        precondition(points.count >= 2)
        let raw = points.map(FlightGeodesy.ecef)
        var positions = [raw[0]]
        var retainedOriginalIndices = [0]
        var originalToRetained = Array(repeating: 0, count: raw.count)
        for (index, point) in raw.enumerated().dropFirst() {
            if simd_distance(point, positions.last!) > 0.01 {
                positions.append(point)
                retainedOriginalIndices.append(index)
            }
            originalToRetained[index] = positions.count - 1
        }
        precondition(positions.count >= 2)

        var chordDistances = [0.0]
        for index in 1..<positions.count {
            chordDistances.append(
                chordDistances[index - 1] + simd_distance(positions[index - 1], positions[index])
            )
        }
        var tangents = Array(repeating: SIMD3<Double>(repeating: 0), count: positions.count)
        for index in positions.indices {
            if index == 0 {
                tangents[index] = (positions[1] - positions[0])
            } else if index == positions.count - 1 {
                tangents[index] = (positions[index] - positions[index - 1])
            } else {
                tangents[index] = (positions[index + 1] - positions[index - 1])
            }
            tangents[index] = simd_normalize(tangents[index])
            if let override = tangentOverrides[retainedOriginalIndices[index]],
               simd_length_squared(override) > 1e-18 {
                tangents[index] = simd_normalize(override)
            }
        }

        var segments = [Segment]()
        var arcKnots = [0.0]
        for index in 0..<(positions.count - 1) {
            let segment = Segment(
                start: positions[index],
                end: positions[index + 1],
                startTangent: tangents[index],
                endTangent: tangents[index + 1],
                chordSpan: chordDistances[index + 1] - chordDistances[index]
            )
            segments.append(segment)
            arcKnots.append(arcKnots.last! + segment.length)
        }
        self.segments = segments
        self.segmentKnotDistances = arcKnots
        self.originalKnotDistances = originalToRetained.map { arcKnots[$0] }
        self.totalDistanceMeters = arcKnots.last!
    }

    func knotDistance(at index: Int) -> Double {
        originalKnotDistances[min(originalKnotDistances.count - 1, max(0, index))]
    }

    func sample(at rawDistance: Double) -> Sample {
        let distance = min(totalDistanceMeters, max(0, rawDistance))
        if distance <= 0 { return segments[0].sample(atArcDistance: 0) }
        if distance >= totalDistanceMeters { return segments.last!.sample(atArcDistance: segments.last!.length) }
        var low = 0
        var high = segmentKnotDistances.count - 1
        while low + 1 < high {
            let middle = (low + high) / 2
            if segmentKnotDistances[middle] <= distance { low = middle } else { high = middle }
        }
        return segments[low].sample(
            atArcDistance: distance - segmentKnotDistances[low]
        )
    }
}

private struct FlightDistanceTiming {
    struct Sample {
        let distanceMeters: Double
        let speedMetersPerSecond: Double
    }

    let times: [TimeInterval]
    let distances: [Double]
    let slopes: [Double]

    init(times: [TimeInterval], distances: [Double], desiredSpeeds: [Double]) {
        precondition(times.count == distances.count && times.count == desiredSpeeds.count)
        var secants = [Double]()
        for index in 0..<(times.count - 1) {
            secants.append(
                max(0, distances[index + 1] - distances[index])
                    / max(0.000_001, times[index + 1] - times[index])
            )
        }
        var slopes = desiredSpeeds
        slopes[0] = 0
        slopes[slopes.count - 1] = 0
        for index in 1..<(slopes.count - 1) {
            let monotoneLimit = 3 * min(secants[index - 1], secants[index])
            slopes[index] = min(max(0, slopes[index]), max(0, monotoneLimit))
        }
        // Fritsch-Carlson limiting preserves monotone distance without
        // flattening the physically meaningful 0→Vr and Vref→0 endpoint
        // slopes. A constant-acceleration roll has normalized slopes (0, 2).
        for index in secants.indices {
            let secant = secants[index]
            guard secant > 1e-9 else {
                slopes[index] = 0
                slopes[index + 1] = 0
                continue
            }
            let alpha = slopes[index] / secant
            let beta = slopes[index + 1] / secant
            let magnitude = hypot(alpha, beta)
            if magnitude > 3 {
                let scale = 3 / magnitude
                slopes[index] = scale * alpha * secant
                slopes[index + 1] = scale * beta * secant
            }
        }
        self.times = times
        self.distances = distances
        self.slopes = slopes
    }

    func sample(at rawTime: TimeInterval) -> Sample {
        let time = min(times.last!, max(times[0], rawTime))
        if time <= times[0] { return Sample(distanceMeters: distances[0], speedMetersPerSecond: slopes[0]) }
        if time >= times.last! {
            return Sample(distanceMeters: distances.last!, speedMetersPerSecond: slopes.last!)
        }
        var segment = 0
        for index in 0..<(times.count - 1) where time >= times[index] {
            segment = index
            if time < times[index + 1] { break }
        }
        let span = max(0.000_001, times[segment + 1] - times[segment])
        let t = (time - times[segment]) / span
        let t2 = t * t
        let t3 = t2 * t
        let h00 = 2 * t3 - 3 * t2 + 1
        let h10 = t3 - 2 * t2 + t
        let h01 = -2 * t3 + 3 * t2
        let h11 = t3 - t2
        let distance = distances[segment] * h00
            + slopes[segment] * span * h10
            + distances[segment + 1] * h01
            + slopes[segment + 1] * span * h11
        let speed = distances[segment] * ((6 * t2 - 6 * t) / span)
            + slopes[segment] * (3 * t2 - 4 * t + 1)
            + distances[segment + 1] * ((-6 * t2 + 6 * t) / span)
            + slopes[segment + 1] * (3 * t2 - 2 * t)
        return Sample(distanceMeters: distance, speedMetersPerSecond: max(0, speed))
    }
}

// MARK: - Compiled representative runway catalog

private enum FlightRunwayCatalog {
    static let runwaysByAirport: [String: [RunwayProfile]] = [
        "SFO": [
            runway("SFO", "01L", 37.607898, -122.382950, 10, 37.626476, -122.370630, 9, 2_332, 30),
            runway("SFO", "01R", 37.606333, -122.381061, 12, 37.627346, -122.367124, 10, 2_640, 29),
            runway("SFO", "28L", 37.611720, -122.358367, 13, 37.626298, -122.393124, 6, 3_469, 24),
            runway("SFO", "28R", 37.613538, -122.357160, 13, 37.628742, -122.393410, 5, 3_618, 25),
        ],
        "BOS": reciprocalPair(
            airport: "BOS", first: "04R", second: "22L",
            firstLatitude: 42.351064, firstLongitude: -71.011801, firstElevationFeet: 18,
            secondLatitude: 42.376923, secondLongitude: -70.999288, secondElevationFeet: 16,
            lengthMeters: 3_050, priority: 20
        ),
        "JFK": reciprocalPair(
            airport: "JFK", first: "13R", second: "31L",
            firstLatitude: 40.648399, firstLongitude: -73.816704, firstElevationFeet: 13,
            secondLatitude: 40.627899, secondLongitude: -73.771599, secondElevationFeet: 13,
            lengthMeters: 4_423, priority: 20
        ),
        "MIA": reciprocalPair(
            airport: "MIA", first: "08R", second: "26L",
            firstLatitude: 25.800699, firstLongitude: -80.301399, firstElevationFeet: 8,
            secondLatitude: 25.802000, secondLongitude: -80.269501, secondElevationFeet: 8,
            lengthMeters: 3_202, priority: 20
        ),
        "LAX": reciprocalPair(
            airport: "LAX", first: "07L", second: "25R",
            firstLatitude: 33.935556, firstLongitude: -118.422089, firstElevationFeet: 119,
            secondLatitude: 33.939881, secondLongitude: -118.379794, secondElevationFeet: 94,
            lengthMeters: 3_930, priority: 20
        ),
        "YYZ": reciprocalPair(
            airport: "YYZ", first: "06L", second: "24R",
            firstLatitude: 43.661049, firstLongitude: -79.623428, firstElevationFeet: 529,
            secondLatitude: 43.678978, secondLongitude: -79.597366, secondElevationFeet: 546,
            lengthMeters: 2_956, priority: 20
        ),
        "YVR": reciprocalPair(
            airport: "YVR", first: "08R", second: "26L",
            firstLatitude: 49.190102, firstLongitude: -123.208000, firstElevationFeet: 9,
            secondLatitude: 49.184399, secondLongitude: -123.161003, secondElevationFeet: 6,
            lengthMeters: 3_505, priority: 20
        ),
        "YQR": reciprocalPair(
            airport: "YQR", first: "13", second: "31",
            firstLatitude: 50.439201, firstLongitude: -104.670998, firstElevationFeet: 1_894,
            secondLatitude: 50.423302, secondLongitude: -104.648003, secondElevationFeet: 1_894,
            lengthMeters: 2_408, priority: 20
        ),
        "SEA": reciprocalPair(
            airport: "SEA", first: "16L", second: "34R",
            firstLatitude: 47.463799, firstLongitude: -122.307999, firstElevationFeet: 432,
            secondLatitude: 47.431198, secondLongitude: -122.307999, secondElevationFeet: 347,
            lengthMeters: 3_627, priority: 20
        ),
        "RDU": reciprocalPair(
            airport: "RDU", first: "05L", second: "23R",
            firstLatitude: 35.874500, firstLongitude: -78.802002, firstElevationFeet: 367,
            secondLatitude: 35.893799, secondLongitude: -78.778000, secondElevationFeet: 409,
            lengthMeters: 3_048, priority: 20
        ),
    ]

    private static func runway(_ airport: String,
                               _ designator: String,
                               _ thresholdLatitude: Double,
                               _ thresholdLongitude: Double,
                               _ thresholdElevationFeet: Double,
                               _ oppositeLatitude: Double,
                               _ oppositeLongitude: Double,
                               _ oppositeElevationFeet: Double,
                               _ lengthMeters: Double,
                               _ priority: Int) -> RunwayProfile {
        RunwayProfile(
            airportCode: airport,
            designator: designator,
            threshold: FlightGeodeticPoint(
                latitude: thresholdLatitude,
                longitude: thresholdLongitude,
                altitudeMeters: thresholdElevationFeet * 0.3048
            ),
            oppositeThreshold: FlightGeodeticPoint(
                latitude: oppositeLatitude,
                longitude: oppositeLongitude,
                altitudeMeters: oppositeElevationFeet * 0.3048
            ),
            elevationMeters: (thresholdElevationFeet + oppositeElevationFeet) * 0.1524,
            usableLengthMeters: lengthMeters,
            defaultPriority: priority
        )
    }

    private static func reciprocalPair(airport: String,
                                       first: String,
                                       second: String,
                                       firstLatitude: Double,
                                       firstLongitude: Double,
                                       firstElevationFeet: Double,
                                       secondLatitude: Double,
                                       secondLongitude: Double,
                                       secondElevationFeet: Double,
                                       lengthMeters: Double,
                                       priority: Int) -> [RunwayProfile] {
        [
            runway(
                airport, first,
                firstLatitude, firstLongitude, firstElevationFeet,
                secondLatitude, secondLongitude, secondElevationFeet,
                lengthMeters, priority
            ),
            runway(
                airport, second,
                secondLatitude, secondLongitude, secondElevationFeet,
                firstLatitude, firstLongitude, firstElevationFeet,
                lengthMeters, priority - 1
            ),
        ]
    }
}

private extension FlightVisualEngine {
    static func normalizedDegrees(_ value: Double) -> Double {
        (value.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }
}

private extension AircraftProfile {
    /// Representative threshold speed used to size a 30-second physical
    /// rollout. These are simulation values, not dispatch-performance data.
    var flightTwinTouchdownSpeedMetersPerSecond: Double {
        switch self {
        case .voyageClassic: return 64
        case .boeing737800: return 70
        case .airbusA320neo: return 68
        }
    }
}

private extension Double {
    var radians: Double { self * .pi / 180 }
    var degrees: Double { self * 180 / .pi }
}
