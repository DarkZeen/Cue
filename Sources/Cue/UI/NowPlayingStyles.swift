import SwiftUI

// MARK: - Motion

/// The dynamics every style borrows when nothing is listening.
///
/// A visualiser with a constant amplitude is the giveaway. Real music arrives in
/// swells — a chorus lifts, a verse settles — and a meter that holds one height
/// reads as a mechanism within about ten seconds, however well its individual
/// wiggle is tuned.
///
/// So the amplitude itself moves, slowly, on rates chosen to share no common
/// factor. The eye is very good at finding a period; the defence is not to have
/// one it can find inside the time anybody looks.
enum ProceduralMotion {
    /// **Audio may set a position. It may never set a rate.**
    ///
    /// Every one of these marks is stateless: it is redrawn each frame from
    /// `elapsed`, and `elapsed` is seconds since 2001 — about 8×10⁸ of them. So
    /// a phase written as `elapsed * rate` moves by *hundreds of millions of
    /// radians* the moment `rate` changes by a fraction. The first version of
    /// this did exactly that, in two places, and the results were a wave that
    /// tore itself apart and a ring that span at random.
    ///
    /// A rate can only be varied by something that integrates it, and nothing
    /// here has anywhere to keep the integral. So rates are constants, and the
    /// music drives what can be set outright and continuously: amplitude, size,
    /// separation, and bounded *offsets* added to a phase that is still
    /// advancing at its own steady speed.

    /// A travelling phase: a steady rate, plus a bounded offset the music may
    /// move.
    ///
    /// Written once, in one place, so the rule above has somewhere to live and
    /// something to test. `surge` is added to the finished phase rather than
    /// folded into the rate, and it is clamped — a mark that leans on the beat
    /// is the intent; a mark that can be thrown anywhere is the bug.
    static func travel(_ elapsed: TimeInterval, rate: Double, surge: Double) -> Double {
        elapsed * rate + min(max(surge, -1.2), 1.2)
    }

    /// How many readings a mark is drawn from.
    ///
    /// Must equal `SpectrumAnalyser.bandCount`, and is stated separately
    /// because the drawing cannot depend on the audio code — the mark has to
    /// build and be previewable with no Core Audio in the picture at all. A
    /// test holds the two together.
    static let bandCount = 9

    /// What drives a style: the real level when there is one, invention when
    /// there is not.
    ///
    /// One path rather than two. The tap is off by default and can be refused,
    /// so every style has to look right without it — and a style written
    /// against real audio with a fallback bolted on afterwards is a style whose
    /// fallback nobody ever looks at.
    static func energy(_ level: Double, at elapsed: TimeInterval) -> Double {
        level > 0.001 ? min(level, 1) : swell(at: elapsed)
    }

    /// The beat, 0 to 1: the low end, which is where a kick lives.
    ///
    /// Separate from `energy` because the two want different things. The level
    /// is an average and moves like one — it says how loud the passage is. This
    /// is the bottom two bands only, which spike on a hit and fall between
    /// them, and that spike is the whole thing the eye reads as rhythm.
    ///
    /// Without a tap it is a sharpened pulse at a plausible tempo. Cubed, so it
    /// reads as a hit rather than as a swell.
    static func beat(_ bands: [Double], at elapsed: TimeInterval) -> Double {
        guard bands.count >= 2 else {
            return pow((sin(elapsed * 1.7 * .pi) + 1) / 2, 3)
        }
        return min((bands[0] * 0.65 + bands[1] * 0.35) * 1.35, 1)
    }

    /// A slow swell, 0 to 1, that never sits still and never repeats visibly.
    static func swell(at elapsed: TimeInterval) -> Double {
        let slow = sin(elapsed / 7.3 * 2 * .pi)
        let slower = sin(elapsed / 11.9 * 2 * .pi + 1.1)
        return (slow * 0.5 + slower * 0.5 + 1) / 2
    }
}

// MARK: - Wave

/// Cue's own mark, each shape stretched about the centre line.
///
/// The artwork's shapes rather than an approximation, so this and the app icon
/// are recognisably one family. Two rules give it its character:
///
/// * The phase travels **outward from the middle**, because this mark is
///   symmetric and movement that runs left to right fights that symmetry.
/// * The outer shapes move furthest. A wave whose middle moves most looks like
///   it is inflating; one whose edges move most looks like sound arriving.
struct WaveIndicator: View {
    let elapsed: TimeInterval
    var level: Double = 0
    var bands: [Double] = []
    let isAnimating: Bool

