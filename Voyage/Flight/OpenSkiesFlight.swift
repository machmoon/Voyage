import Foundation
import CoreLocation

// MARK: - A path generated from a heading

/// A ground track built one fixed step at a time from a heading, a bank angle
/// and a speed. Open skies flies this instead of an authored runway-to-runway
/// spline, because nothing knows where the flight ends until it is cleared to
/// land.
///
/// The turn model is FlightGear's AI aircraft (FlightGear/flightgear,
/// `src/AIModel/AIAircraft.cxx` at 11f9f9d, `FGAIAircraft::updateHeading`): in
/// the air a bank angle gives a coordinated turn of radius v²/(g·tan φ), and the
/// heading advances by the share of that circle flown in the step. Bank slews
/// toward its target at a fixed roll rate and is capped
/// (`src/AIModel/performancedata.cxx`, `PerformanceData::actualBankAngle`:
/// 9°/s and a "passenger friendly" 30°). FlightGear is GPL-2.0, so this reads
/// it for the design and copies no code. Each step moves along the course with
/// Turf's destination formula (Turfjs/turf,
/// `packages/turf-destination/index.ts` at 7501c18, MIT).
struct SteeredPath: Equatable {
    struct Sample: Equatable {
        /// Flight seconds since the brakes came off.
        let time: TimeInterval
        let latitude: Double
        let longitude: Double
        let courseDegrees: Double
        let bankDegrees: Double
        let speedMetersPerSecond: Double
        /// Ground distance flown since the first sample.
        let distanceMeters: Double

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    static let step: TimeInterval = 1
    /// Gentler than FlightGear's 30°: a cabin full of people studying.
    static let maximumBankDegrees = 25.0
    static let rollRateDegreesPerSecond = 9.0
    static let gravity = 9.806_65
    /// Turf's mean Earth radius (`packages/turf-helpers/index.ts`, `earthRadius`).
    static let earthRadiusMeters = 6_371_008.8

    private(set) var samples: [Sample]

    init(start: CLLocationCoordinate2D, courseDegrees: Double) {
        samples = [Sample(time: 0, latitude: start.latitude, longitude: start.longitude,
                          courseDegrees: Self.normalized(courseDegrees), bankDegrees: 0,
                          speedMetersPerSecond: 0, distanceMeters: 0)]
    }

    var last: Sample { samples[samples.count - 1] }

    /// Degrees of heading per second that a coordinated bank gives at `speed`.
    static func turnRateDegreesPerSecond(bankDegrees: Double, speed: Double) -> Double {
        guard speed > 1 else { return 0 }
        return (gravity * tan(bankDegrees * .pi / 180) / speed) * 180 / .pi
    }

    /// Appends one step. The wings move toward `targetBank` at the roll rate and
    /// never past the limit; the speed is what the aircraft reaches by the end
    /// of the step.
    mutating func step(targetBank: Double, speed: Double) {
        let previous = last
        let limit = Self.maximumBankDegrees
        let target = min(limit, max(-limit, targetBank))
        let maxChange = Self.rollRateDegreesPerSecond * Self.step
        let bank = previous.bankDegrees
            + min(maxChange, max(-maxChange, target - previous.bankDegrees))
        let endSpeed = max(0, speed)
        let meanSpeed = (previous.speedMetersPerSecond + endSpeed) / 2
        let turn = Self.turnRateDegreesPerSecond(bankDegrees: bank, speed: meanSpeed) * Self.step
        let distance = meanSpeed * Self.step
        // Moving along the mid-step course keeps a steady turn on its arc
        // instead of cutting inside it one chord at a time.
        let moved = Self.destination(from: previous.coordinate,
                                     distanceMeters: distance,
                                     bearingDegrees: previous.courseDegrees + turn / 2)
        samples.append(Sample(
            time: previous.time + Self.step,
            latitude: moved.latitude,
            longitude: moved.longitude,
            courseDegrees: Self.normalized(previous.courseDegrees + turn),
            bankDegrees: bank,
            speedMetersPerSecond: endSpeed,
            distanceMeters: previous.distanceMeters + distance
        ))
    }

    /// Appends a sample planned elsewhere: the cleared approach
    /// (`ApproachSegment`), which must land on time rather than be steered.
    mutating func append(_ sample: Sample) {
        samples.append(sample)
    }

    /// Steps forward until the newest sample is at `time` or just before it.
    mutating func advance(to time: TimeInterval,
                          targetBank: (Sample) -> Double,
                          speed: (TimeInterval) -> Double) {
        while last.time + Self.step <= time + 1e-9 {
            step(targetBank: targetBank(last), speed: speed(last.time + Self.step))
        }
    }

