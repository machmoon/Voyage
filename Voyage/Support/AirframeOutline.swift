import SwiftUI

/// Turns an `AirframePlanform` into paths, for the seat map and the launch
/// flyover alike.
///
/// Metres become points through two scales. Across the aircraft, the fuselage
/// width sets the scale, so the wing's span is measured in true fuselage
/// widths. Along it, the seat pitch sets the scale, so the wing's chord covers
/// the true number of rows. The two differ on the seat map, where the seat grid
/// is not quite square to the cabin, and match on the flyover.
///
/// Every part is its own path. iOS 17 has no path union, and filling mirrored
/// panels as one path lets their opposite windings cut holes in each other.
struct AirframeOutline {
    let planform: AirframePlanform
    let midX: CGFloat
    /// Points per metre across the aircraft.
    let xScale: CGFloat
    /// Points per metre along the aircraft.
    let yScale: CGFloat
    let noseTipY: CGFloat
    /// Where the over-wing exit sits. The wing is placed around it.
    let exitY: CGFloat
    let tailEndY: CGFloat

    /// The whole aircraft at one scale, nose tip at `noseTipY`.
    init(planform: AirframePlanform, scale: CGFloat, midX: CGFloat, noseTipY: CGFloat) {
        self.init(planform: planform, midX: midX, xScale: scale, yScale: scale,
                  noseTipY: noseTipY,
                  exitY: noseTipY + CGFloat(planform.exitStation) * scale,
                  tailEndY: noseTipY + CGFloat(planform.length) * scale)
    }

    init(planform: AirframePlanform, midX: CGFloat, xScale: CGFloat, yScale: CGFloat,
         noseTipY: CGFloat, exitY: CGFloat, tailEndY: CGFloat) {
        self.planform = planform
        self.midX = midX
        self.xScale = xScale
        self.yScale = yScale
        self.noseTipY = noseTipY
        self.exitY = exitY
        self.tailEndY = tailEndY
    }

    private var halfBody: CGFloat { CGFloat(planform.fuselageWidth) / 2 * xScale }

    // MARK: Fuselage

    /// Nose dome, constant section, tailcone ending in the APU exhaust stub.
    var fuselage: Path {
        let left = midX - halfBody
        let right = midX + halfBody
        let shoulder = noseTipY + CGFloat(planform.noseTaper) * yScale
        let tailStart = tailEndY - CGFloat(planform.tailTaper) * yScale
        let tailHalf = max(1.5, halfBody * 0.06)
        let fullness = CGFloat(planform.noseFullness)
        let noseLength = shoulder - noseTipY

        var path = Path()
        path.move(to: CGPoint(x: left, y: shoulder))
        // A blunt nose reaches full width early and has a wide, flat tip; a
        // spike carries the taper all the way to a point.
        path.addCurve(
            to: CGPoint(x: midX, y: noseTipY),
            control1: CGPoint(x: left, y: shoulder - noseLength * (0.45 + fullness * 0.25)),
            control2: CGPoint(x: midX - halfBody * (0.08 + fullness * 0.55), y: noseTipY)
        )
        path.addCurve(
            to: CGPoint(x: right, y: shoulder),
            control1: CGPoint(x: midX + halfBody * (0.08 + fullness * 0.55), y: noseTipY),
            control2: CGPoint(x: right, y: shoulder - noseLength * (0.45 + fullness * 0.25))
        )
        path.addLine(to: CGPoint(x: right, y: tailStart))
        let taper = tailEndY - tailStart
        path.addCurve(
            to: CGPoint(x: midX + tailHalf, y: tailEndY),
            control1: CGPoint(x: right, y: tailStart + taper * 0.45),
            control2: CGPoint(x: midX + tailHalf * 3, y: tailEndY - taper * 0.22)
        )
        path.addLine(to: CGPoint(x: midX - tailHalf, y: tailEndY))
        path.addCurve(
            to: CGPoint(x: left, y: tailStart),
            control1: CGPoint(x: midX - tailHalf * 3, y: tailEndY - taper * 0.22),
            control2: CGPoint(x: left, y: tailStart + taper * 0.45)
        )
        path.closeSubpath()
        return path
    }