    /// Small, and then smaller. The mark is a status light beside a search
    /// field, not a centrepiece; at this size the nine shapes read as one
    /// object that moves rather than nine that wobble, and the breath
    /// underneath them has room to show without the mark crowding the field.
    ///
    /// A parameter rather than a constant only so the shelf's now-playing
    /// wing can draw it a little smaller still; 14 is the mark's own size and
    /// what every other caller gets.
    var height: CGFloat = 14

    /// White, because the logo is white on black and stays that way
    /// (`CuePalette`). The one caller that passes anything else is the
    /// shelf's now-playing wing, which takes its colour from the cover — a
    /// deliberate exception confined to that wing.
    var tint: Color = .white

    /// How far the motion is allowed to travel, as a share of its designed
    /// reach. 1 is the mark as designed. Less keeps it inside a small housing
    /// — the shapes and the breath scale outward from rest by this much, and
    /// nothing else about the motion changes.
    var excursion: Double = 1

    /// Party mode's second colour. Set, each shape is mixed between this and
    /// `tint` by how long it is on screen at that moment — the long shapes
    /// take `tint`, the short ones this — so the colours move with the music.
    var shortTint: Color? = nil

    /// What the shapes answer to. `frequencies` is the mark as it always was.
    var reaction: MarkReaction = .frequencies
    /// The kick envelope, from a `BeatFollower`, for `.beat`.
    var kick: Double = 0

    private var count: Int { CueWavePath.shapes.count }

    /// Each shape's height as a share of the mark's, from the artwork.
    private static let shapeHeights: [CGFloat] = (0..<CueWavePath.shapes.count).map { index in
        CueWavePath.path(forShape: index, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            .boundingRect.height
    }

    private func colour(_ index: Int) -> Color {
        guard let shortTint else { return tint }
        let length = Self.shapeHeights[index] * displacement(index)
        return shortTint.mix(with: tint, by: MarkColouring.share(forLength: length))
    }

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                CueWaveShape(index: index)
                    .fill(colour(index))
                    .scaleEffect(y: displacement(index), anchor: .center)
            }
        }
        .frame(width: height * CueWavePath.aspect, height: height)
        // The whole mark breathes underneath the individual shapes.
        //
        // Two motions at different rates, which is what stops it reading as a
        // mechanism: the shapes flicker with the music while the object itself
        // swells slowly. One rate alone looks like a loop however well tuned,
        // because the eye finds the period.
        .scaleEffect(pulse)
    }

    /// A breath, a swell, and a kick — three rates, deliberately.
    ///
    /// The breath keeps the mark alive when the music is quiet. The swell
    /// follows the passage. The beat is the one that arrives suddenly, and it
    /// is the only one anybody consciously notices; the other two are what stop
    /// it looking like a light being switched.
    private var pulse: CGFloat {
        guard isAnimating else { return 1 }

        // A sine rather than a repeating ease: a breath has no beginning and no
        // end, and any keyframed loop shows its seam eventually.
        let breath = sin(elapsed / 2.6 * 2 * .pi)
        let swell = ProceduralMotion.energy(level, at: elapsed)
        let kick = ProceduralMotion.beat(bands, at: elapsed)

        switch reaction {
        case .frequencies:
            // Each term scaled on its own rather than summed first, so the
            // default excursion of 1 is bit-for-bit the mark as it always was.
            return 1
                + CGFloat(breath * 0.04 * excursion)
                + CGFloat(swell * 0.06 * excursion)
                + CGFloat(kick * 0.13 * excursion)
        case .beat:
            // The whole mark punches on the kick and breathes in between.
            return 1
                + CGFloat(breath * 0.02 * excursion)
                + CGFloat(self.kick * 0.2 * excursion)
        case .smooth:
            return 1
                + CGFloat(breath * 0.04 * excursion)
                + CGFloat(swell * 0.07 * excursion)
        }
    }

    private func displacement(_ index: Int) -> CGFloat {
        guard isAnimating else { return 1 }

        let middle = Double(count - 1) / 2
        let distance = abs(Double(index) - middle) / max(middle, 1)

        let reach = 0.28 + 0.72 * distance

        // The phase is left completely alone. Nothing the music does touches
        // it — not the rate, and not an offset either.
        //
        // The beat is built to spike, so *any* term added to a travelling
        // phase moves the shapes several times their usual step in a single
        // frame, and a wave that jumps forward on every hit is exactly what
        // reads as jagged. Worse, the second sine below multiplies the phase by
        // 1.63, so it would receive an offset 1.63 times the size and the two
        // would pull apart on every beat — which is what "not cohesive" looks
        // like from the outside.
        let phase = ProceduralMotion.travel(elapsed, rate: 3.6, surge: 0)
            - distance * 1.5

        // Two sines rather than one, at an irrational-ish ratio, so the loop
        // never lands on an obvious repeat.
        let wave = (sin(phase) + sin(phase * 1.63 + 0.7)) / 2

        // The beat is spent here instead, and on the pulse: both are set
        // outright each frame, both move every shape by the same proportion,
        // and neither can break the phase relationship that makes nine shapes
        // look like one object. Enough travel to be read from the corner of an
        // eye — the earlier values were tuned looking straight at it, which is
        // the one way this is never actually seen.
        let amplitude: Double
        switch reaction {
        case .frequencies:
            amplitude = 0.20
                + 0.34 * ProceduralMotion.energy(level, at: elapsed)
                + 0.18 * ProceduralMotion.beat(bands, at: elapsed) * distance
        case .beat:
            // Small between kicks, so the kick is what is seen.
            amplitude = 0.08 + 0.62 * kick * (0.45 + 0.55 * distance)
        case .smooth:
            amplitude = 0.14 + 0.3 * ProceduralMotion.energy(level, at: elapsed)
        }

        // Never collapses to nothing: a shape that reaches zero height leaves a
        // gap in the mark and reads as a rendering fault rather than as quiet.
        // The floor holds whatever the excursion, which only scales the
        // stretch away from rest.
        return max(1 + CGFloat(wave * amplitude * excursion) * reach, 0.22)
    }
}