    /// The aircraft at any instant: interpolated between steps, and carried
    /// straight ahead past the newest one (the display runs a frame or two
    /// ahead of the session tick that extends the path).
    func sample(at time: TimeInterval) -> Sample {
        let first = samples[0]
        guard time > first.time else { return first }
        let newest = last
        guard time < newest.time else {
            let extra = time - newest.time
            let distance = newest.speedMetersPerSecond * extra
            let ahead = Self.destination(from: newest.coordinate, distanceMeters: distance,
                                         bearingDegrees: newest.courseDegrees)
            return Sample(time: time, latitude: ahead.latitude, longitude: ahead.longitude,
                          courseDegrees: newest.courseDegrees, bankDegrees: newest.bankDegrees,
                          speedMetersPerSecond: newest.speedMetersPerSecond,
                          distanceMeters: newest.distanceMeters + distance)
        }
        let index = min(samples.count - 2, max(0, Int(time / Self.step)))
        let a = samples[index]
        let b = samples[index + 1]
        let f = (time - a.time) / Self.step
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * f }
        return Sample(
            time: time,
            latitude: mix(a.latitude, b.latitude),
            longitude: mix(a.longitude, b.longitude),
            courseDegrees: Self.normalized(a.courseDegrees
                + Self.shortestAngle(from: a.courseDegrees, to: b.courseDegrees) * f),
            bankDegrees: mix(a.bankDegrees, b.bankDegrees),
            speedMetersPerSecond: mix(a.speedMetersPerSecond, b.speedMetersPerSecond),
            distanceMeters: mix(a.distanceMeters, b.distanceMeters)
        )
    }

    /// The point `distanceMeters` along `bearingDegrees` from `start`, on a
    /// sphere: Turf's `destination`.
    static func destination(from start: CLLocationCoordinate2D,
                            distanceMeters: Double,
                            bearingDegrees: Double) -> CLLocationCoordinate2D {
        let lat1 = start.latitude * .pi / 180
        let lon1 = start.longitude * .pi / 180
        let bearing = bearingDegrees * .pi / 180
        let angular = distanceMeters / earthRadiusMeters
        let lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(bearing))
        let lon2 = lon1 + atan2(sin(bearing) * sin(angular) * cos(lat1),
                                cos(angular) - sin(lat1) * sin(lat2))
        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }

    static func normalized(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    static func shortestAngle(from: Double, to: Double) -> Double {
        OpenSkiesField.angle(from: from, to: to)
    }
}

// MARK: - The Open skies flight

/// A 25-minute focus flight from the home airport with no destination. The
/// autopilot flies toward a field the traveller has not landed at yet; tapping
/// the aircraft hands over the controls; two minutes before the end air traffic
/// control clears it to land at the nearest field within reach, whoever is
/// flying, and it is down exactly when the 25 minutes are.
///
/// Pure and deterministic: everything is a function of the inputs and the
/// times they arrived, in flight seconds. The session converts its leg clock
/// to flight seconds through `timeScale`, which is 1 except under
/// `-VoyageDemoFlight`, where the whole flight plays fast-forward.
struct OpenSkiesFlight {
    enum Control: Equatable {
        case autopilot
        /// The traveller is flying.
        case pilot
        /// Cleared to land: the autopilot has the airplane until the gate.
        case approach
    }

    enum Event: Equatable {
        case autopilotEngaged
        case clearedToLand(OpenSkiesField)
    }

    struct Landing: Equatable {
        let field: OpenSkiesField
        let runway: RunwayProfile
        /// The cleared approach: from where the airplane was at 23:00 to the
        /// threshold, flown to arrive exactly as the rollout begins.
        let approach: ApproachSegment
    }

    // MARK: Timeline (flight seconds)

    static let duration: TimeInterval = 25 * 60
    /// Air traffic control takes the flight back at 23:00.
    static let reclaimLead: TimeInterval = 2 * 60
    static let rolloutDuration: TimeInterval = 30
    static let climbDuration: TimeInterval = 6 * 60
    /// Let go of the controls this long and the autopilot takes over.
    static let idleRelease: TimeInterval = 10
    /// Wings stay level after liftoff, as on a real initial climb.
    static let wingsLevelAfterLiftoff: TimeInterval = 20
    /// The gentle let-down from cruise to the approach starts here.
    static let letDownDuration: TimeInterval = 5 * 60

