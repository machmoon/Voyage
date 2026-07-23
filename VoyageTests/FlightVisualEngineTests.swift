import XCTest
import CoreLocation
import simd
@testable import Voyage

final class FlightVisualEngineTests: XCTestCase {
    private let frozenAt = Date(timeIntervalSince1970: 1_750_000_000)

    func testProductionScheduleUsesAircraftRollAndBlockTimeScaledWindows() {
        let schedule = FlightPhaseSchedule.make(
            legDuration: 6 * 60 * 60,
            aircraft: .boeing737800,
            shortFlights: false
        )

        XCTAssertEqual(schedule.takeoffDuration, 36, accuracy: 0.001)
        XCTAssertEqual(schedule.climbDuration, 20 * 60, accuracy: 0.001)
        XCTAssertEqual(schedule.descentDuration, 25 * 60, accuracy: 0.001)
        XCTAssertEqual(schedule.landingDuration, 30, accuracy: 0.001)
        XCTAssertEqual(schedule.rotationStart, schedule.takeoffEnd * 0.68, accuracy: 0.000_001)
        XCTAssertGreaterThan(schedule.cruiseDuration, 0)
        XCTAssertEqual(schedule.phase(at: 0), .takeoffRoll)
        XCTAssertEqual(schedule.phase(at: schedule.takeoffEnd), .climb)
        XCTAssertEqual(schedule.phase(at: schedule.climbEnd), .cruise)
        XCTAssertEqual(schedule.phase(at: schedule.descentStart), .descent)
        XCTAssertEqual(schedule.phase(at: schedule.landingStart), .landing)
    }

    func testShortFlightSchedulePreservesQABoundaries() {
        let schedule = FlightPhaseSchedule.make(
            legDuration: 90 * 60,
            aircraft: .airbusA320neo,
            shortFlights: true
        )

        XCTAssertEqual(schedule.takeoffEnd, 28, accuracy: 0.001)
        XCTAssertEqual(schedule.climbEnd, 180, accuracy: 0.001)
        XCTAssertEqual(schedule.descentDuration, 165, accuracy: 0.001)
        XCTAssertEqual(schedule.landingDuration, 15, accuracy: 0.001)
    }

    func testRunwayCatalogCoversEveryAirportAndBothSFOFamilies() {
        for airport in Airport.all {
            let runways = FlightVisualEngine.runways(for: airport)
            XCTAssertGreaterThanOrEqual(runways.count, 2, airport.code)
            XCTAssertTrue(runways.allSatisfy { $0.airportCode == airport.code })
            XCTAssertTrue(runways.allSatisfy { $0.usableLengthMeters > 1_700 })
        }

        let sfoIDs = Set(FlightVisualEngine.runways(for: Airport.byCode("SFO")).map(\.designator))
        XCTAssertTrue(sfoIDs.isSuperset(of: ["01L", "01R", "28L", "28R"]))
    }

