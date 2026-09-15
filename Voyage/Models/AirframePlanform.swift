import Foundation

/// A wing or tailplane panel seen from above, in metres.
///
/// Parameterised the way OpenVSP describes a wing section
/// (`src/geom_core/WingGeom.cpp`, `WingSect`): span, root chord, tip chord,
/// and a sweep angle measured at a chord fraction (`Sweep`, `Sweep_Location`).
/// Published aircraft data quotes sweep at the quarter chord, so that is the
/// usual location, and the leading-edge sweep the drawing needs is derived with
/// OpenVSP's own `CalcTanSweepAt`.
struct WingSection: Equatable {
    /// One side, measured outboard from the panel's root.
    let span: Double
    let rootChord: Double
    let tipChord: Double
    /// Degrees, at `sweepLocation` of the chord.
    let sweep: Double
    let sweepLocation: Double

    var taper: Double { tipChord / rootChord }
    /// OpenVSP's section aspect ratio: span over mean chord.
    var aspect: Double { span / ((rootChord + tipChord) / 2) }

    /// `tan` of the sweep along the line at chord fraction `location`.
    /// Ported from `CalcTanSweepAt` in OpenVSP's `WingGeom.cpp`.
    func tanSweep(at location: Double) -> Double {
        let tanSweep = tan(sweep * .pi / 180)
        return tanSweep - (2 / aspect) * (location - sweepLocation) * (1 - taper) / (1 + taper)
    }

    /// Chord at a distance `s` outboard of the root.
    func chord(at s: Double) -> Double {
        rootChord + (tipChord - rootChord) * min(max(s / span, 0), 1)
    }

    /// How far aft of the root leading edge the leading edge sits at `s`.
    func leadingEdgeOffset(at s: Double) -> Double {
        s * tanSweep(at: 0)
    }
}

/// An underwing engine nacelle, one per side.
struct Nacelle: Equatable {
    /// Distance from the aircraft centreline.
    let station: Double
    let length: Double
    let diameter: Double
    /// Where the inlet sits relative to the local wing leading edge: a chord
    /// fraction plus a fixed offset. Narrowbody fans hang ahead of the wing
    /// (negative offset); a supersonic delta buries them near the trailing edge.
    let chordFraction: Double
    let offset: Double
}

/// The whole aircraft seen from above, in metres.
///
/// Figures are rounded from each type's published dimensions (length,
/// fuselage width, span, quarter-chord sweep, tailplane span). Chords and
/// stations the manufacturers do not publish are estimated from general
/// arrangement drawings, so treat them as close, not certified.
///
/// Stations are measured from three anchors rather than one, because the seat
/// map's cabin is not laid out in metres (cabin headers and a shortened row
/// count): nose features from the nose tip, the wing from the over-wing exit,
/// and tail features back from the tail end. Each anchor lands where its rows
/// actually are, and each panel keeps its true size around it.
struct AirframePlanform: Equatable {
    let length: Double
    let fuselageWidth: Double
    /// 0 is a pointed nose, 1 a blunt dome.
    let noseFullness: Double
    /// Nose tip to where the fuselage reaches full width.
    let noseTaper: Double
    /// Nose tip to the first passenger row: the flight deck and forward galley.
    let noseToFirstRow: Double
    /// Last passenger row to the tail end: aft galley, then the tailcone.
    let aftOfLastRow: Double
    /// Tail end forward to where the tailcone begins to narrow.
    let tailTaper: Double

    /// Main wing, measured outboard from the fuselage side.
    let wing: WingSection
    /// Where the over-wing exit sits along the wing root, as a chord fraction.
    /// Exits are cut above the forward wing box, which is why this is small.
    let exitChordFraction: Double
    let nacelles: [Nacelle]

    /// Horizontal stabiliser, measured outboard from the centreline. `nil`
    /// for a tailless delta.
    let horizontalTail: WingSection?
    /// Tail end forward to the stabiliser root leading edge.
    let horizontalTailFromEnd: Double

    /// Vertical fin, which from above is a thin blade on the centreline.
    let finRootChord: Double
    let finFromEnd: Double

    /// Nose tip to the over-wing exit. Only used where the airframe is drawn
    /// whole at one scale (the launch flyover); the seat map measures it.
    let exitStation: Double

    /// A real seat pitch, used to turn the seat map's row pitch into a scale.
    static let seatPitch = 0.787 // 31 in

    /// Full span, tip to tip.
    var totalSpan: Double { fuselageWidth + wing.span * 2 }
}