    // MARK: Performance

    /// Above the Cascades and the San Gabriels, the highest terrain within a
    /// 25-minute flight of any home airport.
    static let cruiseAltitudeMeters = 15_500 * 0.3048
    static let approachAltitudeMeters = 3_000 * 0.3048
    /// Bank commands this small count as hands off.
    static let pilotDeadbandDegrees = 2.0

    /// The app's own rate: a catalog route's miles over its focus minutes.
    /// SFO to LAX is 337 miles in 1h 25m, about four miles a minute.
    static let milesPerFocusMinute: Double = {
        let leg = RoutePlanner.itinerary(from: Airport.byCode("SFO"),
                                         to: Airport.byCode("LAX")).legs[0]
        return leg.distanceMiles / (leg.duration / 60)
    }()

    /// What a landed Open skies flight credits, at that rate.
    static var creditedMiles: Double { milesPerFocusMinute * duration / 60 }

    // MARK: State

    let origin: Airport
    let departureRunway: RunwayProfile
    /// Phase boundaries in flight seconds.
    let schedule: FlightPhaseSchedule
    /// Flight seconds per second of the session's leg clock.
    let timeScale: Double
    let rotationSpeed: Double
    let cruiseSpeed: Double
    private let fields: [OpenSkiesField]
    private let visitedCodes: Set<String>

    private(set) var path: SteeredPath
    private(set) var control: Control = .autopilot
    /// Where the autopilot is heading. Re-chosen whenever it takes over.
    private(set) var target: OpenSkiesField?
    private(set) var landing: Landing?
    private(set) var pilotBank: Double = 0
    private var lastPilotInput: TimeInterval = 0

    init(origin: Airport,
         departureRunway: RunwayProfile,
         aircraft: AircraftProfile,
         visitedCodes: Set<String>,
         fields: [OpenSkiesField] = OpenSkiesField.all,
         legDuration: TimeInterval = OpenSkiesFlight.duration) {
        let schedule = FlightPhaseSchedule.openSkies(aircraft: aircraft)
        let rotation = aircraft.rotationKnots * 0.514_444
        self.origin = origin
        self.departureRunway = departureRunway
        self.schedule = schedule
        self.timeScale = Self.duration / max(1, legDuration)
        self.rotationSpeed = rotation
        self.cruiseSpeed = Self.cruiseSpeed(schedule: schedule, rotationSpeed: rotation)
        self.fields = fields.filter { !$0.runways.isEmpty }
        self.visitedCodes = visitedCodes
        self.path = SteeredPath(start: departureRunway.threshold.coordinate,
                                courseDegrees: departureRunway.trueHeadingDegrees)
        self.target = Self.scenicTarget(from: departureRunway.threshold.coordinate,
                                        course: departureRunway.trueHeadingDegrees,
                                        distanceBudget: nominalDistance(from: 0, to: schedule.landingStart),
                                        origin: origin, fields: self.fields,
                                        visitedCodes: visitedCodes)
    }

    // MARK: Controls

    func canTakeControl(at time: TimeInterval) -> Bool {
        control == .autopilot && time >= schedule.takeoffEnd && time < schedule.descentStart
    }

    /// The traveller takes the airplane. False when it is not theirs to take:
    /// on the runway, or once cleared to land.
    @discardableResult
    mutating func takeControl(at time: TimeInterval) -> Bool {
        guard canTakeControl(at: time) else { return false }
        control = .pilot
        pilotBank = 0
        lastPilotInput = time
        return true
    }

    /// Hands the airplane back. The autopilot picks a new field to head for.
    mutating func releaseControl() {
        guard control == .pilot else { return }
        engageAutopilot(from: path.last)
    }

    /// The bank the traveller is asking for, in degrees (negative is left).
    mutating func steer(bankDegrees: Double) {
        guard control == .pilot else { return }
        let limit = SteeredPath.maximumBankDegrees
        pilotBank = min(limit, max(-limit, bankDegrees))
    }

    // MARK: Advancing

