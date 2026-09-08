import SwiftUI
import MapKit

/// Shared globe rendering for the two screens that draw the satellite Earth:
/// `HomeView` and `OnboardingView`.
///
/// Onboarding's last screen cross-dissolves into Home on the same camera
/// framing, so any difference between the two shows up as a jump at the seam.
/// These pieces were duplicated in both files and drifted apart five ways: the
/// route was a flat stroke in one and a tapered arc in the other, the pins were
/// drawn in the wrong order relative to the line, the destination dot differed
/// by 2pt, the label carried a different shadow, and the origin pin showed its
/// airport code on Home but not in onboarding. Anything both globes draw
/// belongs here rather than in either view.
enum GlobeRoute {

    // MARK: Arc

    /// One drawn piece of the arc. The route is cut into short geodesic pieces
    /// so opacity and width can vary along it; a single polyline can only be
    /// one flat weight end to end.
    struct Segment: Identifiable {
        let id: Int
        let start: CLLocationCoordinate2D
        let end: CLLocationCoordinate2D
        /// 0 at the pins, 1 across the middle of the leg.
        let strength: Double
    }

    /// Samples per leg. Enough that the taper reads as continuous without
    /// putting a large number of overlays on the map.
    private static let sampleCount = 18

    /// Builds the drawable arc for any number of legs. Home passes a booked
    /// itinerary; onboarding passes a single sample leg.
    static func segments(
        legs: [(start: CLLocationCoordinate2D, end: CLLocationCoordinate2D)]
    ) -> [Segment] {
        var segments: [Segment] = []
        for leg in legs {
            let points = GreatCircle.points(from: leg.start, to: leg.end, count: sampleCount)
            for index in 0..<(points.count - 1) {
                let midpoint = (Double(index) + 0.5) / Double(points.count - 1)
                segments.append(
                    Segment(id: segments.count,
                            start: points[index],
                            end: points[index + 1],
                            strength: strength(at: midpoint))
                )
            }
        }
        return segments
    }

    /// The arc lifts out of the origin, runs at full weight across the middle,
    /// and settles back into the destination, so it reads as a path flown
    /// rather than a line painted between two dots. Because this eases per leg,
    /// a connection naturally pinches at the stop.
    static func strength(at fraction: Double) -> Double {
        let fromNearestEnd = min(fraction, 1 - fraction) * 2
        return smoothstep(0, 0.32, fromNearestEnd)
    }

    static func smoothstep(_ edge0: Double, _ edge1: Double, _ value: Double) -> Double {
        let t = min(1, max(0, (value - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    /// The arc itself: a wide faint pass for glow, then the line on top.
    ///
    /// Call this BEFORE any annotation. Map content draws in declaration order,
    /// so declaring pins first lays the line over the top of every dot it
    /// passes and makes the arc read as a pipe crossing the airports.
    ///
    /// Main-actor isolated because `ForEach` is: both callers build this inside
    /// a `Map` in a view body, so this costs them nothing.
    @MainActor
    @MapContentBuilder
    static func arc(_ segments: [Segment]) -> some MapContent {
        ForEach(segments) { segment in
            MapPolyline(coordinates: [segment.start, segment.end],
                        contourStyle: .geodesic)
                .stroke(
                    Theme.accent.opacity(0.09 + 0.13 * segment.strength),
                    style: StrokeStyle(lineWidth: 7 + 3 * segment.strength, lineCap: .round)
                )
        }
        ForEach(segments) { segment in
            MapPolyline(coordinates: [segment.start, segment.end],
                        contourStyle: .geodesic)
                .stroke(
                    Theme.accent.opacity(0.32 + 0.68 * segment.strength),
                    style: StrokeStyle(lineWidth: 1.7 + 1.7 * segment.strength, lineCap: .round)
                )
        }
    }

    // MARK: Pins

    /// Where an airport sits in the route being shown. Pin weight follows from
    /// this, so the booked route reads at a glance instead of every airport on
    /// the globe competing with it.
    enum PinRole {
        case origin
        case connection
        case destination
        /// Nothing booked yet: every airport is a candidate.
        case available
        /// Booked, but not part of this route.
        case offRoute
    }

    /// The globe has no label declutter of its own, so pins that sit within a
    /// few degrees of each other stack their codes (SEA landed on top of YVR).
    /// The more northern of a close pair carries its code above the dot.
    static func labelSitsAbove(_ airport: Airport) -> Bool {
        Airport.all.contains { other in
            other != airport
                && abs(other.latitude - airport.latitude) < 6
                && abs(other.longitude - airport.longitude) < 6
                && other.latitude < airport.latitude
        }
    }
}

/// The dot itself. Deliberately carries no shadow: the stacked halo on the
/// label does the legibility work, and a shadow here made the two globes
/// disagree at the cross-dissolve.
struct GlobePinDot: View {
    let role: GlobeRoute.PinRole

    var body: some View {
        switch role {
        case .origin:
            ZStack {
                Circle()
                    .fill(.white)
                    .frame(width: 26, height: 26)
                    .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                Image(systemName: "house.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black)
            }
        case .destination:
            ZStack {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 26, height: 26)
                    .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                Image(systemName: "airplane.arrival")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
        case .connection:
            // A waypoint is something you pass through, so it is drawn as a
            // ring rather than a filled endpoint. Smaller than either end,
            // which also stops it fighting the destination for attention.
            ZStack {
                Circle()
                    .fill(Theme.ink.opacity(0.8))
                    .frame(width: 17, height: 17)
                    .overlay(Circle().strokeBorder(Theme.accent, lineWidth: 2.5))
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 4, height: 4)
            }
        case .available, .offRoute:
            ZStack {
                Circle()
                    .fill(.black.opacity(0.55))
                    .frame(width: 20, height: 20)
                    .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                Image(systemName: "airplane.arrival")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }
}

/// The airport code under (or over) a pin.
struct GlobeAirportCode: View {
    let airport: Airport

    var body: some View {
        Text(airport.code)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            // A stacked halo rather than one soft drop shadow. The globe runs
            // from bright daylight terrain to near-black ocean, and a single
            // shadow disappears against the lit half.
            .shadow(color: .black.opacity(0.9), radius: 1)
            .shadow(color: .black.opacity(0.65), radius: 3)
            .shadow(color: .black.opacity(0.4), radius: 6)
    }
}

/// A complete pin: dot plus code, with the code decluttered onto whichever
/// side keeps it off a close neighbour's label.
struct GlobeAirportPin: View {
    let airport: Airport
    let role: GlobeRoute.PinRole

    var body: some View {
        VStack(spacing: 3) {
            if GlobeRoute.labelSitsAbove(airport) { GlobeAirportCode(airport: airport) }
            GlobePinDot(role: role)
            if !GlobeRoute.labelSitsAbove(airport) { GlobeAirportCode(airport: airport) }
        }
    }
}