struct CueWaveShape: Shape {
    let index: Int

    nonisolated func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / CueWavePath.aspect, rect.height)
        let size = CGSize(width: scale * CueWavePath.aspect, height: scale)
        let box = CGRect(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        return CueWavePath.path(forShape: index, in: box)
    }
}

// MARK: - Record

/// A record turning under its arm, seen from above.
///
/// The notes are back, and they earn their place now that they are not the only
/// thing saying "music": the vinyl says it, and the notes say *how much*. They
/// leave on the beat, and a quiet passage produces almost none.
///
/// The difficulty of a record at this size is that a disc is rotationally
/// symmetric, so it looks identical however fast it turns. Real vinyl solves
/// this itself: the sheen sweeps across the grooves as the record moves, and
/// that sweep is the only part of this drawing that has to rotate for the whole
/// thing to read as spinning.
struct DiscIndicator: View {
    let elapsed: TimeInterval
    var level: Double = 0
    var bands: [Double] = []
    let isAnimating: Bool

    /// One turn every three and a half seconds. A record at 33⅓ rpm is 1.8
    /// seconds a turn, which at this size reads as a wobble rather than a
    /// rotation — the honest speed is the one that looks wrong.
    private static let secondsPerTurn = 3.4

    private static let diameter: CGFloat = 21

    var body: some View {
        ZStack(alignment: .center) {
            notes
            record
            Tonearm(isDown: isAnimating, sway: sway)
        }
        .frame(width: 30, height: 26)
    }

    /// The arm is never quite still. A tonearm on a record that is turning has
    /// a tiny amount of movement in it, and without that this half of the mark
    /// is a decal sitting on top of the moving half.
    private var sway: Double {
        guard isAnimating else { return 0 }
        return sin(elapsed / 3.1 * 2 * .pi) * 0.5 + ProceduralMotion.energy(level, at: elapsed) * 0.6
    }