    /// Extends the path to `time`, applying the timeline on the way: ten
    /// seconds hands-off returns the airplane to the autopilot, and 23:00
    /// starts the approach whoever is flying.
    mutating func advance(to time: TimeInterval) -> [Event] {
        var events: [Event] = []
        while path.last.time + SteeredPath.step <= time + 1e-9 {
            let now = path.last
            if control == .pilot {
                if abs(pilotBank) > Self.pilotDeadbandDegrees {
                    lastPilotInput = now.time
                } else if now.time - lastPilotInput >= Self.idleRelease * timeScale {
                    engageAutopilot(from: now)
                    events.append(.autopilotEngaged)
                }
            }
            if control != .approach, now.time >= schedule.descentStart - 1e-9,
               let landing = beginApproach(from: now) {
                events.append(.clearedToLand(landing.field))
            }
            let next = now.time + SteeredPath.step
            if let landing, next <= schedule.landingStart + 1e-9 {
                // Cleared to land: the airplane flies the planned approach.
                path.append(landing.approach.sample(at: next, after: now))
            } else {
                path.step(targetBank: bankCommand(from: now), speed: speed(after: now, at: next))
            }
        }
        return events
    }

    /// Where a flight that ends now would be logged: the field it is cleared
    /// for, else the nearest field that is not home.
    func provisionalField(at time: TimeInterval) -> OpenSkiesField? {
        if let landing { return landing.field }
        let position = path.sample(at: time)
        let here = CLLocation(latitude: position.latitude, longitude: position.longitude)
        return OpenSkiesField.nearest(to: here, in: fields.filter { $0.code != origin.code })
    }

    // MARK: Altitude

    /// A monotonic climb on the trajectory's own front-loaded curve
    /// (`FlightTrajectory.climbAltitudeFraction`), level cruise, a let-down to
    /// the approach altitude, then a constant-angle descent to the runway.
    func altitudeMeters(at time: TimeInterval) -> Double {
        let departure = departureRunway.threshold.altitudeMeters
        let arrival = landing?.runway.threshold.altitudeMeters ?? departure
        let liftoff = departure + 18
        let s = schedule
        if time < s.rotationStart { return departure }
        if time < s.takeoffEnd {
            let p = (time - s.rotationStart) / max(0.001, s.takeoffEnd - s.rotationStart)
            return departure + 18 * smoothstep(p)
        }
        if time < s.climbEnd {
            let p = (time - s.takeoffEnd) / max(0.001, s.climbDuration)
            return liftoff + (Self.cruiseAltitudeMeters - liftoff) * (1 - pow(1 - p, 1.5))
        }
        let approachAltitude = max(Self.approachAltitudeMeters, departure + 600)
        let letDown = s.descentStart - Self.letDownDuration
        if time < letDown { return Self.cruiseAltitudeMeters }
        if time < s.descentStart {
            let p = (time - letDown) / Self.letDownDuration
            return Self.cruiseAltitudeMeters
                + (approachAltitude - Self.cruiseAltitudeMeters) * smoothstep(p)
        }
        if time < s.landingStart {
            let p = (time - s.descentStart) / max(0.001, s.landingStart - s.descentStart)
            return approachAltitude + (arrival - approachAltitude) * p
        }
        return arrival
    }

    // MARK: Choices (static, so the tests can call them directly)

    /// Where to land when cleared: the nearest field within reach that is not
    /// home; home if nothing else is within reach; failing both, the nearest
    /// field that is not home, reach or not, so the flight always lands.
    static func landingField(from position: CLLocationCoordinate2D,
                             origin: Airport,
                             fields: [OpenSkiesField],
                             reachMeters: CLLocationDistance) -> OpenSkiesField? {
        let here = CLLocation(latitude: position.latitude, longitude: position.longitude)
        let byDistance = fields.sorted {
            $0.location.distance(from: here) < $1.location.distance(from: here)
        }
        func reachable(_ field: OpenSkiesField) -> Bool {
            field.location.distance(from: here) <= reachMeters
        }
        return byDistance.first { $0.code != origin.code && reachable($0) }
            ?? byDistance.first { $0.code == origin.code && reachable($0) }
            ?? byDistance.first { $0.code != origin.code }
            ?? byDistance.first
    }

    /// The field the autopilot heads for: one the traveller has not landed at,
    /// about as far as the flight has left to fly, and not far off the nose.
    static func scenicTarget(from position: CLLocationCoordinate2D,
                             course: Double,
                             distanceBudget: Double,
                             origin: Airport,
                             fields: [OpenSkiesField],
                             visitedCodes: Set<String>) -> OpenSkiesField? {
        let here = CLLocation(latitude: position.latitude, longitude: position.longitude)
        let budget = max(1, distanceBudget)
        func distance(_ field: OpenSkiesField) -> Double { field.location.distance(from: here) }
        func score(_ field: OpenSkiesField) -> Double {
            let turn = abs(OpenSkiesField.angle(from: course,
                                                to: GreatCircle.bearing(from: position, to: field.coordinate)))
            return abs(distance(field) - budget) + budget * 0.35 * turn / 180
        }
        let candidates = fields.filter { $0.code != origin.code }
        let unvisited = candidates.filter {
            !visitedCodes.contains($0.code) && (0.5...1.3).contains(distance($0) / budget)
        }
        let pool = unvisited.isEmpty ? candidates : unvisited
        return pool.min { score($0) < score($1) }
    }

