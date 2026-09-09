import SwiftUI

/// The mark in the corner: whether anything is playing, and the way back to it.
///
/// Three forms, because the right one is a matter of taste and none of them is
/// obviously correct. What they share is the discipline: motion only while the
/// music is moving, nothing that overshoots, and everything derived from one
/// clock so no two parts can drift.
struct NowPlayingIndicator: View {
    let nowPlaying: PlayerService.NowPlaying
    /// 0 to 1, already shaped by the envelope in `PlayerService`.
    var level: Double = 0
    /// The spectrum, low to high. Only the bars use it.
    var bands: [Double] = []
    var style: PlaqueAnimation = .wave
    let onOpen: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isAnimating: Bool { nowPlaying.isPlaying && !reduceMotion }

    var body: some View {
        TimelineView(.animation(paused: !isAnimating)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate

            Group {
                switch style {
                case .wave: WaveIndicator(elapsed: elapsed, level: level, isAnimating: isAnimating)
                case .disc: DiscIndicator(elapsed: elapsed, level: level, isAnimating: isAnimating)
                case .bars: BarsIndicator(elapsed: elapsed, level: level, bands: bands, isAnimating: isAnimating)
                }
            }
            // Paused is dimmed rather than greyed: the mark keeps its colour so
            // it still reads as Cue, it simply stops being lit.
            .opacity(nowPlaying.isPlaying ? 1 : 0.42)
        }
        .frame(width: style == .bars ? 46 : 26, height: 26)
        .scaleEffect(isHovered ? 1.09 : 1)
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onOpen)
        // Short and flat. This sits beside a field people type into, and a
        // hover response with any bounce in it becomes a tic within a day.
        .animation(.easeOut(duration: 0.13), value: isHovered)
        .animation(.easeOut(duration: 0.25), value: nowPlaying.isPlaying)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }

    private var label: String {
        let what = nowPlaying.artist.map { "\(nowPlaying.title) — \($0)" } ?? nowPlaying.title
        return nowPlaying.isPlaying ? "Playing \(what). Click to open." : "Paused: \(what). Click to open."
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
private struct WaveIndicator: View {
    let elapsed: TimeInterval
    let level: Double
    let isAnimating: Bool

    private var count: Int { CueWavePath.shapes.count }

    /// Small. The mark is a status light beside a search field, not a
    /// centrepiece, and at this size the shapes read as one object that moves
    /// rather than nine that wobble.
    private static let height: CGFloat = 18

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

    /// A slow swell, lifted by whatever is playing.
    private var pulse: CGFloat {
        guard isAnimating else { return 1 }

        // A sine rather than a repeating ease: a breath has no beginning and no
        // end, and any keyframed loop shows its seam eventually.
        let breath = sin(elapsed / 2.6 * 2 * .pi)
        return 1 + CGFloat(breath * 0.035) + CGFloat(min(max(level, 0), 1) * 0.09)
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
        let amplitude = 0.10 + 0.62 * min(max(level, 0), 1)

        // Never collapses to nothing: a shape that reaches zero height leaves a
        // gap in the mark and reads as a rendering fault rather than as quiet.
        return max(1 + CGFloat(wave * amplitude) * reach, 0.22)
    }
}

private struct CueWaveShape: Shape {
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

/// A record turning, with notes drifting off it.
private struct DiscIndicator: View {
    let elapsed: TimeInterval
    let level: Double
    let isAnimating: Bool

    /// One turn every four seconds. A record at 33⅓ rpm is 1.8 seconds a turn,
    /// which at this size reads as a wobble rather than a rotation.
    private static let secondsPerTurn = 4.0

    var body: some View {
        ZStack {
            notes
            disc
        }
    }

    private var disc: some View {
        let turns = isAnimating ? elapsed / Self.secondsPerTurn : 0
        let angle = Angle.degrees(turns.truncatingRemainder(dividingBy: 1) * 360)

        return ZStack {
            Circle().fill(CuePalette.accent)

            // Grooves. Without them a plain circle turning is indistinguishable
            // from a plain circle sitting still, and the rotation — the entire
            // point — becomes invisible.
            ForEach(0..<3, id: \.self) { ring in
                Circle()
                    .strokeBorder(.black.opacity(0.16), lineWidth: 0.6)
                    .padding(2.0 + Double(ring) * 2.2)
            }

            // The off-centre label is what actually sells the spin: a
            // rotationally symmetric disc looks static however fast it turns.
            Circle().fill(.white.opacity(0.9)).frame(width: 4.5, height: 4.5).offset(x: 2.8)
            Circle().fill(.black.opacity(0.55)).frame(width: 1.6, height: 1.6).offset(x: 2.8)
        }
        .rotationEffect(angle)
        .frame(width: 22, height: 22)
        // The one place the level shows on this style: the record leans into
        // a loud passage rather than turning at a constant, indifferent rate.
        .scaleEffect(1 + CGFloat(level) * 0.07)
        .offset(x: 3)
    }

    private var notes: some View {
        ForEach(0..<2, id: \.self) { index in
            let period = 2.4
            let cycle = ((elapsed / period) + Double(index) * 0.5)
                .truncatingRemainder(dividingBy: 1)

            Image(systemName: index == 0 ? "music.note" : "music.quarternote.3")
                .font(.system(size: index == 0 ? 7 : 8, weight: .medium))
                .foregroundStyle(.secondary)
                .offset(x: -7 - cycle * 6 + sin(cycle * .pi * 2) * 2, y: 1 - cycle * 13)
                // In quickly, out slowly: a note that fades in over the same
                // duration it fades out spends most of its life at half
                // opacity, which reads as blur rather than motion.
                .opacity(isAnimating ? min(cycle * 5, 1) * (1 - cycle) : 0)
        }
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
private struct BarsIndicator: View {
    let elapsed: TimeInterval
    let level: Double
    /// The spectrum, low to high. Empty when nothing is being analysed, in
    /// which case the bars fall back to a rhythm of their own.
    let bands: [Double]
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

    /// The level for a band, from the spectrum when there is one.
    private func reading(_ band: Int) -> Double {
        if bands.indices.contains(band) { return bands[band] }

        // No analyser. This is invention, and it should at least be invention
        // shaped like music rather than a sine wave wearing a costume.
        //
        // Three things separate the two. A pulse at a plausible tempo, so the
        // whole meter lifts together the way it does on a beat. Bands that
        // decay at different speeds, because bass rings on and hi-hats do not.
        // And rates that share no common factor, so the pattern never visibly
        // repeats — the eye finds a period in seconds otherwise, which is what
        // makes a fake meter look fake.
        let position = Double(band) / Double(Self.bandCount - 1)

        // Roughly 100bpm. Sharpened so it reads as a hit rather than a swell.
        let beat = pow((sin(elapsed * 1.7 * .pi) + 1) / 2, 3)

        let rate = 2.3 + Double(band) * 0.61 + position * 1.4
        let wobble = (sin(elapsed * rate + Double(band) * 1.7)
            + sin(elapsed * rate * 0.41 + Double(band) * 3.1)) / 4 + 0.5

        // The low bands follow the beat; the high ones chatter over it.
        let follow = 1 - position
        let shape = wobble * (0.45 + 0.55 * position) + beat * follow * 0.8

        return (0.16 + 0.5 * level) * min(shape, 1)
    }

    /// The tall middle is the brightest, the tips fade out. It is the depth
    /// cue the reference has, and it stops seventeen identical strokes reading
    /// as a comb.
    private func opacity(_ index: Int) -> Double {
        let distance = Double(abs(index - (Self.bandCount - 1))) / Double(Self.bandCount - 1)
        return 1 - 0.45 * distance
    }
}