    func testRunwaySelectionUsesFrozenWindAndIsDeterministic() {
        let sfo = Airport.byCode("SFO")
        let westWind = weather(airport: sfo, direction: 298, speed: 18)
        let northWind = weather(airport: sfo, direction: 28, speed: 18)

        let first = FlightVisualEngine.selectRunway(
            for: sfo,
            routeCourseDegrees: 70,
            weather: westWind,
            aircraft: .boeing737800
        )
        let second = FlightVisualEngine.selectRunway(
            for: sfo,
            routeCourseDegrees: 70,
            weather: westWind,
            aircraft: .boeing737800
        )
        let northerly = FlightVisualEngine.selectRunway(
            for: sfo,
            routeCourseDegrees: 70,
            weather: northWind,
            aircraft: .boeing737800
        )

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.designator.hasPrefix("28"))
        XCTAssertTrue(northerly.designator.hasPrefix("01"))
    }

    func testWGS84ENUOffsetRoundTrips() {
        let origin = FlightGeodeticPoint(
            latitude: 37.6213,
            longitude: -122.3790,
            altitudeMeters: 4
        )
        let target = FlightGeodesy.offset(
            from: origin,
            eastMeters: 1_234,
            northMeters: -432,
            upMeters: 88
        )
        let enu = FlightGeodesy.enu(of: target, relativeTo: origin)
        let roundTrip = FlightGeodesy.geodetic(fromECEF: FlightGeodesy.ecef(target))

        XCTAssertEqual(enu.x, 1_234, accuracy: 0.5)
        XCTAssertEqual(enu.y, -432, accuracy: 0.5)
        XCTAssertEqual(enu.z, 88, accuracy: 0.5)
        XCTAssertEqual(roundTrip.latitude, target.latitude, accuracy: 0.000_000_1)
        XCTAssertEqual(roundTrip.longitude, target.longitude, accuracy: 0.000_000_1)
        XCTAssertEqual(roundTrip.altitudeMeters, target.altitudeMeters, accuracy: 0.02)
    }

    func testTrajectoryStartsOnSelectedRunwayAndEndsAfterRollout() {
        let trajectory = makeTrajectory()
        let start = trajectory.state(at: 0, seat: "A8")
        let end = trajectory.state(at: trajectory.schedule.legEnd, seat: "A8")

        XCTAssertLessThan(
            location(start.aircraft.coordinate).distance(from: location(trajectory.departureRunway.threshold.coordinate)),
            2
        )
        let rolloutDistance = location(end.aircraft.coordinate).distance(
            from: location(trajectory.arrivalRunway.threshold.coordinate)
        )
        XCTAssertGreaterThan(rolloutDistance, 850)
        XCTAssertLessThan(rolloutDistance, 1_200)
        XCTAssertGreaterThan(
            location(end.aircraft.coordinate).distance(
                from: location(trajectory.arrivalRunway.oppositeThreshold.coordinate)
            ),
            2_500
        )
        XCTAssertEqual(start.aircraft.groundSpeedMetersPerSecond, 0, accuracy: 0.001)
        XCTAssertEqual(end.aircraft.groundSpeedMetersPerSecond, 0, accuracy: 0.001)
        XCTAssertEqual(start.routeProgress, 0, accuracy: 0.000_001)
        XCTAssertEqual(end.routeProgress, 1, accuracy: 0.000_001)

        // A passenger starts at actual window height on the tarmac. A large
        // minimum orbit range would silently turn this into an aerial view.
        XCTAssertGreaterThan(start.camera.rangeMeters, 10)
        XCTAssertLessThan(start.camera.rangeMeters, 80)
        let runwayProjection = WorldSceneryProjection(pose: WorldCameraPose(start.camera))
        XCTAssertEqual(
            runwayProjection.targetAltitudeMeters,
            trajectory.departureRunway.elevationMeters,
            accuracy: 0.5
        )
        let reconstructedCameraAltitude = runwayProjection.targetAltitudeMeters
            + runwayProjection.rangeMeters * cos(runwayProjection.tiltDegrees.radiansForTest)
        XCTAssertEqual(
            reconstructedCameraAltitude,
            start.camera.altitudeMeters,
            accuracy: 0.01
        )
    }

    func testTrajectoryPoseIsContinuousAtEveryPhaseBoundary() {
        let trajectory = makeTrajectory()
        let boundaries = [
            trajectory.schedule.takeoffEnd,
            trajectory.schedule.climbEnd,
            trajectory.schedule.descentStart,
            trajectory.schedule.landingStart,
        ]

        for boundary in boundaries {
            let before = trajectory.state(at: boundary - 0.02, seat: "C8")
            let exact = trajectory.state(at: boundary, seat: "C8")
            let after = trajectory.state(at: boundary + 0.02, seat: "C8")

            XCTAssertLessThan(distance(before.aircraft, exact.aircraft), 30, "boundary \(boundary)")
            XCTAssertLessThan(distance(exact.aircraft, after.aircraft), 30, "boundary \(boundary)")
            XCTAssertLessThan(
                abs(shortestAngle(before.aircraft.courseDegrees, after.aircraft.courseDegrees)),
                2,
                "boundary \(boundary)"
            )
            XCTAssertLessThan(abs(before.aircraft.pitchDegrees - after.aircraft.pitchDegrees), 1)
            XCTAssertLessThan(abs(before.aircraft.bankDegrees - after.aircraft.bankDegrees), 2)
            XCTAssertTrue(before.aircraft.groundSpeedMetersPerSecond.isFinite)
            XCTAssertTrue(after.aircraft.groundSpeedMetersPerSecond.isFinite)
        }
    }

    func testRotationPitchAndQuaternionAreContinuous() {
        let trajectory = makeTrajectory()
        let checkpoints = [
            trajectory.schedule.rotationStart,
            trajectory.schedule.takeoffEnd,
        ]

        for checkpoint in checkpoints {
            let epsilon = 0.001
            let before = trajectory.state(at: checkpoint - epsilon, seat: "A8").aircraft
            let after = trajectory.state(at: checkpoint + epsilon, seat: "A8").aircraft
            XCTAssertLessThan(abs(before.pitchDegrees - after.pitchDegrees), 0.01)
            XCTAssertLessThan(
                quaternionAngleDegrees(before.orientation, after.orientation),
                0.02
            )
        }
    }

    /// The altitude readout is live, so the number a passenger sees five
    /// minutes after takeoff has to be one a narrow-body could actually be at.
    func testEarlyClimbAltitudeStaysBelievableAndLevelsOffAtAPlausibleFlightLevel() {
        let trajectory = makeTrajectory()
        let feetPerMeter = 3.280_839_895
        let liftoffFeet = (trajectory.departureRunway.threshold.altitudeMeters + 18) * feetPerMeter

        let fiveMinutes = trajectory.state(at: 5 * 60, seat: "A8").aircraft.altitudeMeters * feetPerMeter
        XCTAssertLessThanOrEqual(
            fiveMinutes - liftoffFeet,
            5 * 2_500,
            "five minutes of climb implies more than 2,500 fpm"
        )

        let cruise = trajectory.state(
            at: trajectory.schedule.climbEnd + 60,
            seat: "A8"
        ).aircraft.altitudeMeters * feetPerMeter
        XCTAssertGreaterThan(cruise, 25_000, "transcon should cruise in the flight levels")
        XCTAssertLessThanOrEqual(cruise, 38_000, "above a narrow-body's service ceiling")
        XCTAssertLessThanOrEqual(
            (cruise - liftoffFeet) / (trajectory.schedule.climbDuration / 60),
            2_500,
            "average climb rate to cruise is faster than a narrow-body flies"
        )
    }

    func testTakeoffRollStaysLevelAndClimbIsMonotonic() {
        let trajectory = makeTrajectory(shortFlights: true)
        let schedule = trajectory.schedule
        let runway = trajectory.departureRunway
        let liftoff = runway.threshold.altitudeMeters + 18

        let rollTimes = strideTimes(
            from: 0,
            through: max(0, schedule.rotationStart - 0.001),
            count: 80
        )
        for elapsed in rollTimes {
            let state = trajectory.state(at: elapsed, seat: "A8")
            let surface = runwaySurfaceAltitude(runway, at: state.aircraft.coordinate)
            XCTAssertEqual(
                state.aircraft.altitudeMeters,
                surface,
                accuracy: 0.2,
                "altitude rose during roll at elapsed \(elapsed)"
            )
        }

        let climbTimes = strideTimes(
            from: schedule.takeoffEnd,
            through: schedule.climbEnd,
            count: 120
        )
        var lastAltitude = liftoff
        for (index, elapsed) in climbTimes.enumerated() {
            let altitude = trajectory.state(at: elapsed, seat: "A8").aircraft.altitudeMeters
            if index == 0 {
                XCTAssertEqual(altitude, liftoff, accuracy: 0.2, "liftoff altitude at climb start")
            } else {
                XCTAssertGreaterThanOrEqual(
                    altitude,
                    lastAltitude - 0.05,
                    "altitude dipped at elapsed \(elapsed)"
                )
            }
            lastAltitude = altitude
        }
        XCTAssertGreaterThan(
            trajectory.state(at: schedule.climbEnd, seat: "A8").aircraft.altitudeMeters,
            liftoff + 500,
            "climb should reach meaningful altitude"
        )
    }

    func testShortFlightGroundSpeedsStayBelievableDuringDeparture() {
        let trajectory = makeTrajectory(shortFlights: true)
        let schedule = trajectory.schedule
        let checkpoints: [(TimeInterval, Double)] = [
            (schedule.takeoffEnd * 0.5, 95),
            (schedule.takeoffEnd + schedule.climbDuration * 0.35, 135),
            (schedule.climbEnd + schedule.cruiseDuration * 0.2, 250),
        ]
        for (elapsed, maxMetersPerSecond) in checkpoints {
            let speed = trajectory.state(at: elapsed, seat: "A8").aircraft.groundSpeedMetersPerSecond
            XCTAssertLessThan(
                speed,
                maxMetersPerSecond,
                "ground speed \(speed) m/s too high at elapsed \(elapsed)"
            )
        }
    }

    func testShortFlightInitialClimbRateStaysBelievable() {
        let trajectory = makeTrajectory(shortFlights: true)
        let schedule = trajectory.schedule
        let liftoff = trajectory.departureRunway.threshold.altitudeMeters + 18
        let climbStart = schedule.takeoffEnd
        let sampleSpan = schedule.climbDuration * 0.75

        for index in 1...40 {
            let earlierElapsed = climbStart + sampleSpan * Double(index - 1) / 40
            let laterElapsed = climbStart + sampleSpan * Double(index) / 40
            let deltaSeconds = laterElapsed - earlierElapsed
            guard deltaSeconds > 0 else { continue }

            let earlier = trajectory.state(at: earlierElapsed, seat: "A8").aircraft.altitudeMeters
            let later = trajectory.state(at: laterElapsed, seat: "A8").aircraft.altitudeMeters
            let feetPerMinute = (later - earlier) / deltaSeconds * 3.280_839_895 * 60
            let secondsIntoClimb = laterElapsed - climbStart

            // The first ~25 s after liftoff build vertical speed gradually.
            if secondsIntoClimb < 25 { continue }
            // The final level-off segment is intentionally slower than en-route climb.
            if secondsIntoClimb > schedule.climbDuration * 0.88 { continue }

            XCTAssertGreaterThanOrEqual(
                feetPerMinute,
                800,
                "climb too slow at elapsed \(laterElapsed)"
            )
            XCTAssertLessThanOrEqual(
                feetPerMinute,
                3_800,
                "climb too fast at elapsed \(laterElapsed)"
            )
        }

        let qaCeiling = 1_520.0
        XCTAssertEqual(
            trajectory.state(at: schedule.climbEnd - 0.001, seat: "A8").aircraft.altitudeMeters,
            qaCeiling,
            accuracy: 0.5,
            "compressed climb should level at the QA ceiling"
        )
        XCTAssertLessThan(
            trajectory.state(at: climbStart + 25, seat: "A8").aircraft.altitudeMeters - liftoff,
            400,
            "twenty-five seconds into climb should still be in the gentle initial segment"
        )
    }

    func testEarlyClimbKeepsNoseUpAndMapTiltNearHorizon() {
        let trajectory = makeTrajectory(shortFlights: true)
        let schedule = trajectory.schedule
        let start = schedule.takeoffEnd
        let end = schedule.takeoffEnd + schedule.climbDuration * 0.55
        var lastCameraAlt = 0.0
        var lastTilt = 0.0
        for index in 0...180 {
            let elapsed = start + (end - start) * Double(index) / 180
            let state = trajectory.state(at: elapsed, seat: "A8")
            XCTAssertGreaterThan(
                state.aircraft.pitchDegrees,
                1.5,
                "nose dropped at elapsed \(elapsed)"
            )
            XCTAssertGreaterThanOrEqual(
                state.camera.altitudeMeters,
                state.aircraft.altitudeMeters + 0.5,
                "eye below fuselage at elapsed \(elapsed)"
            )
            if index > 0 {
                XCTAssertGreaterThanOrEqual(
                    state.camera.altitudeMeters,
                    lastCameraAlt - 0.5,
                    "camera altitude dipped at elapsed \(elapsed)"
                )
                let projection = WorldSceneryProjection(pose: WorldCameraPose(state.camera))
                XCTAssertGreaterThanOrEqual(
                    projection.tiltDegrees,
                    lastTilt - 1.5,
                    "map tilt dove at elapsed \(elapsed)"
                )
            }
            lastCameraAlt = state.camera.altitudeMeters
            lastTilt = WorldSceneryProjection(pose: WorldCameraPose(state.camera)).tiltDegrees
        }
    }

    func testAircraftNeverDropsBelowRunwayAcrossAirportRolls() {
        let airports = Airport.all
        for index in airports.indices {
            let origin = airports[index]
            let destination = airports[(index + 1) % airports.count]
            let leg = FlightLeg(
                origin: origin,
                destination: destination,
                duration: 2 * 60 * 60,
                flightNumber: "TEST-\(origin.code)-\(destination.code)"
            )
            let trajectory = FlightVisualEngine.trajectory(
                for: leg,
                aircraft: AircraftProfile.allCases[index % AircraftProfile.allCases.count],
                environment: .fallback(for: leg, frozenAt: frozenAt),
                shortFlights: false
            )

            assertRollStaysOnRunway(
                trajectory: trajectory,
                runway: trajectory.departureRunway,
                times: strideTimes(from: 0, through: trajectory.schedule.takeoffEnd, count: 100)
            )
            assertRollStaysOnRunway(
                trajectory: trajectory,
                runway: trajectory.arrivalRunway,
                times: strideTimes(
                    from: trajectory.schedule.landingStart,
                    through: trajectory.schedule.legEnd,
                    count: 100
                )
            )
        }
    }

    func testAircraftSpecificRolloutsDecelerateWithoutSpeedSpike() {
        for aircraft in AircraftProfile.allCases {
            let trajectory = makeTrajectory(aircraft: aircraft)
            let times = strideTimes(
                from: trajectory.schedule.landingStart,
                through: trajectory.schedule.legEnd,
                count: 120
            )
            let speeds = times.map {
                trajectory.state(at: $0, seat: "A8").aircraft.groundSpeedMetersPerSecond
            }

            XCTAssertLessThanOrEqual(speeds.max() ?? .infinity, 72, aircraft.name)
            XCTAssertEqual(speeds.last ?? -1, 0, accuracy: 0.001, aircraft.name)
            for index in 1..<speeds.count {
                XCTAssertLessThanOrEqual(speeds[index], speeds[index - 1] + 0.05, aircraft.name)
                let interval = times[index] - times[index - 1]
                let acceleration = abs(speeds[index] - speeds[index - 1]) / interval
                XCTAssertLessThan(acceleration, 4, aircraft.name)
            }
        }
    }

    func testArcLengthSpeedMatchesFiniteDifferenceWorldMotion() {
        let trajectory = makeTrajectory()
        let schedule = trajectory.schedule
        let times = [
            schedule.takeoffEnd * 0.45,
            schedule.takeoffEnd + schedule.climbDuration * 0.08,
            schedule.takeoffEnd + schedule.climbDuration * 0.52,
            schedule.climbEnd + schedule.cruiseDuration * 0.35,
            schedule.descentStart + schedule.descentDuration * 0.55,
            schedule.landingStart + schedule.landingDuration * 0.45,
        ]

        for elapsed in times {
            let delta = 0.2
            let before = trajectory.state(at: elapsed - delta, seat: "A8").aircraft
            let center = trajectory.state(at: elapsed, seat: "A8").aircraft
            let after = trajectory.state(at: elapsed + delta, seat: "A8").aircraft
            let measured = simd_distance(ecef(before), ecef(after)) / (2 * delta)
            let tolerance = max(0.75, center.groundSpeedMetersPerSecond * 0.012)
            XCTAssertEqual(
                measured,
                center.groundSpeedMetersPerSecond,
                accuracy: tolerance,
                "elapsed \(elapsed)"
            )
        }
    }

    func testSeatCameraUsesAircraftBodyTransformAndOppositeWindowSides() {
        let trajectory = makeTrajectory()
        let elapsed = (0...80)
            .map { trajectory.schedule.takeoffEnd + trajectory.schedule.climbDuration * Double($0) / 80 }
            .max { lhs, rhs in
                let left = trajectory.state(at: lhs, seat: "A3").aircraft
                let right = trajectory.state(at: rhs, seat: "A3").aircraft
                return abs(left.pitchDegrees) + abs(left.bankDegrees)
                    < abs(right.pitchDegrees) + abs(right.bankDegrees)
            }!
        let left = trajectory.state(at: elapsed, seat: "A3")
        let right = trajectory.state(at: elapsed, seat: "D20")
        let aircraftPoint = FlightGeodeticPoint(
            coordinate: left.aircraft.coordinate,
            altitudeMeters: left.aircraft.altitudeMeters
        )
        let leftPoint = FlightGeodeticPoint(
            coordinate: left.camera.coordinate,
            altitudeMeters: left.camera.altitudeMeters
        )
        let rightPoint = FlightGeodeticPoint(
            coordinate: right.camera.coordinate,
            altitudeMeters: right.camera.altitudeMeters
        )
        let leftENU = FlightGeodesy.enu(of: leftPoint, relativeTo: aircraftPoint)
        let rightENU = FlightGeodesy.enu(of: rightPoint, relativeTo: aircraftPoint)
        let expectedLeft = expectedEyeOffset(for: left.aircraft, seat: "A3", aircraft: .boeing737800)
        let expectedRight = expectedEyeOffset(for: right.aircraft, seat: "D20", aircraft: .boeing737800)

        XCTAssertEqual(left.camera.side, .left)
        XCTAssertEqual(right.camera.side, .right)
        XCTAssertLessThan(simd_distance(leftENU, expectedLeft), 0.05)
        XCTAssertLessThan(simd_distance(rightENU, expectedRight), 0.05)
        XCTAssertGreaterThan(
            abs(leftENU.z - AircraftProfile.boeing737800.windowHeight),
            0.05
        )
        XCTAssertLessThan(abs(abs(shortestAngle(left.aircraft.courseDegrees, left.camera.headingDegrees)) - 90), 12)
        XCTAssertLessThan(abs(abs(shortestAngle(right.aircraft.courseDegrees, right.camera.headingDegrees)) - 90), 12)
    }

    func testReduceMotionPreservesGeographyAndCapsBankContinuously() {
        let trajectory = makeTrajectory()
        let elapsed = (0...120)
            .map { trajectory.schedule.takeoffEnd + trajectory.schedule.climbDuration * Double($0) / 120 }
            .max { lhs, rhs in
                abs(trajectory.state(at: lhs, seat: "A8").aircraft.bankDegrees)
                    < abs(trajectory.state(at: rhs, seat: "A8").aircraft.bankDegrees)
            }!
        let normal = trajectory.state(at: elapsed, seat: "A8", reduceMotion: false)
        let reduced = trajectory.state(at: elapsed, seat: "A8", reduceMotion: true)

        XCTAssertLessThan(
            location(normal.aircraft.coordinate).distance(from: location(reduced.aircraft.coordinate)),
            0.01
        )
        XCTAssertEqual(normal.aircraft.altitudeMeters, reduced.aircraft.altitudeMeters, accuracy: 0.001)
        XCTAssertEqual(normal.routeProgress, reduced.routeProgress, accuracy: 0.000_001)
        XCTAssertLessThanOrEqual(abs(reduced.aircraft.bankDegrees), 5.000_001)
        XCTAssertLessThanOrEqual(abs(reduced.aircraft.bankDegrees), abs(normal.aircraft.bankDegrees))

        for boundary in [trajectory.schedule.takeoffEnd, trajectory.schedule.landingStart] {
            let before = trajectory.state(at: boundary - 0.01, seat: "A8", reduceMotion: true)
            let after = trajectory.state(at: boundary + 0.01, seat: "A8", reduceMotion: true)
            XCTAssertLessThan(abs(before.aircraft.pitchDegrees - after.aircraft.pitchDegrees), 0.1)
            XCTAssertLessThan(abs(before.aircraft.bankDegrees - after.aircraft.bankDegrees), 0.25)
        }
    }

    func testPortraitFlightWindowDerivesHorizontalFOVFromVerticalFOV() {
        let trajectory = makeTrajectory()
        let camera = trajectory.state(at: 0, seat: "A8").camera

        XCTAssertEqual(camera.fieldOfViewDegrees / 2, 32, accuracy: 0.000_001)
        XCTAssertEqual(
            camera.horizontalFieldOfViewDegrees(forAspectRatio: 0.72) / 2,
            24.223_263,
            accuracy: 0.000_001
        )
    }

    func testSFO01DeparturePutsDowntownTowersOnlyInLeftPortraitFrustum() {
        let trajectory = makeTrajectory(
            departureWeather: weather(
                airport: Airport.byCode("SFO"),
                direction: 28,
                speed: 18
            )
        )
        XCTAssertTrue(trajectory.departureRunway.designator.hasPrefix("01"))
        let elapsed = trajectory.schedule.takeoffEnd + trajectory.schedule.climbDuration * 0.08
        let left = trajectory.state(at: elapsed, seat: "A8")
        let right = trajectory.state(at: elapsed, seat: "D8")

        for landmark in sfoSkylineLandmarks {
            assert(
                landmark.point,
                named: landmark.name,
                isInsidePortraitFrustumOf: left.camera
            )
            assert(
                landmark.point,
                named: landmark.name,
                isOutsidePortraitFrustumOf: right.camera
            )
        }
    }

    func testSFO28DeparturePutsDowntownTowersOnlyInRightPortraitFrustum() {
        let trajectory = makeTrajectory(
            departureWeather: weather(
                airport: Airport.byCode("SFO"),
                direction: 298,
                speed: 18
            )
        )
        XCTAssertTrue(trajectory.departureRunway.designator.hasPrefix("28"))
        let elapsed = trajectory.schedule.takeoffEnd + trajectory.schedule.climbDuration * 0.02
        let left = trajectory.state(at: elapsed, seat: "A8")
        let right = trajectory.state(at: elapsed, seat: "D8")

        for landmark in sfoSkylineLandmarks {
            assert(
                landmark.point,
                named: landmark.name,
                isInsidePortraitFrustumOf: right.camera
            )
            assert(
                landmark.point,
                named: landmark.name,
                isOutsidePortraitFrustumOf: left.camera
            )
        }
    }

    func testReplaySamplesAreDeterministicAndCodable() throws {
        let trajectory = makeTrajectory()
        let first = trajectory.replaySamples(count: 24, seat: "A8")
        let second = trajectory.replaySamples(count: 24, seat: "A8")
        let data = try JSONEncoder().encode(first)
        let decoded = try JSONDecoder().decode([FlightTrajectorySample].self, from: data)

        XCTAssertEqual(first, second)
        XCTAssertEqual(decoded, first)
        XCTAssertEqual(first.first?.routeProgress, 0)
        XCTAssertEqual(first.last?.routeProgress, 1)
        XCTAssertTrue(first.allSatisfy { $0.latitude.isFinite && $0.longitude.isFinite })
    }

    func testLongLegReplaySamplesIncludeChoreographyBoundariesAndDenseRolls() {
        let trajectory = makeTrajectory()
        let samples = trajectory.replaySamples(count: 192, seat: "A8")
        let required = [
            0,
            trajectory.schedule.rotationStart,
            trajectory.schedule.takeoffEnd,
            trajectory.schedule.climbEnd,
            trajectory.schedule.descentStart,
            trajectory.schedule.landingStart,
            trajectory.schedule.legEnd,
        ]

        XCTAssertEqual(samples.count, 192)
        for boundary in required {
            XCTAssertTrue(
                samples.contains { abs($0.elapsed - boundary) < 0.000_001 },
                "missing elapsed boundary \(boundary)"
            )
        }
        let takeoff = samples.filter { $0.elapsed <= trajectory.schedule.takeoffEnd }
        let rollout = samples.filter { $0.elapsed >= trajectory.schedule.landingStart }
        XCTAssertLessThanOrEqual(maximumElapsedGap(takeoff), 2)
        XCTAssertLessThanOrEqual(maximumElapsedGap(rollout), 2)
    }

    func testEveryBookableRouteBuildsFiniteWorldGeometry() {
        for origin in Airport.all {
            for destination in Airport.all where destination != origin {
                let itinerary = RoutePlanner.itinerary(from: origin, to: destination)
                for leg in itinerary.legs {
                    let environment = FlightEnvironmentSnapshot.fallback(
                        for: leg,
                        frozenAt: frozenAt
                    )
                    let trajectory = FlightVisualEngine.trajectory(
                        for: leg,
                        aircraft: .airbusA320neo,
                        environment: environment,
                        shortFlights: false
                    )
                    for elapsed in [
                        0,
                        trajectory.schedule.takeoffEnd,
                        trajectory.schedule.climbEnd,
                        trajectory.schedule.descentStart,
                        trajectory.schedule.landingStart,
                        trajectory.schedule.legEnd,
                    ] {
                        let state = trajectory.state(at: elapsed, seat: "C8")
                        XCTAssertTrue(state.aircraft.coordinate.latitude.isFinite, leg.id)
                        XCTAssertTrue(state.aircraft.coordinate.longitude.isFinite, leg.id)
                        XCTAssertTrue(state.aircraft.altitudeMeters.isFinite, leg.id)
                        XCTAssertTrue(state.aircraft.courseDegrees.isFinite, leg.id)
                        XCTAssertTrue(state.camera.headingDegrees.isFinite, leg.id)
                        XCTAssertTrue(state.camera.pitchDegrees.isFinite, leg.id)
                    }
                }
            }
        }
    }

    func testClearSFOToJFKWorldActuallyTraversesRockiesCoordinates() {
        let samples = makeTrajectory().replaySamples(count: 240, seat: "A8")
        let rockies = samples.filter {
            (-114 ... -104).contains($0.longitude)
                && (34 ... 48).contains($0.latitude)
                && $0.altitudeMeters > 9_000
        }

        XCTAssertFalse(rockies.isEmpty)
        XCTAssertTrue(rockies.allSatisfy { $0.latitude.isFinite && $0.longitude.isFinite })
    }

    func testEnvironmentWeatherSelectionAndFallbackAreStable() {
        let leg = routeLeg()
        let route = weather(airport: Airport.byCode("BOS"), direction: 90, speed: 4)
        let environment = FlightEnvironmentSnapshot(
            frozenAt: frozenAt,
            departureWeather: weather(airport: leg.origin, direction: 20, speed: 8),
            arrivalWeather: weather(airport: leg.destination, direction: 310, speed: 9),
            routeWeather: [route]
        )
        let fallback = FlightEnvironmentSnapshot.fallback(for: leg, frozenAt: frozenAt)

        XCTAssertEqual(environment.weather(at: 0)?.airportCode, "SFO")
        XCTAssertEqual(environment.weather(at: 0.5), route)
        XCTAssertEqual(environment.weather(at: 1)?.airportCode, "JFK")
        XCTAssertEqual(fallback, FlightEnvironmentSnapshot.fallback(for: leg, frozenAt: frozenAt))
        XCTAssertEqual(fallback.departureWeather?.observedAt, frozenAt)
    }

    private func makeTrajectory(
        departureWeather: WeatherSnapshot? = nil,
        aircraft: AircraftProfile = .boeing737800,
        shortFlights: Bool = false
    ) -> FlightTrajectory {
        let leg = routeLeg()
        let environment = FlightEnvironmentSnapshot(
            frozenAt: frozenAt,
            departureWeather: departureWeather,
            arrivalWeather: nil
        )
        return FlightVisualEngine.trajectory(
            for: leg,
            aircraft: aircraft,
            environment: environment,
            shortFlights: shortFlights
        )
    }

    private func routeLeg() -> FlightLeg {
        RoutePlanner.itinerary(
            from: Airport.byCode("SFO"),
            to: Airport.byCode("JFK")
        ).legs[0]
    }

    private func weather(airport: Airport, direction: Int, speed: Int) -> WeatherSnapshot {
        WeatherSnapshot(
            airportCode: airport.code,
            observedAt: frozenAt,
            condition: .clear,
            windDirectionDegrees: direction,
            windSpeedKnots: speed,
            visibilityMiles: 10,
            cloudBaseFeet: nil,
            temperatureCelsius: 18,
            source: "unit fixture"
        )
    }

    private var sfoSkylineLandmarks: [(name: String, point: FlightGeodeticPoint)] {
        [
            (
                "Salesforce Tower",
                FlightGeodeticPoint(
                    latitude: 37.78974,
                    longitude: -122.39610,
                    altitudeMeters: 326
                )
            ),
            (
                "Millennium Tower",
                FlightGeodeticPoint(
                    latitude: 37.79043,
                    longitude: -122.39606,
                    altitudeMeters: 197
                )
            ),
        ]
    }

    private func assert(
        _ target: FlightGeodeticPoint,
        named name: String,
        isInsidePortraitFrustumOf camera: PassengerCameraPose,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let sample = frustumSample(target: target, camera: camera, aspectRatio: 0.72)
        XCTAssertTrue(
            sample.isInside,
            "\(name) should be visible; depth=\(sample.depthMeters)m, horizontal=\(sample.horizontalDegrees)°, vertical=\(sample.verticalDegrees)°",
            file: file,
            line: line
        )
    }

    private func assert(
        _ target: FlightGeodeticPoint,
        named name: String,
        isOutsidePortraitFrustumOf camera: PassengerCameraPose,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let sample = frustumSample(target: target, camera: camera, aspectRatio: 0.72)
        XCTAssertFalse(
            sample.isInside,
            "\(name) is physically impossible from this seat; depth=\(sample.depthMeters)m, horizontal=\(sample.horizontalDegrees)°, vertical=\(sample.verticalDegrees)°",
            file: file,
            line: line
        )
    }

    private func frustumSample(
        target: FlightGeodeticPoint,
        camera: PassengerCameraPose,
        aspectRatio: Double
    ) -> FrustumSample {
        let eye = FlightGeodeticPoint(
            coordinate: camera.coordinate,
            altitudeMeters: camera.altitudeMeters
        )
        let targetENU = FlightGeodesy.enu(of: target, relativeTo: eye)
        let heading = camera.headingDegrees.radiansForTest
        let pitch = camera.pitchDegrees.radiansForTest
        let roll = camera.rollDegrees.radiansForTest
        let forward = SIMD3<Double>(
            sin(heading) * cos(pitch),
            cos(heading) * cos(pitch),
            sin(pitch)
        )
        let unrolledRight = SIMD3<Double>(cos(heading), -sin(heading), 0)
        let unrolledUp = simd_normalize(simd_cross(unrolledRight, forward))
        let right = unrolledRight * cos(roll) + unrolledUp * sin(roll)
        let up = -unrolledRight * sin(roll) + unrolledUp * cos(roll)
        let depth = simd_dot(targetENU, forward)
        let horizontal = atan2(simd_dot(targetENU, right), depth).degreesForTest
        let vertical = atan2(simd_dot(targetENU, up), depth).degreesForTest
        let horizontalHalfFOV = camera.horizontalFieldOfViewDegrees(
            forAspectRatio: aspectRatio
        ) / 2
        let verticalHalfFOV = camera.fieldOfViewDegrees / 2

        return FrustumSample(
            depthMeters: depth,
            horizontalDegrees: horizontal,
            verticalDegrees: vertical,
            isInside: depth > 0
                && abs(horizontal) < horizontalHalfFOV
                && abs(vertical) < verticalHalfFOV
        )
    }

    private struct FrustumSample {
        let depthMeters: Double
        let horizontalDegrees: Double
        let verticalDegrees: Double
        let isInside: Bool
    }

    private func assertRollStaysOnRunway(
        trajectory: FlightTrajectory,
        runway: RunwayProfile,
        times: [TimeInterval],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for elapsed in times {
            let state = trajectory.state(at: elapsed, seat: "A8")
            let surface = runwaySurfaceAltitude(runway, at: state.aircraft.coordinate)
            XCTAssertGreaterThanOrEqual(
                state.aircraft.altitudeMeters,
                surface - 0.15,
                "\(runway.id) below runway at elapsed \(elapsed)",
                file: file,
                line: line
            )
            XCTAssertGreaterThan(
                state.camera.altitudeMeters,
                surface + 0.5,
                "\(runway.id) eye below terrain at elapsed \(elapsed)",
                file: file,
                line: line
            )
        }
    }

    private func runwaySurfaceAltitude(
        _ runway: RunwayProfile,
        at coordinate: CLLocationCoordinate2D
    ) -> Double {
        let total = location(runway.threshold.coordinate).distance(
            from: location(runway.oppositeThreshold.coordinate)
        )
        let traveled = location(runway.threshold.coordinate).distance(from: location(coordinate))
        let fraction = min(1, max(0, traveled / max(1, total)))
        return runway.threshold.altitudeMeters
            + (runway.oppositeThreshold.altitudeMeters - runway.threshold.altitudeMeters) * fraction
    }

    private func strideTimes(
        from start: TimeInterval,
        through end: TimeInterval,
        count: Int
    ) -> [TimeInterval] {
        (0...max(1, count)).map {
            start + (end - start) * Double($0) / Double(max(1, count))
        }
    }

    private func expectedEyeOffset(
        for pose: AircraftPose,
        seat: String,
        aircraft: AircraftProfile
    ) -> SIMD3<Double> {
        let sideSign = WindowSide(seat: seat) == .left ? -1.0 : 1.0
        let row = Int(seat.filter(\.isNumber)) ?? 8
        let forwardOffset = Double(8 - min(30, max(1, row))) * 0.79
        let lateralOffset = sideSign * 2.05
        let heading = pose.courseDegrees.radiansForTest
        let pitch = pose.pitchDegrees.radiansForTest
        let bank = pose.bankDegrees.radiansForTest
        let horizontalForward = SIMD3<Double>(sin(heading), cos(heading), 0)
        let horizontalRight = SIMD3<Double>(cos(heading), -sin(heading), 0)
        let worldUp = SIMD3<Double>(0, 0, 1)
        let bodyForward = horizontalForward * cos(pitch) + worldUp * sin(pitch)
        let pitchedUp = worldUp * cos(pitch) - horizontalForward * sin(pitch)
        let bodyRight = horizontalRight * cos(bank) - pitchedUp * sin(bank)
        let bodyUp = horizontalRight * sin(bank) + pitchedUp * cos(bank)
        var offset = bodyForward * forwardOffset
            + bodyRight * lateralOffset
            + bodyUp * aircraft.windowHeight
        let minimumUp = aircraft.windowHeight * 0.72
        if offset.z < minimumUp {
            offset.z = minimumUp
        }
        return offset
    }

    private func ecef(_ pose: AircraftPose) -> SIMD3<Double> {
        FlightGeodesy.ecef(
            FlightGeodeticPoint(
                coordinate: pose.coordinate,
                altitudeMeters: pose.altitudeMeters
            )
        )
    }

    private func quaternionAngleDegrees(_ lhs: simd_quatd, _ rhs: simd_quatd) -> Double {
        let cosine = min(1, max(-1, abs(simd_dot(lhs.vector, rhs.vector))))
        return 2 * acos(cosine) * 180 / .pi
    }

    private func maximumElapsedGap(_ samples: [FlightTrajectorySample]) -> TimeInterval {
        zip(samples, samples.dropFirst()).map { pair in
            pair.1.elapsed - pair.0.elapsed
        }.max() ?? 0
    }

    private func location(_ coordinate: CLLocationCoordinate2D) -> CLLocation {
        CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private func distance(_ lhs: AircraftPose, _ rhs: AircraftPose) -> Double {
        let horizontal = location(lhs.coordinate).distance(from: location(rhs.coordinate))
        return hypot(horizontal, lhs.altitudeMeters - rhs.altitudeMeters)
    }

    private func shortestAngle(_ lhs: Double, _ rhs: Double) -> Double {
        var delta = (rhs - lhs).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }
}