    // MARK: Speed

    /// Ground speed with nobody steering the throttle: accelerate down the
    /// runway, build to cruise over the first half of the climb, slow toward
    /// touchdown speed on the approach, stop on the rollout.
    static func nominalSpeed(at time: TimeInterval,
                             schedule s: FlightPhaseSchedule,
                             rotationSpeed: Double,
                             cruiseSpeed: Double) -> Double {
        let touchdown = rotationSpeed * 0.92
        if time < s.takeoffEnd { return rotationSpeed * max(0, time) / max(0.001, s.takeoffEnd) }
        if time < s.climbEnd {
            let p = min(1, (time - s.takeoffEnd) / max(0.001, s.climbDuration * 0.5))
            return rotationSpeed + (cruiseSpeed - rotationSpeed) * p
        }
        if time < s.descentStart { return cruiseSpeed }
        if time < s.landingStart {
            let p = (time - s.descentStart) / max(0.001, s.landingStart - s.descentStart)
            return cruiseSpeed + (touchdown - cruiseSpeed) * p
        }
        let p = (time - s.landingStart) / max(0.001, s.landingDuration)
        return touchdown * max(0, 1 - p)
    }

    /// The cruise speed at which 25 minutes covers the app's miles per minute.
    /// Nominal speed is linear in cruise speed, so two integrals solve it.
    static func cruiseSpeed(schedule: FlightPhaseSchedule, rotationSpeed: Double) -> Double {
        func distance(_ cruise: Double) -> Double {
            stride(from: 0.5, to: schedule.legEnd, by: 1).reduce(0) {
                $0 + nominalSpeed(at: $1, schedule: schedule, rotationSpeed: rotationSpeed,
                                  cruiseSpeed: cruise)
            }
        }
        let base = distance(0)
        let slope = distance(1) - base
        return (creditedMiles * 1_609.344 - base) / max(1, slope)
    }

    private func nominalDistance(from start: TimeInterval, to end: TimeInterval) -> Double {
        stride(from: start + 0.5, to: end, by: 1).reduce(0) {
            $0 + Self.nominalSpeed(at: $1, schedule: schedule, rotationSpeed: rotationSpeed,
                                   cruiseSpeed: cruiseSpeed)
        }
    }

    private func speed(after sample: SteeredPath.Sample, at time: TimeInterval) -> Double {
        if let landing, time > schedule.landingStart {
            // Rollout: from touchdown speed to a stop at 25:00, the same
            // rollout `nominalSpeed` flies. Starting from the approach's own
            // ground speed instead carried a fast approach (over 200 m/s)
            // more than 3 km down the runway.
            let touchdown = min(landing.approach.speed, rotationSpeed * 0.92)
            let p = (time - schedule.landingStart) / max(0.001, schedule.landingDuration)
            return touchdown * max(0, 1 - p)
        }
        return Self.nominalSpeed(at: time, schedule: schedule,
                                 rotationSpeed: rotationSpeed, cruiseSpeed: cruiseSpeed)
    }

    // MARK: Steering

    private func bankCommand(from sample: SteeredPath.Sample) -> Double {
        if sample.time < schedule.takeoffEnd + Self.wingsLevelAfterLiftoff { return 0 }
        if sample.time >= schedule.landingStart { return 0 }
        switch control {
        case .pilot:
            return pilotBank
        case .autopilot:
            return target.map { headingHold(from: sample, to: $0.coordinate) } ?? 0
        case .approach:
            return 0
        }
    }

    /// FlightGear's heading lock (`FGAIAircraft::updateBankAngleTarget`): bank
    /// toward the target by one degree per degree of heading error, capped.
    private func headingHold(from sample: SteeredPath.Sample,
                             to point: CLLocationCoordinate2D) -> Double {
        let here = CLLocation(latitude: sample.latitude, longitude: sample.longitude)
        let there = CLLocation(latitude: point.latitude, longitude: point.longitude)
        // Over the point itself the bearing swings wildly; hold the wings level.
        guard here.distance(from: there) > 300 else { return 0 }
        let wanted = GreatCircle.bearing(from: sample.coordinate, to: point)
        return OpenSkiesField.angle(from: sample.courseDegrees, to: wanted)
    }

