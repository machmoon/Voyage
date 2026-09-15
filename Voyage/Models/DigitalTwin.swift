import Foundation

/// The cabin geometry and takeoff performance used by the passenger-window world.
enum AircraftProfile: String, CaseIterable, Codable, Identifiable {
    case voyageClassic
    case boeing737800
    case airbusA320neo
    case boomOverture

    var id: String { rawValue }

    var name: String {
        switch self {
        case .voyageClassic: return "Voyage Classic"
        case .boeing737800: return "Boeing 737-800"
        case .airbusA320neo: return "Airbus A320neo"
        case .boomOverture: return "Boom Overture"
        }
    }

    var symbol: String {
        switch self {
        case .voyageClassic: return "airplane"
        case .boeing737800: return "airplane.departure"
        case .airbusA320neo: return "airplane.circle"
        case .boomOverture: return "paperplane.fill"
        }
    }

    /// Rotation speed expressed in knots for the visual speed curve.
    var rotationKnots: Double {
        switch self {
        case .voyageClassic: return 132
        case .boeing737800: return 148
        case .airbusA320neo: return 143
        // A slender delta carries far less lift at low speed, so it holds the
        // runway well past a narrowbody's rotation and lifts off nose-high.
        case .boomOverture: return 198
        }
    }

    var windowHeight: Double {
        switch self {
        case .voyageClassic: return 2.2
        case .boeing737800: return 2.7
        case .airbusA320neo: return 2.55
        // Supersonic cabins carry small windows: less structure to cut, less
        // to fail at altitude.
        case .boomOverture: return 1.6
        }
    }

    /// The cabin as a passenger would meet it on the real aircraft: the same
    /// class split, seat letters, and exit rows an airline seat map shows.
    var cabinPlan: CabinPlan {
        switch self {
        case .boeing737800:
            return CabinPlan(
                cabins: [
                    .init(name: "First", rows: Array(1...4), left: CabinPlan.pairLeft,
                          right: CabinPlan.pairRight, isPremium: true),
                    // Real 737-800 cabins have no rows 5 or 6. Keeping the gap
                    // costs nothing and is the kind of detail a frequent flyer
                    // notices immediately.
                    .init(name: "Extra Legroom", rows: Array(7...11), left: CabinPlan.tripleLeft,
                          right: CabinPlan.tripleRight, isPremium: false),
                    .init(name: "Main Cabin", rows: Array(12...22), left: CabinPlan.tripleLeft,
                          right: CabinPlan.tripleRight, isPremium: false)
                ],
                exitRows: [11, 12]
            )
        case .airbusA320neo:
            return CabinPlan(
                cabins: [
                    .init(name: "First", rows: Array(1...3), left: CabinPlan.pairLeft,
                          right: CabinPlan.pairRight, isPremium: true),
                    .init(name: "Extra Legroom", rows: Array(7...10), left: CabinPlan.tripleLeft,
                          right: CabinPlan.tripleRight, isPremium: false),
                    .init(name: "Main Cabin", rows: Array(11...20), left: CabinPlan.tripleLeft,
                          right: CabinPlan.tripleRight, isPremium: false)
                ],
                exitRows: [10, 11]
            )
        case .voyageClassic:
            return CabinPlan(
                // Fictional airframe, real narrowbody layout: 2-2 up front and
                // 3-3 behind, the way every single-aisle cabin you can actually
                // board is arranged.
                cabins: [
                    .init(name: "First", rows: Array(1...3), left: CabinPlan.pairLeft,
                          right: CabinPlan.pairRight, isPremium: true),
                    .init(name: "Extra Legroom", rows: Array(7...10), left: CabinPlan.tripleLeft,
                          right: CabinPlan.tripleRight, isPremium: false),
                    .init(name: "Main Cabin", rows: Array(11...24), left: CabinPlan.tripleLeft,
                          right: CabinPlan.tripleRight, isPremium: false)
                ],
                exitRows: [10, 11]
            )
        case .boomOverture:
            return CabinPlan(
                // Overture seats 64-80 in an all-business 1-1 cabin: one seat
                // either side of the aisle, every row a window and an aisle.
                // Sixty-four seats over thirty-two rows is the published
                // layout, which is why this cabin is so much longer and
                // narrower than the narrowbodies.
                cabins: [
                    .init(name: "Founders", rows: Array(1...4), left: CabinPlan.singleLeft,
                          right: CabinPlan.singleRight, isPremium: true),
                    .init(name: "Main Cabin", rows: Array(5...32), left: CabinPlan.singleLeft,
                          right: CabinPlan.singleRight, isPremium: false)
                ],
                exitRows: [16, 17]
            )
        }
    }
}

/// A top-down cabin plan: which rows exist, what they are called, where the
/// wing box sits. The airframe around them is `AircraftProfile.planform`.
struct CabinPlan {
    /// Two-abreast cabins skip B and E so the letters still line up with the
    /// three-abreast rows behind them, exactly as real narrowbodies do.
    static let pairLeft = ["A", "C"]
    static let pairRight = ["D", "F"]
    static let tripleLeft = ["A", "B", "C"]
    static let tripleRight = ["D", "E", "F"]
    /// One seat either side of the aisle, as on a supersonic cabin. A stays
    /// port and D starboard so `WindowSide(seat:)` still reads the side right.
    static let singleLeft = ["A"]
    static let singleRight = ["D"]

