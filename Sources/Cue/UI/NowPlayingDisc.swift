import SwiftUI

/// The spinning record in the panel's corner.
///
/// The only sign, once the player is invisible, that Cue is playing anything at
/// all — and the way back to it. It has one job each way round: *something is
/// playing* at a glance, and *show me it* on click.
///
/// It spins only while the music does. A disc that keeps turning through a
/// pause is worse than no disc, because it is confidently wrong about the one
/// thing it exists to report.
struct NowPlayingDisc: View {
    let nowPlaying: PlayerService.NowPlaying
    let onOpen: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One turn every four seconds. A record at 33⅓ rpm is 1.8 seconds a turn,
    /// which at this size reads as a wobble rather than a rotation — this is
    /// slow enough to be legible as movement and quiet enough to sit next to a
    /// search field you are typing into.
    private static let secondsPerTurn = 4.0

    var body: some View {
        // Paused with the music, so the whole thing genuinely stops rather than
        // freezing a frame and continuing to schedule redraws.
        TimelineView(.animation(paused: !nowPlaying.isPlaying || reduceMotion)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate

            ZStack {
                notes(at: elapsed)
                disc(at: elapsed)
            }
        }
        .frame(width: 34, height: 30)
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onOpen)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }

    private var label: String {
        let what = nowPlaying.artist.map { "\(nowPlaying.title) — \($0)" } ?? nowPlaying.title
        return nowPlaying.isPlaying ? "Playing \(what). Click to open." : "Paused: \(what). Click to open."
    }

    // MARK: - The disc

    private func disc(at elapsed: TimeInterval) -> some View {
        let turns = reduceMotion ? 0 : elapsed / Self.secondsPerTurn
        let angle = Angle.degrees(turns.truncatingRemainder(dividingBy: 1) * 360)

        return ZStack {
            Circle()
                .fill(Color(red: 1.0, green: 0.0, blue: 0.2))

            // Grooves. Without them a plain red circle turning is indistinguish-
            // able from a plain red circle sitting still, and the rotation —
            // the entire point — becomes invisible.
            ForEach(0..<3, id: \.self) { ring in
                Circle()
                    .strokeBorder(.black.opacity(0.16), lineWidth: 0.6)
                    .padding(3.0 + Double(ring) * 2.6)
            }

            // The off-centre label is what actually sells the spin: a
            // rotationally symmetric disc looks static however fast it turns.
            Circle()
                .fill(.white.opacity(0.9))
                .frame(width: 5, height: 5)
                .offset(x: 3.2)

            Circle()
                .fill(.black.opacity(0.55))
                .frame(width: 1.8, height: 1.8)
                .offset(x: 3.2)
        }
        .rotationEffect(angle)
        .frame(width: 20, height: 20)
        .overlay {
            // Shown on hover instead of always: the disc is a status light
            // first, and a button only once you have reached for it.
            if isHovered {
                Image(systemName: nowPlaying.isPlaying ? "play.fill" : "pause.fill")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.white)
                    .shadow(radius: 1)
            }
        }
        .scaleEffect(isHovered ? 1.12 : 1)
        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        .offset(x: 5, y: 4)
    }

    // MARK: - The notes

    /// Two notes rising and fading, on offset phases.
    ///
    /// Computed from the timeline's clock rather than held in state, so they
    /// need no animation to drive them, cannot drift out of step with the disc,
    /// and stop dead the moment the music does.
    private func notes(at elapsed: TimeInterval) -> some View {
        ForEach(0..<2, id: \.self) { index in
            let period = 2.4
            let phase = ((elapsed / period) + Double(index) * 0.5)
                .truncatingRemainder(dividingBy: 1)

            Image(systemName: index == 0 ? "music.note" : "music.quarternote.3")
                .font(.system(size: index == 0 ? 8 : 9, weight: .medium))
                .foregroundStyle(.secondary)
                // Rising and drifting left, away from the disc in the corner.
                .offset(
                    x: -6 - phase * 7 + sin(phase * .pi * 2) * 2,
                    y: 2 - phase * 14
                )
                // In quickly, out slowly: a note that fades in over the same
                // duration it fades out spends most of its life at half
                // opacity, which reads as blur rather than motion.
                .opacity(nowPlaying.isPlaying && !reduceMotion ? min(phase * 5, 1) * (1 - phase) : 0)
        }
    }
}