extension AircraftProfile {
    var planform: AirframePlanform {
        switch self {
        case .boeing737800:
            // 39.5 m long, 3.76 m wide, 34.3 m span, 25° quarter-chord sweep,
            // 14.4 m tailplane.
            return AirframePlanform(
                length: 39.5, fuselageWidth: 3.76, noseFullness: 0.34,
                noseTaper: 4.6, noseToFirstRow: 5.4, aftOfLastRow: 8.4, tailTaper: 7.2,
                wing: WingSection(span: 15.3, rootChord: 6.4, tipChord: 1.25,
                                  sweep: 25, sweepLocation: 0.25),
                exitChordFraction: 0.3,
                nacelles: [Nacelle(station: 4.9, length: 4.0, diameter: 2.0,
                                   chordFraction: 0, offset: -2.7)],
                horizontalTail: WingSection(span: 7.2, rootChord: 3.9, tipChord: 1.1,
                                            sweep: 30, sweepLocation: 0.25),
                horizontalTailFromEnd: 6.2,
                finRootChord: 5.6, finFromEnd: 7.4,
                exitStation: 16.2
            )
        case .airbusA320neo:
            // 37.6 m long, 3.95 m wide, 35.8 m span with sharklets, 25°
            // sweep, 12.5 m tailplane, and the LEAP-1A's oversized nacelles.
            return AirframePlanform(
                length: 37.6, fuselageWidth: 3.95, noseFullness: 0.62,
                noseTaper: 4.2, noseToFirstRow: 5.0, aftOfLastRow: 8.0, tailTaper: 6.8,
                wing: WingSection(span: 15.9, rootChord: 6.1, tipChord: 1.5,
                                  sweep: 25, sweepLocation: 0.25),
                exitChordFraction: 0.3,
                nacelles: [Nacelle(station: 5.75, length: 4.4, diameter: 2.5,
                                   chordFraction: 0, offset: -3.0)],
                horizontalTail: WingSection(span: 6.25, rootChord: 3.6, tipChord: 1.2,
                                            sweep: 29, sweepLocation: 0.25),
                horizontalTailFromEnd: 5.8,
                finRootChord: 5.4, finFromEnd: 7.0,
                exitStation: 15.4
            )
        case .voyageClassic:
            // Fictional, sized like a modern single-aisle: between the two
            // real narrowbodies, with a slightly longer, cleaner wing.
            return AirframePlanform(
                length: 38.4, fuselageWidth: 3.9, noseFullness: 0.5,
                noseTaper: 4.4, noseToFirstRow: 5.2, aftOfLastRow: 8.2, tailTaper: 7.0,
                wing: WingSection(span: 16.2, rootChord: 6.3, tipChord: 1.35,
                                  sweep: 26, sweepLocation: 0.25),
                exitChordFraction: 0.3,
                nacelles: [Nacelle(station: 5.4, length: 4.2, diameter: 2.2,
                                   chordFraction: 0, offset: -2.8)],
                horizontalTail: WingSection(span: 6.7, rootChord: 3.8, tipChord: 1.15,
                                            sweep: 30, sweepLocation: 0.25),
                horizontalTailFromEnd: 6.0,
                finRootChord: 5.5, finFromEnd: 7.2,
                exitStation: 15.8
            )
        case .boomOverture:
            // 61 m long, 32 m span. A slender delta that carries its chord
            // down most of the fuselage, four engines buried at the trailing
            // edge, and no horizontal tail at all.
            return AirframePlanform(
                length: 61, fuselageWidth: 2.9, noseFullness: 0.05,
                noseTaper: 11, noseToFirstRow: 11.5, aftOfLastRow: 12, tailTaper: 9,
                wing: WingSection(span: 14.6, rootChord: 27, tipChord: 2.2,
                                  sweep: 52, sweepLocation: 0.25),
                exitChordFraction: 0.42,
                nacelles: [
                    // Inlets under the wing, nozzles just past the trailing
                    // edge, which is all of them that shows from above.
                    Nacelle(station: 3.6, length: 7.5, diameter: 1.7,
                            chordFraction: 0.74, offset: 0),
                    Nacelle(station: 6.4, length: 7.0, diameter: 1.6,
                            chordFraction: 0.70, offset: 0)
                ],
                horizontalTail: nil,
                horizontalTailFromEnd: 0,
                finRootChord: 9, finFromEnd: 10,
                exitStation: 33
            )
        }
    }
}