    struct Cabin: Identifiable {
        let name: String
        let rows: [Int]
        let left: [String]
        let right: [String]
        /// Tier-gated, and drawn as the wider recliner.
        let isPremium: Bool

        var id: String { name }
        var seatsPerRow: Int { left.count + right.count }
    }

    let cabins: [Cabin]
    let exitRows: Set<Int>

    /// The widest row in the plan decides how big every seat can be.
    var maxSeatsPerRow: Int { cabins.map(\.seatsPerRow).max() ?? 4 }

    /// The row the wing is placed against: the last over-wing exit.
    var wingAnchorRow: Int? { exitRows.max() }

    func cabin(forRow row: Int) -> Cabin? {
        cabins.first { $0.rows.contains(row) }
    }

    func isPremiumRow(_ row: Int) -> Bool {
        cabin(forRow: row)?.isPremium ?? false
    }
}

enum WindowSide: String, Codable {
    case left
    case right

    /// Seats are labelled letter-first ("C10"). A/B/C sit port of the aisle on
    /// every cabin plan, D/E/F starboard.
    init(seat: String) {
        let letter = seat.first.map { String($0).uppercased() } ?? "A"
        self = ["A", "B", "C"].contains(letter) ? .left : .right
    }
}

/// Frozen at departure so a completed flight can be replayed exactly as it looked.
struct WeatherSnapshot: Codable, Equatable {
    let airportCode: String
    let observedAt: Date
    let condition: SkyCondition
    let windDirectionDegrees: Int?
    let windSpeedKnots: Int?
    let visibilityMiles: Double?
    let cloudBaseFeet: Int?
    let temperatureCelsius: Double?
    let source: String

    static func fallback(for airport: Airport, condition: SkyCondition = .clear) -> WeatherSnapshot {
        WeatherSnapshot(
            airportCode: airport.code,
            observedAt: .now,
            condition: condition,
            windDirectionDegrees: nil,
            windSpeedKnots: nil,
            visibilityMiles: nil,
            cloudBaseFeet: nil,
            temperatureCelsius: nil,
            source: "on-device fallback"
        )
    }
}

enum DepartureProfile: String, Codable, CaseIterable {
    case standard
    case sfoBay
    case sfoCity

    var displayName: String {
        switch self {
        case .standard: return "Local departure"
        case .sfoBay: return "Bay departure"
        case .sfoCity: return "City departure"
        }
    }
}

/// Airport metadata compiled into the app. The coordinates and source data are
/// intentionally kept outside the runtime renderer; it receives only this compact world contract.
enum AirportWorldCatalog {
    static let revision = "2026.07.20"

    static func departureProfile(for airport: Airport, weather: WeatherSnapshot?) -> DepartureProfile {
        guard airport.code == "SFO" else { return .standard }
        // Westerly flow uses the Bay-facing signature; northerly flow selects
        // the alternate city-facing composition. This is a visual operational model, not ATC clearance.
        let wind = weather?.windDirectionDegrees ?? 280
        return (wind >= 220 && wind <= 359) || wind < 40 ? .sfoBay : .sfoCity
    }
}

/// A pure, testable description of one rendered instant. Metal owns pixels;
/// FlightSession owns elapsed time and passes it through here.
struct AirportWorldFrame: Equatable {
    let airportCode: String
    let profile: DepartureProfile
    let aircraft: AircraftProfile
    let side: WindowSide
    let rollProgress: Double
    let climbProgress: Double
    let pitchDegrees: Double
    let bankDegrees: Double
    let cloudAmount: Double
    let visibility: Double
    let wetRunway: Bool
    let elapsed: TimeInterval
    let camera: AirportWorldCameraPose
}

/// A renderer-independent passenger camera. Positions are expressed in meters
/// in the authored airport world's runway-local coordinate system: +x is the
/// right side of the aircraft, +y is up, and the departure roll travels -z.
struct AirportWorldCameraPose: Equatable {
    let position: SIMD3<Double>
    let yawDegrees: Double
    let pitchDegrees: Double
    let rollDegrees: Double
    let fieldOfViewDegrees: Double
}

struct AirportWorldSimulation {
    let airport: Airport
    let aircraft: AircraftProfile
    let seat: String
    let weather: WeatherSnapshot?