    /// Notes drifting off the record, up and to the left.
    ///
    /// Three of them on their own cycles. What makes them read as *music*
    /// rather than as decoration is that they are not evenly spaced in time:
    /// each has its own period, and each is only as visible as the music is
    /// loud — so a quiet passage produces almost nothing and a chorus produces
    /// a stream.
    private var notes: some View {
        let energy = ProceduralMotion.energy(level, at: elapsed)

        return ForEach(0..<3, id: \.self) { index in
            // Periods that share no common factor, so the three never fall
            // into step and start reading as one repeating animation.
            let period = [2.4, 3.1, 2.75][index]
            let cycle = ((elapsed / period) + Double(index) * 0.37)
                .truncatingRemainder(dividingBy: 1)

            // Further out when the music is loud. A note that always travels
            // the same distance is a note on a rail.
            let reach = 5.0 + 7.0 * energy

            Image(systemName: ["music.note", "music.quarternote.3", "music.note"][index])
                .font(.system(size: index == 1 ? 7.5 : 6.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .offset(
                    x: -8 - cycle * reach + sin(cycle * .pi * 2 + Double(index)) * 2.2,
                    y: 2 - cycle * (11 + 6 * energy)
                )
                .rotationEffect(.degrees(sin(cycle * .pi * 2) * 14))
                // In quickly, out slowly: a note that fades in over the same
                // duration it fades out spends most of its life at half
                // opacity, which reads as blur rather than as motion.
                .opacity(isAnimating ? min(cycle * 5, 1) * (1 - cycle) * (0.25 + 0.75 * energy) : 0)
        }
    }

    private var record: some View {
        let turns = isAnimating ? elapsed / Self.secondsPerTurn : 0
        let angle = Angle.degrees(turns.truncatingRemainder(dividingBy: 1) * 360)

        return ZStack {
            // Vinyl is not black. It is very dark and slightly lit from
            // somewhere, and a flat black circle at this size disappears into
            // whatever the plaque is sitting on.
            Circle().fill(
                RadialGradient(
                    colors: [Color(white: 0.20), Color(white: 0.045)],
                    center: UnitPoint(x: 0.36, y: 0.30),
                    startRadius: 0.5,
                    endRadius: Self.diameter * 0.72
                )
            )

            // Grooves. Fine and many, rather than three heavy rings: the
            // texture is what says vinyl, and a groove you can count is a
            // drawing of a groove.
            ForEach(0..<8, id: \.self) { ring in
                Circle()
                    .strokeBorder(.white.opacity(0.07), lineWidth: 0.35)
                    .padding(1.0 + Double(ring) * 0.95)
            }

            // The sheen, and the only thing here that turns. Two soft lobes
            // opposite each other, which is how light actually falls across a
            // record — one bright arc, one weaker one behind it.
            Circle()
                .fill(
                    AngularGradient(
                        stops: [
                            .init(color: .white.opacity(0.00), location: 0.00),
                            .init(color: .white.opacity(0.26), location: 0.10),
                            .init(color: .white.opacity(0.00), location: 0.30),
                            .init(color: .white.opacity(0.00), location: 0.55),
                            .init(color: .white.opacity(0.13), location: 0.63),
                            .init(color: .white.opacity(0.00), location: 0.82),
                            .init(color: .white.opacity(0.00), location: 1.00)
                        ],
                        center: .center
                    )
                )
                .rotationEffect(angle)
                .blendMode(.screen)

            // The label. Cue's red, which the reference happened to be already.
            Circle()
                .fill(CuePalette.accent)
                .frame(width: 8.2, height: 8.2)
                .overlay(Circle().strokeBorder(.black.opacity(0.25), lineWidth: 0.4))

            // The spindle hole. One pixel of true black, and the difference
            // between a red dot and a record.
            Circle().fill(.black.opacity(0.85)).frame(width: 1.5, height: 1.5)
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .offset(x: -3)
    }
}

/// The arm: pivot at the top right, dogleg, stylus down on the outer grooves.
///
/// Lifted when nothing is playing. A stopped record with the arm still down is
/// a record that has run out, and this one has not — it is waiting.
struct Tonearm: View {
    let isDown: Bool
    let sway: Double

    var body: some View {
        ZStack(alignment: .topLeading) {
            ArmShape()
                .stroke(.white.opacity(0.92), style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))

            // The bearing housing, which on a real deck is the heaviest thing
            // on the arm and the reason the silhouette reads right way up.
            //
            // Grey, not black. The reference is black on paper; this sits on a
            // near-black plaque, where the same shape is a hole rather than a
            // part — and the arm then appears to start in mid-air.
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(white: 0.62))
                .frame(width: 3.6, height: 5.8)
                .rotationEffect(.degrees(30))
                .offset(x: 22.6, y: 0.8)
        }
        .frame(width: 30, height: 26, alignment: .topLeading)
        // About the pivot, not the centre: an arm that rotates about the middle
        // of the frame swings its own bearing around, which nothing does.
        .rotationEffect(.degrees(isDown ? sway : -9), anchor: UnitPoint(x: 24.5 / 30, y: 3.5 / 26))
        .animation(.easeOut(duration: 0.45), value: isDown)
    }
}

struct ArmShape: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 24.2, y: rect.minY + 4.0))
        path.addLine(to: CGPoint(x: rect.minX + 18.2, y: rect.minY + 13.6))
        // The dogleg. Every arm of this shape has one, and it is the detail
        // that separates a tonearm from a line drawn across a circle. Shallow,
        // though: at this size the first version bent far enough to read as a
        // tick mark laid over the record.
        path.addLine(to: CGPoint(x: rect.minX + 16.9, y: rect.minY + 14.4))
        path.addLine(to: CGPoint(x: rect.minX + 15.2, y: rect.minY + 19.6))
        return path
    }
}