final class WorldSceneryProviderPolicyTests: XCTestCase {
    func testOnlySelectedMapKitProviderMountsTheApple3DEngine() {
        XCTAssertTrue(WorldSceneryLayerPolicy.needsMapKit(under: .mapKit))
        XCTAssertFalse(WorldSceneryLayerPolicy.needsMapKit(under: .procedural))
        XCTAssertFalse(
            WorldSceneryLayerPolicy.mapKitIsVisible(
                under: .mapKit,
                loadState: .loading
            )
        )
        XCTAssertTrue(
            WorldSceneryLayerPolicy.mapKitIsVisible(
                under: .mapKit,
                loadState: .ready
            )
        )
    }

    func testMapKitIsPrimaryWhenEnabledActiveAndOnline() {
        XCTAssertEqual(
            WorldSceneryProviderPolicy.provider(
                realWorldTwinEnabled: true,
                appIsActive: true,
                isOnline: true,
                thermalState: .nominal
            ),
            .mapKit
        )
    }

    func testSeriousThermalPressureFallsBackToProceduralWorld() {
        for thermalState in [ProcessInfo.ThermalState.serious, .critical] {
            XCTAssertEqual(
                WorldSceneryProviderPolicy.provider(
                    realWorldTwinEnabled: true,
                    appIsActive: true,
                    isOnline: true,
                    thermalState: thermalState
                ),
                .procedural
            )
        }
    }

