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
                case .bars: BarsIndicator(elapsed: elapsed, level: level, isAnimating: isAnimating)
                }
            }
            // Paused is dimmed rather than greyed: the mark keeps its colour so
            // it still reads as Cue, it simply stops being lit.
            .opacity(nowPlaying.isPlaying ? 1 : 0.42)
        }
        .frame(width: 34, height: 28)
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

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                CueWaveShape(index: index)
                    .fill(.white)
                    .scaleEffect(y: displacement(index), anchor: .center)
            }
        }
        .frame(width: 28 * CueWavePath.aspect, height: 28)
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

/// Level bars, the way a meter has always looked.
private struct BarsIndicator: View {
    let elapsed: TimeInterval
    let level: Double
    let isAnimating: Bool

    private static let count = 5

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<Self.count, id: \.self) { index in
                Capsule()
                    .fill(.white)
                    .frame(width: 3, height: height(index))
            }
        }
        .frame(height: 26)
    }

    private func height(_ index: Int) -> CGFloat {
        let resting: CGFloat = 6
        guard isAnimating else { return resting }

        // Each bar runs at its own rate, so they never march in step — which is
        // what separates a meter from a row of blinking lights.
        let rate = 2.6 + Double(index) * 0.47
        let wave = (sin(elapsed * rate + Double(index) * 1.3) + 1) / 2

        // The centre bars sit taller at rest, which gives the group a shape
        // even in near-silence.
        let middle = Double(Self.count - 1) / 2
        let bias = 1 - abs(Double(index) - middle) / (middle + 1)

        let reach = 5 + 17 * min(max(level, 0), 1)
        return resting + CGFloat(bias * (0.35 + 0.65 * wave) * reach)
    }
}