    /// `rollDuration` and `climbSpan` come from the leg's phase schedule;
    /// the static defaults exist for callers without a trajectory.
    func frame(phase: LegPhase, legElapsed: TimeInterval, altitudeFeet: Int,
               rollDuration rawRoll: TimeInterval = FlightSession.takeoffRollDuration,
               climbSpan rawClimb: TimeInterval = FlightSession.climbEndsAt - FlightSession.takeoffRollDuration) -> AirportWorldFrame {
        let rollDuration = max(0.1, rawRoll)
        let climbSpan = max(0.1, rawClimb)
        let roll = phase == .takeoffRoll ? min(1, max(0, legElapsed / rollDuration)) : 1
        let climb: Double
        switch phase {
        case .takeoffRoll: climb = 0
        case .climb: climb = min(1, max(0, (legElapsed - rollDuration) / climbSpan))
        case .cruise: climb = 1
        case .descent: climb = min(1, max(0.2, Double(altitudeFeet) / 36_000))
        case .landing: climb = 0
        }
        let rotation = smoothstep(0.72, 0.98, roll)
        let pitch = phase == .takeoffRoll ? rotation * 10 : (phase == .climb ? 8 * (1 - climb * 0.45) : 0)
        let side = WindowSide(seat: seat)
        // Climb-out tilt, matched to `IllustratedWindowSceneView.bankAngle` so the
        // two window worlds agree. The sign is deliberately NOT flipped by window
        // side: the aircraft rolls one way, and negating it for the right-hand
        // seat made the horizon swing the opposite direction from the illustrated
        // layer, which read as the view rotating one way and then hard back.
        let bank: Double
        switch phase {
        case .takeoffRoll:
            bank = Self.climbTilt * smoothstep(0.66, 1, roll)
        case .climb:
            bank = Self.climbTilt * (1 - smoothstep(0.15, 0.85, climb))
        case .cruise, .descent, .landing:
            bank = 0
        }
        let visibilityMiles = weather?.visibilityMiles ?? 10
        let camera = cameraPose(side: side, roll: roll, climb: climb, pitch: pitch, bank: bank)
        return AirportWorldFrame(
            airportCode: airport.code,
            profile: AirportWorldCatalog.departureProfile(for: airport, weather: weather),
            aircraft: aircraft,
            side: side,
            rollProgress: roll,
            climbProgress: climb,
            pitchDegrees: pitch,
            bankDegrees: bank,
            cloudAmount: weather?.condition.cloudAmount ?? 0.25,
            visibility: min(1, max(0.16, visibilityMiles / 10)),
            wetRunway: weather?.condition.isPrecipitating ?? false,
            elapsed: legElapsed,
            camera: camera
        )
    }

    /// Produces the same pose for a given session instant, making live flight,
    /// screenshots, and logbook replay visually identical.
    private func cameraPose(side: WindowSide, roll: Double, climb: Double,
                            pitch: Double, bank: Double) -> AirportWorldCameraPose {
        let sideSign = side == .left ? -1.0 : 1.0
        let climbEase = smoothstep(0, 1, climb)
        let groundDistance = 2_450 * roll
        let airborneDistance = 3_200 * climbEase
        let height = aircraft.windowHeight + 700 * climbEase

        // A passenger window looks across the wing, never down the aircraft's
        // nose. Begin nearly perpendicular to the runway and ease toward a
        // slightly forward-looking side view during climb so landmarks enter
        // naturally without turning the scene into a cockpit camera.
        let sideLook = sideSign * (78 - 20 * climbEase)

        // Looking down is a cruise behaviour, not a departure one. Applying it
        // from wheels-up drops the horizon exactly when the aircraft rotates,
        // so the climb reads as a descent. Hold the view level off the runway
        // and only tip toward the ground once the climb is established.
        let lookDown = 8.5 * smoothstep(0.35, 1, climb)
        return AirportWorldCameraPose(
            position: SIMD3(sideSign * 2.25, height, 180 - groundDistance - airborneDistance),
            yawDegrees: -sideLook,
            pitchDegrees: -(pitch * 0.42 * smoothstep(0.2, 0.8, climb) + lookDown),
            rollDegrees: bank,
            fieldOfViewDegrees: 66
        )
    }

    /// Peak climb-out tilt, in degrees. Kept identical to
    /// `IllustratedWindowSceneView.climbTilt` so switching window modes
    /// mid-climb does not jump the horizon.
    static let climbTilt: Double = 4.0

    private func smoothstep(_ edge0: Double, _ edge1: Double, _ value: Double) -> Double {
        let t = min(1, max(0, (value - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }
}

struct ReplayRouteSample: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let progress: Double
}

enum ReplayRouteRecorder {
    static func samples(for itinerary: Itinerary, count: Int = 72) -> [ReplayRouteSample] {
        let total = max(1, itinerary.totalFocusDuration)
        return (0..<max(2, count)).map { index in
            let progress = Double(index) / Double(max(1, count - 1))
            var remaining = progress * total
            for leg in itinerary.legs {
                if remaining <= leg.duration {
                    let coordinate = GreatCircle.point(from: leg.origin.coordinate, to: leg.destination.coordinate,
                                                       fraction: remaining / max(1, leg.duration))
                    return ReplayRouteSample(latitude: coordinate.latitude, longitude: coordinate.longitude, progress: progress)
                }
                remaining -= leg.duration
            }
            let destination = itinerary.destination.coordinate
            return ReplayRouteSample(latitude: destination.latitude, longitude: destination.longitude, progress: progress)
        }
    }
}