// MARK: - Bars

/// A mirrored spectrum: bass in the middle, treble at the edges, every bar
/// growing from a centre line in both directions.
///
/// The shape comes from the mirroring. A meter that stands on a floor reads as
/// a chart; one that grows symmetrically about a line reads as a *waveform*,
/// which is the thing being looked at. Bass in the centre is what gives it the
/// tall middle and the tapering dashes at either end — and it means the beat,
/// which lives in the low end, moves the part of the mark the eye is already on.
struct BarsIndicator: View {
    let elapsed: TimeInterval
    var level: Double = 0
    /// The spectrum, low to high. Empty when nothing is listening, in which
    /// case the bars move to a rhythm of their own.
    var bands: [Double] = []
    let isAnimating: Bool
    /// White everywhere but the notch, where the mark takes the cover's colour.
    var tint: Color = .white
    /// Party mode's second colour: the short bars take it, the tall ones
    /// `tint`, mixed by height.
    var shortTint: Color? = nil

    /// Bands either side of the centre. Nine gives seventeen bars, which is
    /// enough to read as a spectrum and few enough that each stays visible at
    /// this size.
    private static let bandCount = ProceduralMotion.bandCount
    // Smaller than it was, and shorter by more than it is narrower — a meter
    // whose bars are as tall as the search field's text competes with the
    // field. Previously 1.6 / 1.1 / 26, kept here because the difference is
    // taste rather than correctness and taste is worth being able to undo.
    private static let barWidth: CGFloat = 1.3
    private static let spacing: CGFloat = 0.95
    private static let height: CGFloat = 16

    private var barCount: Int { Self.bandCount * 2 - 1 }

    var body: some View {
        HStack(alignment: .center, spacing: Self.spacing) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(barColour(index).opacity(opacity(index)))
                    .frame(width: Self.barWidth, height: barHeight(index))
            }
        }
        .frame(height: Self.height)
    }

    /// Which band a bar shows: 0 at the centre, rising outward on both sides.
    private func barColour(_ index: Int) -> Color {
        guard let shortTint else { return tint }
        return shortTint.mix(with: tint, by: MarkColouring.share(forLength: barHeight(index) / Self.height))
    }

    private func band(_ index: Int) -> Int {
        abs(index - (Self.bandCount - 1))
    }

    private func barHeight(_ index: Int) -> CGFloat {
        // A dot rather than nothing at rest, so the mark keeps its full width
        // in silence instead of shrinking to a stub.
        let resting: CGFloat = Self.barWidth
        guard isAnimating else { return resting }

        let band = band(index)
        let value = reading(band)

        // The outer bands are quieter in almost all music, so without this the
        // mark is a hump in the middle and two flat wings. Lifting the highs
        // trades accuracy for a shape worth looking at, which is the right
        // trade for something a centimetre wide.
        let lift = 1 + 1.5 * (Double(band) / Double(Self.bandCount - 1))

        let reach = Self.height - resting
        return resting + CGFloat(min(value * lift, 1)) * reach
    }

    /// How high a band stands. Invention — but invention shaped like music
    /// rather than a sine wave wearing a costume.
    ///
    /// Three things separate the two. A pulse at a plausible tempo, so the
    /// whole meter lifts together the way it does on a beat. Bands that decay
    /// at different speeds, because bass rings on and hi-hats do not. And rates
    /// that share no common factor, so the pattern never visibly repeats — the
    /// eye finds a period in seconds otherwise, which is what makes a fake
    /// meter look fake.
    private func reading(_ band: Int) -> Double {
        if bands.indices.contains(band) { return bands[band] }

        let position = Double(band) / Double(Self.bandCount - 1)

        // Roughly 100bpm. Sharpened so it reads as a hit rather than a swell.
        let beat = pow((sin(elapsed * 1.7 * .pi) + 1) / 2, 3)

        let rate = 2.3 + Double(band) * 0.61 + position * 1.4
        let wobble = (sin(elapsed * rate + Double(band) * 1.7)
            + sin(elapsed * rate * 0.41 + Double(band) * 3.1)) / 4 + 0.5

        // The low bands follow the beat; the high ones chatter over it.
        let follow = 1 - position
        let shape = wobble * (0.45 + 0.55 * position) + beat * follow * 0.8

        // The whole meter rises and falls underneath the individual bars, which
        // is what a chorus does and what a loop cannot fake.
        return (0.24 + 0.4 * ProceduralMotion.energy(level, at: elapsed)) * min(shape, 1)
    }

    /// The tall middle is the brightest, the tips fade out. It is the depth
    /// cue the reference has, and it stops seventeen identical strokes reading
    /// as a comb.
    private func opacity(_ index: Int) -> Double {
        let distance = Double(abs(index - (Self.bandCount - 1))) / Double(Self.bandCount - 1)
        return 1 - 0.45 * distance
    }
}