    /// Flight deck glazing seen from above: two front panes meeting at a
    /// centre post, and a side window wrapping back on each side. Placed a
    /// little behind the nose tip, where the crown starts to rise. Clip it to
    /// `fuselage` when drawing: on a slender nose the panes are wider than
    /// the skin at that station.
    var windshield: [Path] {
        let noseLength = CGFloat(planform.noseTaper) * yScale
        // Pointed noses push the flight deck further back.
        let frontY = noseTipY + noseLength * (0.36 - CGFloat(planform.noseFullness) * 0.08)
        // Shallow panes. A slender nose caps them by width, or they read as a
        // visor rather than glazing.
        let depth = max(1.6, min(noseLength * 0.045, halfBody * 0.1))
        let halfWidth = halfBody * 0.44
        let post = max(0.6, halfBody * 0.025)
        let bow = depth * 1.6

        var panes: [Path] = []
        for side: CGFloat in [-1, 1] {
            // Front pane: from the centre post out to the corner post, bowed
            // forward so the glazing follows the nose.
            var front = Path()
            front.move(to: CGPoint(x: midX + side * post, y: frontY - bow * 0.35))
            front.addQuadCurve(to: CGPoint(x: midX + side * halfWidth, y: frontY + bow * 0.55),
                               control: CGPoint(x: midX + side * halfWidth * 0.55, y: frontY - bow * 0.3))
            front.addLine(to: CGPoint(x: midX + side * halfWidth * 0.9, y: frontY + bow * 0.55 + depth))
            front.addQuadCurve(to: CGPoint(x: midX + side * post, y: frontY - bow * 0.35 + depth),
                               control: CGPoint(x: midX + side * halfWidth * 0.5, y: frontY - bow * 0.3 + depth))
            front.closeSubpath()
            panes.append(front)

            // Side window: a short sliver behind the corner post.
            let gap = post * 1.6
            var sideWindow = Path()
            sideWindow.move(to: CGPoint(x: midX + side * (halfWidth + gap * 0.4), y: frontY + bow * 0.55 + gap))
            sideWindow.addLine(to: CGPoint(x: midX + side * halfBody * 0.8, y: frontY + bow * 0.55 + depth * 1.4 + gap))
            sideWindow.addLine(to: CGPoint(x: midX + side * halfBody * 0.74, y: frontY + bow * 0.55 + depth * 2.1 + gap))
            sideWindow.addLine(to: CGPoint(x: midX + side * (halfWidth * 0.9 + gap * 0.4), y: frontY + bow * 0.55 + depth + gap))
            sideWindow.closeSubpath()
            panes.append(sideWindow)
        }
        return panes
    }

    // MARK: Wing

    private var wingRootLeadingY: CGFloat {
        exitY - CGFloat(planform.exitChordFraction * planform.wing.rootChord) * yScale
    }

    /// A point on the wing, `s` metres outboard of the fuselage side and at
    /// chord fraction `f`.
    private func wingPoint(side: CGFloat, s: Double, f: Double) -> CGPoint {
        let wing = planform.wing
        let lead: CGFloat = wingRootLeadingY + CGFloat(wing.leadingEdgeOffset(at: s)) * yScale
        let outboard: CGFloat = halfBody + CGFloat(s) * xScale
        let aft: CGFloat = CGFloat(f * wing.chord(at: s)) * yScale
        return CGPoint(x: midX + side * outboard, y: lead + aft)
    }

    /// One wing, root buried a little inside the fuselage so no seam shows.
    func wing(side: CGFloat) -> Path {
        let span = planform.wing.span
        let rootTop = wingPoint(side: side, s: 0, f: 0)
        let rootBottom = wingPoint(side: side, s: 0, f: 1)
        var path = Path()
        path.move(to: CGPoint(x: midX + side * halfBody * 0.5, y: rootTop.y))
        path.addLine(to: wingPoint(side: side, s: span, f: 0))
        path.addLine(to: wingPoint(side: side, s: span, f: 1))
        path.addLine(to: rootBottom)
        path.addLine(to: CGPoint(x: midX + side * halfBody * 0.5, y: rootBottom.y))
        path.closeSubpath()
        return path
    }

