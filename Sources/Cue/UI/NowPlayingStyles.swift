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
    let isAnimating: Bool

    private var count: Int { CueWavePath.shapes.count }

    /// Small, and then smaller. The mark is a status light beside a search
    /// field, not a centrepiece; at this size the nine shapes read as one
    /// object that moves rather than nine that wobble, and the breath
    /// underneath them has room to show without the mark crowding the field.
    private static let height: CGFloat = 14

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                CueWaveShape(index: index)
                    .fill(.white)
                    .scaleEffect(y: displacement(index), anchor: .center)
            }
        }
        .frame(width: Self.height * CueWavePath.aspect, height: Self.height)
        // The whole mark breathes underneath the individual shapes.
        //
        // Two motions at different rates, which is what stops it reading as a
        // mechanism: the shapes flicker with the music while the object itself
        // swells slowly. One rate alone looks like a loop however well tuned,
        // because the eye finds the period.
        .scaleEffect(pulse)
    }

    /// A breath, riding on the slower swell.
    private var pulse: CGFloat {
        guard isAnimating else { return 1 }

        // A sine rather than a repeating ease: a breath has no beginning and no
        // end, and any keyframed loop shows its seam eventually.
        let breath = sin(elapsed / 2.6 * 2 * .pi)
        let swell = ProceduralMotion.energy(level, at: elapsed)
        // Larger than it was, because the mark is smaller than it was: the
        // same proportion on a smaller object is less motion, not equal motion.
        return 1 + CGFloat(breath * 0.05) + CGFloat(swell * 0.08)
    }

    private func displacement(_ index: Int) -> CGFloat {
        guard isAnimating else { return 1 }

        let middle = Double(count - 1) / 2
        let distance = abs(Double(index) - middle) / max(middle, 1)

        let reach = 0.28 + 0.72 * distance
        let phase = elapsed * 3.6 - distance * 1.5
        // Two sines rather than one, at an irrational-ish ratio, so the loop
        // never lands on an obvious repeat.
        let wave = (sin(phase) + sin(phase * 1.63 + 0.7)) / 2

        // Enough travel to be read from the corner of an eye. The earlier
        // values were tuned looking straight at it, which is the one way this
        // is never actually seen — and at that amplitude the mark only
        // shimmered.
        let amplitude = 0.18 + 0.44 * ProceduralMotion.energy(level, at: elapsed)

        // Never collapses to nothing: a shape that reaches zero height leaves a
        // gap in the mark and reads as a rendering fault rather than as quiet.
        return max(1 + CGFloat(wave * amplitude) * reach, 0.22)
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
/// The notes that used to drift off it are gone. They were the part that said
/// "music" without the rest of the drawing having to, and once the vinyl reads
/// as vinyl — black, grooved, a red label, an arm resting on it — saying it
/// twice is the thing that makes a mark look like clip art.
///
/// The difficulty of a record at this size is that a disc is rotationally
/// symmetric, so it looks identical however fast it turns. Real vinyl solves
/// this itself: the sheen sweeps across the grooves as the record moves, and
/// that sweep is the only part of this drawing that has to rotate for the whole
/// thing to read as spinning.
struct DiscIndicator: View {
    let elapsed: TimeInterval
    var level: Double = 0
    let isAnimating: Bool

    /// One turn every three and a half seconds. A record at 33⅓ rpm is 1.8
    /// seconds a turn, which at this size reads as a wobble rather than a
    /// rotation — the honest speed is the one that looks wrong.
    private static let secondsPerTurn = 3.4

    private static let diameter: CGFloat = 21

    var body: some View {
        ZStack(alignment: .center) {
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

    /// Bands either side of the centre. Nine gives seventeen bars, which is
    /// enough to read as a spectrum and few enough that each stays visible at
    /// this size.
    private static let bandCount = 9
    private static let barWidth: CGFloat = 1.6
    private static let spacing: CGFloat = 1.1
    private static let height: CGFloat = 26

    private var barCount: Int { Self.bandCount * 2 - 1 }

    var body: some View {
        HStack(alignment: .center, spacing: Self.spacing) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(.white.opacity(opacity(index)))
                    .frame(width: Self.barWidth, height: barHeight(index))
            }
        }
        .frame(height: Self.height)
    }

    /// Which band a bar shows: 0 at the centre, rising outward on both sides.
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
struct OrbitIndicator: View {
    let elapsed: TimeInterval
    var level: Double = 0
    let isAnimating: Bool

    /// Radius from centre, size, angular speed, where it starts.
    ///
    /// Deliberately uneven. Six identical blobs at six even speeds is a
    /// mechanism; these differ in every value they have, which is why the
    /// pairings look like something happening rather than something scheduled.
    private static let blobs: [(orbit: Double, size: Double, speed: Double, phase: Double)] = [
        (7.4, 7.4, 0.64, 0.00),
        (7.9, 6.2, 0.73, 1.10),
        (7.1, 5.6, 0.61, 2.15),
        (8.0, 6.8, 0.70, 3.25),
        (7.2, 5.2, 0.77, 4.25),
        (7.7, 6.0, 0.66, 5.35)
    ]

    var body: some View {
        Canvas { context, size in
            // The threshold has to sit where a lone blob still clears it after
            // the blur has spread it out. Too high and the small blobs vanish;
            // too low and everything is one puddle.
            context.addFilter(.alphaThreshold(min: 0.42, color: .white))

            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 2.4))

                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                // Loud makes them bigger, which makes them meet more often —
                // so the merging itself is the thing that responds, rather
                // than the blobs simply inflating.
                let swell = 0.86 + 0.28 * ProceduralMotion.energy(level, at: elapsed)

                for blob in Self.blobs {
                    let angle = blob.phase + elapsed * blob.speed
                    // The orbit breathes a little, so the ring is not a wire
                    // the blobs are threaded on.
                    let radius = blob.orbit + sin(elapsed * 0.9 + blob.phase) * 0.7
                    let point = CGPoint(
                        x: centre.x + cos(angle) * radius,
                        y: centre.y + sin(angle) * radius
                    )
                    let size = blob.size * swell
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