// MARK: - Orbit

/// Blobs going round a ring, running together when they pass.
///
/// The merging is the whole idea, and it is not drawn — it falls out of two
/// filters. Blur everything, then throw away every pixel below a threshold: two
/// circles far apart stay two circles, and two circles close enough for their
/// blurs to overlap cross the threshold in the gap between them and become one
/// shape with a waist. Nothing computes the join; it is just what a blurred
/// alpha channel does.
///
/// Which means the motion has to earn it. Blobs at one speed never meet, so
/// each runs at its own — they lap each other, pair up, stretch apart, and the
/// ring is never twice in the same arrangement.
///
/// With a tap running, three separate things answer the music, and they were
/// chosen because they change *the merging* rather than merely the picture:
///
/// * **Separation.** Loud pushes the ring outward and quiet lets it collapse
///   inward. Close together, the blobs merge constantly and the mark is nearly
///   one shape; spread apart, they come apart into six. That range is the whole
///   character of the thing, and the music now drives it end to end.
/// * **A lean.** The ring runs slightly ahead through a loud passage and drops
///   back through a quiet one. An offset, never a rate — see
///   `ProceduralMotion`, which is where the reasoning for that lives.
/// * **Size, per band.** Each blob reads one slice of the spectrum, low at the
///   top and rising round the ring — so the ring is a spectrum bent into a
///   circle, and a bass hit swells one part of it rather than all of it.
struct OrbitIndicator: View {
    let elapsed: TimeInterval
    var level: Double = 0
    var bands: [Double] = []
    let isAnimating: Bool
    /// White everywhere but the notch, where the mark takes the cover's colour.
    var tint: Color = .white

    /// Radius from centre, size, angular speed, where it starts.
    ///
    /// Deliberately uneven. Six identical blobs at six even speeds is a
    /// mechanism; these differ in every value they have, which is why the
    /// pairings look like something happening rather than something scheduled.
    private static let blobs: [(orbit: Double, size: Double, speed: Double, phase: Double)] = [
        (6.7, 6.7, 0.64, 0.00),
        (7.1, 5.6, 0.73, 1.10),
        (6.4, 5.0, 0.61, 2.15),
        (7.2, 6.1, 0.70, 3.25),
        (6.5, 4.7, 0.77, 4.25),
        (6.9, 5.4, 0.66, 5.35)
    ]

    var body: some View {
        Canvas { context, size in
            // The threshold has to sit where a lone blob still clears it after
            // the blur has spread it out. Too high and the small blobs vanish;
            // too low and everything is one puddle.
            context.addFilter(.alphaThreshold(min: 0.42, color: tint))

            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 2.4))

                let centre = CGPoint(x: size.width / 2, y: size.height / 2)

                let energy = ProceduralMotion.energy(level, at: elapsed)

                // How far apart they sit. The number that matters most: at the
                // bottom of this range the blobs overlap almost continuously
                // and the mark is one moving shape, at the top they separate
                // into six. Everything else is detail next to it.
                // The floor matters as much as the ceiling. At 0.62 the blobs
                // ran together into a single puddle with a hole in it during
                // every quiet passage — which is not "merged", it is "one
                // shape", and the mark stopped being a ring at all.
                let separation = 0.84 + 0.38 * energy