    /// Slat line along the leading edge, flap and aileron hinge lines along
    /// the trailing edge: the panel breaks that make a flat shape read as a
    /// wing.
    func wingPanelLines(side: CGFloat) -> Path {
        let span = planform.wing.span
        var path = Path()
        path.move(to: wingPoint(side: side, s: span * 0.03, f: 0.12))
        path.addLine(to: wingPoint(side: side, s: span * 0.96, f: 0.12))
        path.move(to: wingPoint(side: side, s: 0, f: 0.74))
        path.addLine(to: wingPoint(side: side, s: span * 0.66, f: 0.74))
        path.move(to: wingPoint(side: side, s: span * 0.68, f: 0.76))
        path.addLine(to: wingPoint(side: side, s: span * 0.96, f: 0.76))
        // Flap track fairings: the short blades that stick out past the
        // trailing edge on every narrowbody.
        for fraction in [0.2, 0.42, 0.62] {
            let hinge = wingPoint(side: side, s: span * fraction, f: 0.74)
            let trail = wingPoint(side: side, s: span * fraction, f: 1)
            path.move(to: hinge)
            path.addLine(to: CGPoint(x: trail.x, y: trail.y + (trail.y - hinge.y) * 0.25))
        }
        return path
    }

    func nacelles(side: CGFloat) -> [Path] {
        planform.nacelles.map { nacelle in
            let s = max(0, nacelle.station - planform.fuselageWidth / 2)
            let wing = planform.wing
            let lead = wingRootLeadingY + CGFloat(wing.leadingEdgeOffset(at: s)) * yScale
            let inlet = lead + CGFloat(nacelle.chordFraction * wing.chord(at: s) + nacelle.offset) * yScale
            let width = CGFloat(nacelle.diameter) * xScale
            let rect = CGRect(x: midX + side * CGFloat(nacelle.station) * xScale - width / 2,
                              y: inlet, width: width,
                              height: CGFloat(nacelle.length) * yScale)
            return Path(roundedRect: rect, cornerSize: CGSize(width: width / 2, height: width * 0.7),
                        style: .continuous)
        }
    }

    // MARK: Tail

    func horizontalTail(side: CGFloat) -> Path? {
        guard let tail = planform.horizontalTail else { return nil }
        let rootLead = tailEndY - CGFloat(planform.horizontalTailFromEnd) * yScale
        func point(_ s: Double, _ f: Double) -> CGPoint {
            let aft = CGFloat(tail.leadingEdgeOffset(at: s) + f * tail.chord(at: s))
            let outboard: CGFloat = CGFloat(s) * xScale
            return CGPoint(x: midX + side * outboard, y: rootLead + aft * yScale)
        }
        var path = Path()
        path.move(to: point(0, 0))
        path.addLine(to: point(tail.span, 0))
        path.addLine(to: point(tail.span, 1))
        path.addLine(to: point(0, 1))
        path.closeSubpath()
        return path
    }

    /// The fin from above: a slim airfoil on the centreline, rounded at the
    /// leading edge and sharp at the trailing edge.
    var fin: Path {
        let lead: CGFloat = tailEndY - CGFloat(planform.finFromEnd) * yScale
        let chord: CGFloat = CGFloat(planform.finRootChord) * yScale
        let thickest: CGFloat = lead + chord * 0.3
        let half: CGFloat = max(1, CGFloat(planform.fuselageWidth) * 0.04 * xScale)
        var path = Path()
        path.move(to: CGPoint(x: midX, y: lead))
        path.addQuadCurve(to: CGPoint(x: midX + half, y: thickest),
                          control: CGPoint(x: midX + half, y: lead))
        path.addLine(to: CGPoint(x: midX, y: lead + chord))
        path.addLine(to: CGPoint(x: midX - half, y: thickest))
        path.addQuadCurve(to: CGPoint(x: midX, y: lead),
                          control: CGPoint(x: midX - half, y: lead))
        path.closeSubpath()
        return path
    }

    // MARK: Silhouette

    /// Every surface that makes up the solid silhouette, back to front.
    var silhouetteParts: [Path] {
        var parts: [Path] = []
        for side: CGFloat in [-1, 1] {
            parts.append(contentsOf: nacelles(side: side))
            parts.append(wing(side: side))
            if let tail = horizontalTail(side: side) { parts.append(tail) }
        }
        parts.append(fuselage)
        return parts
    }
}