    private mutating func engageAutopilot(from sample: SteeredPath.Sample) {
        control = .autopilot
        pilotBank = 0
        target = Self.scenicTarget(from: sample.coordinate, course: sample.courseDegrees,
                                   distanceBudget: nominalDistance(from: sample.time,
                                                                   to: schedule.landingStart),
                                   origin: origin, fields: fields, visitedCodes: visitedCodes)
    }

    private mutating func beginApproach(from sample: SteeredPath.Sample) -> Landing? {
        let available = max(1, schedule.landingStart - sample.time)
        guard let field = Self.landingField(from: sample.coordinate, origin: origin, fields: fields,
                                            reachMeters: cruiseSpeed * available),
              let runway = field.landingRunway(
                arrivingOn: GreatCircle.bearing(from: sample.coordinate, to: field.coordinate))
        else { return nil }
        let landing = Landing(field: field, runway: runway,
                              approach: ApproachSegment(from: sample, to: runway,
                                                        arrivingAt: schedule.landingStart))
        self.landing = landing
        control = .approach
        pilotBank = 0
        return landing
    }

    private func smoothstep(_ value: Double) -> Double {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }
}

extension FlightPhaseSchedule {
    /// Open skies' phases: the aircraft's own takeoff roll, a six-minute climb,
    /// cruise to 23:00, the approach, and a 30-second rollout ending at 25:00.
    /// `legDuration` scales the whole timeline for `-VoyageDemoFlight`.
    static func openSkies(aircraft: AircraftProfile,
                          legDuration: TimeInterval = OpenSkiesFlight.duration) -> FlightPhaseSchedule {
        let full = OpenSkiesFlight.duration
        let roll = make(legDuration: full, aircraft: aircraft, shortFlights: false).takeoffEnd
        let scale = legDuration / full
        return FlightPhaseSchedule(
            legDuration: legDuration,
            takeoffEnd: roll * scale,
            climbEnd: (roll + OpenSkiesFlight.climbDuration) * scale,
            descentStart: (full - OpenSkiesFlight.reclaimLead) * scale,
            landingStart: (full - OpenSkiesFlight.rolloutDuration) * scale
        )
    }
}

// MARK: - The cleared approach

/// The approach once cleared: one great-circle segment from where the airplane
/// was at 23:00 to the runway threshold, flown at constant ground speed so it
/// crosses the threshold exactly when the rollout begins. The course eases
/// from the old heading onto the segment over its first seconds.
struct ApproachSegment: Equatable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let start: FlightGeodeticPoint
    let end: FlightGeodeticPoint
    let startCourse: Double
    let lengthMeters: Double
    /// Ground speed along the segment: its length over its time.
    var speed: Double { lengthMeters / max(1, endTime - startTime) }
    /// Seconds to turn from the old course onto the segment.
    static let headingEase: TimeInterval = 12

    init(from sample: SteeredPath.Sample, to runway: RunwayProfile, arrivingAt endTime: TimeInterval) {
        startTime = sample.time
        self.endTime = endTime
        start = FlightGeodeticPoint(coordinate: sample.coordinate)
        end = runway.threshold
        startCourse = sample.courseDegrees
        lengthMeters = CLLocation(latitude: start.latitude, longitude: start.longitude)
            .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
    }

    func sample(at time: TimeInterval, after previous: SteeredPath.Sample) -> SteeredPath.Sample {
        let f = min(1, max(0, (time - startTime) / max(1, endTime - startTime)))
        let point = GreatCircle.point(from: start.coordinate, to: end.coordinate, fraction: f)
        let track = GreatCircle.bearing(from: point, to: end.coordinate)
        let ease = min(1, (time - startTime) / Self.headingEase)
        let course = f >= 1 ? previous.courseDegrees
            : SteeredPath.normalized(startCourse + SteeredPath.shortestAngle(from: startCourse, to: track) * ease)
        return SteeredPath.Sample(
            time: time, latitude: point.latitude, longitude: point.longitude,
            courseDegrees: course, bankDegrees: 0, speedMetersPerSecond: speed,
            distanceMeters: previous.distanceMeters
                + CLLocation(latitude: point.latitude, longitude: point.longitude)
                    .distance(from: CLLocation(latitude: previous.latitude, longitude: previous.longitude))
        )
    }
}