                // A steady rate with a surge added, never a rate the music
                // sets. This is where the runaway was: `elapsed * (a + b·kick)`
                // moved every blob by an eighth of a billion radians whenever
                // the kick moved, which is why the ring appeared to spin at
                // random. The surge is bounded, so the ring leans into a beat
                // and settles, and the underlying travel never stops being
                // steady.
                // The lean follows the level rather than the beat, and that is
                // the difference between leaning and lurching. The beat has a
                // fast attack — it is built to spike — so hanging a position on
                // it moves the blobs several frames' worth in one frame. The
                // beat is spent on size instead, where a sudden change is a
                // blob swelling rather than a blob teleporting.
                let surge = energy * 0.3

                for (index, blob) in Self.blobs.enumerated() {
                    let angle = blob.phase
                        + ProceduralMotion.travel(elapsed, rate: blob.speed, surge: surge)
                    // The orbit breathes a little, so the ring is not a wire
                    // the blobs are threaded on.
                    let radius = (blob.orbit + sin(elapsed * 0.9 + blob.phase) * 0.7) * separation
                    let point = CGPoint(
                        x: centre.x + cos(angle) * radius,
                        y: centre.y + sin(angle) * radius
                    )
                    // One band each, low at the start and rising round the
                    // ring. Without a tap they all read the same swell, which
                    // is what the fallback has always done.
                    let band = index * (ProceduralMotion.bandCount - 1) / max(Self.blobs.count - 1, 1)
                    let reading = bands.indices.contains(band) ? bands[band] : energy
                    // Floored for the same reason: a band at rest should give
                    // a smaller blob, not a speck.
                    let size = blob.size * (0.88 + 0.44 * reading)
                    let rect = CGRect(
                        x: point.x - size / 2,
                        y: point.y - size / 2,
                        width: size,
                        height: size
                    )
                    layer.fill(Path(ellipseIn: rect), with: .color(.white))
                }
            }
        }
        .frame(width: 26, height: 26)
    }
}

// MARK: - Party colouring

/// How a mark's lines take two colours in party mode: by length.
enum MarkColouring {
    /// 0 for the shortest lines, 1 for the longest, for a line `length` long
    /// as a share of the mark's height. Eased, so most lines read as clearly
    /// one colour or the other rather than as a muddy middle.
    static func share(forLength length: CGFloat) -> Double {
        let raw = min(max((Double(length) - 0.25) / 0.65, 0), 1)
        return raw * raw * (3 - 2 * raw)
    }
}

// MARK: - Island

/// A few thick rounded bars, the way the iPhone's Dynamic Island shows music.
///
/// Five capsules standing on a common centre line, each rising and falling on
/// its own sine. Fewer and fatter than `BarsIndicator`'s meter, so it reads
/// at a glance in the notch: the iPhone's answer to "is something playing",
/// not a spectrum. The same rule as the other marks holds — the music sets how
/// far a bar reaches, never how fast it moves — so the bars stay one object
/// however hard the beat hits.
struct IslandIndicator: View {
    let elapsed: TimeInterval
    var level: Double = 0
    /// The spectrum, low to high. Empty when nothing is listening, in which
    /// case the bars move to a rhythm of their own.
    var bands: [Double] = []
    let isAnimating: Bool
    var height: CGFloat = 14
    var tint: Color = .white
    /// Party mode's second colour: the short bars take it, the tall ones
    /// `tint`, mixed by height.
    var shortTint: Color? = nil
    /// What the bars answer to.
    var reaction: MarkReaction = .frequencies
    /// The kick envelope, from a `BeatFollower`, for `.beat`.
    var kick: Double = 0

    static let barCount = 5

    /// Thick for a meter, but not stubby: a seventh of the height, with gaps
    /// a little wider than a bar so the five read as five.
    private var barWidth: CGFloat { (height * 0.145).rounded(toPlaces: 1) }
    private var spacing: CGFloat { barWidth * 1.15 }

    /// Each bar's own pace, uneven so the row never lines up into a loop.
    private static let rates: [Double] = [5.1, 6.7, 4.3, 7.4, 5.8]
    private static let offsets: [Double] = [0.0, 1.9, 3.7, 0.8, 2.6]
    /// Which band each bar listens to: low in the middle, rising outward,
    /// so a kick lifts the centre and the hats the edges.
    private static let bandFor: [Int] = [5, 2, 0, 1, 4]