    func testOfflineInactiveAndDisabledStatesUseProceduralFallback() {
        let inputs: [(enabled: Bool, active: Bool, online: Bool)] = [
            (true, true, false),
            (true, false, true),
            (false, true, true),
        ]
        for input in inputs {
            XCTAssertEqual(
                WorldSceneryProviderPolicy.provider(
                    realWorldTwinEnabled: input.enabled,
                    appIsActive: input.active,
                    isOnline: input.online,
                    thermalState: .nominal
                ),
                .procedural
            )
        }
    }

    func testCameraProjectionNormalizesAndBoundsProviderInputs() {
        let pose = WorldCameraPose(
            coordinate: CLLocationCoordinate2D(latitude: 37.619, longitude: -122.375),
            altitudeMeters: 2_500,
            headingDegrees: -25,
            tiltDegrees: 95,
            rollDegrees: 63,
            rangeMeters: nil,
            fieldOfViewDegrees: 140
        )
        let projection = WorldSceneryProjection(pose: pose)

        XCTAssertEqual(projection.headingDegrees, 335, accuracy: 0.001)
        XCTAssertEqual(projection.tiltDegrees, 87.5, accuracy: 0.001)
        XCTAssertEqual(projection.rollDegrees, 45, accuracy: 0.001)
        XCTAssertEqual(projection.fieldOfViewDegrees, 100, accuracy: 0.001)
        XCTAssertTrue(projection.rangeMeters.isFinite)
        XCTAssertGreaterThan(projection.rangeMeters, 2_500)
        let reconstructedAltitude = projection.targetAltitudeMeters
            + projection.rangeMeters * cos(projection.tiltDegrees.radiansForTest)
        XCTAssertEqual(reconstructedAltitude, pose.altitudeMeters, accuracy: 0.001)
    }
}

private extension Double {
    var radiansForTest: Double { self * .pi / 180 }
    var degreesForTest: Double { self * 180 / .pi }
}