    var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                Capsule()
                    .fill(colour(index))
                    .frame(width: barWidth, height: max(barWidth, height * share(index)))
            }
        }
        .frame(height: height)
    }

    /// How much of the height a bar stands, a third to all of it.
    private func share(_ index: Int) -> CGFloat {
        guard isAnimating else { return Self.resting[index] }

        let phase = ProceduralMotion.travel(elapsed, rate: Self.rates[index], surge: 0)
            + Self.offsets[index]
        let own = (sin(phase) + 1) / 2

        let energy = ProceduralMotion.energy(level, at: elapsed)
        let reach: Double
        if reaction == .beat {
            // All five on the kick, the middle highest — the shape of a hit —
            // with a little of each bar's own motion so they are not a block.
            reach = kick * Self.hitShape[index] * 0.92 + own * 0.12
        } else if reaction == .smooth {
            let slow = (sin(ProceduralMotion.travel(elapsed, rate: Self.rates[index] * 0.35, surge: 0)
                + Self.offsets[index]) + 1) / 2
            reach = energy * Self.hitShape[index] * 0.7 + slow * 0.25
        } else if let heard = heard(index) {
            // Listening: the music drives the bars, and their own motion is
            // only a flicker underneath, so nothing reads as a loop.
            reach = heard + own * 0.08
        } else {
            let kick = ProceduralMotion.beat(bands, at: elapsed)
            let centre = 1 - abs(Double(index) - 2) / 2
            reach = own * (0.5 + 0.4 * energy) + kick * 0.3 * centre
        }
        // A floor of a third, not a dot: the iPhone's bars dip, they never
        // vanish into the row.
        return CGFloat(min(max(0.33 + reach * 0.67, 0.33), 1))
    }

    /// What the music says about one bar, or `nil` when nothing is listening.
    ///
    /// Two readings mixed. The band itself, so a loud passage stands every
    /// bar up; and the band against the other four this frame, so the bars
    /// move *apart* — the spectrum's bands rise and fall together much of the
    /// time, and on their raw values alone five bars move as one block, which
    /// is what looked scripted. The beat lifts the middle on top.
    private func heard(_ index: Int) -> Double? {
        guard bands.count > Self.bandFor.max() ?? 0 else { return nil }
        let picked = Self.bandFor.map { bands[$0] }
        let own = picked[index]
        let low = picked.min() ?? 0
        let high = picked.max() ?? 1
        let relative = (own - low) / max(high - low, 0.12)
        let kick = ProceduralMotion.beat(bands, at: elapsed)
        let centre = 1 - abs(Double(index) - 2) / 2
        return pow(own, 1.4) * 0.45 + relative * 0.45 * (0.4 + 0.6 * level) + kick * 0.25 * centre
    }

    /// How a kick stands the bars up: the middle highest.
    private static let hitShape: [Double] = [0.6, 0.85, 1, 0.85, 0.6]

    /// Still, the bars sit as the iPhone draws them paused: a low, even
    /// skyline with the middle a little taller.
    private static let resting: [CGFloat] = [0.35, 0.55, 0.75, 0.55, 0.35]

    private func colour(_ index: Int) -> Color {
        guard let shortTint else { return tint }
        return shortTint.mix(with: tint, by: MarkColouring.share(forLength: share(index)))
    }
}

private extension CGFloat {
    func rounded(toPlaces places: Int) -> CGFloat {
        let scale = pow(10, CGFloat(places))
        return (self * scale).rounded() / scale
    }
}

// MARK: - The beat

/// Finds the kicks in the music: the bass jumping above where it has been.
///
/// The marks are otherwise pure functions of one instant, and one instant
/// cannot tell a kick from a loud bass line — both are simply "a lot of
/// bass". A kick is the bass *rising* past its recent level, so this keeps
/// that level, a third of a second's worth, and answers with an envelope that
/// jumps on each rise and dies away in about a seventh of a second. Held by the
/// view that draws the mark and advanced once a frame. With nothing listening
/// it passes on the invented beat the marks already fall back to.
@MainActor
final class BeatFollower {
    private var average = 0.0
    private var envelope = 0.0
    private var last: Date?

    func update(level: Double, bands: [Double], at now: Date) -> Double {
        defer { last = now }
        let elapsed = now.timeIntervalSinceReferenceDate
        guard bands.count >= 2 else {
            return ProceduralMotion.beat(bands, at: elapsed)
        }
        let step = last.map { min(max(now.timeIntervalSince($0), 0), 0.1) } ?? 0

        let bass = bands[0] * 0.65 + bands[1] * 0.35
        average += (bass - average) * min(1, step * 3)
        let onset = min(max((bass - average - 0.02) * 5, 0), 1)
        envelope = max(onset, envelope * exp(-step * 7))
        return envelope
    }
}

