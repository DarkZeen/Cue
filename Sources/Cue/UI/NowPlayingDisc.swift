import SwiftUI

/// Cue's mark, in the corner, saying whether anything is playing.
///
/// It was a spinning record. A drawn record is a stock illustration of music
/// rather than a sign of *this* app, and a thing that turns forever is
/// motion that has stopped meaning anything by the second day. This is the app's
/// own mark instead: lit and breathing while the music plays, dimmed and still
/// when it does not.
///
/// One job each way round — *something is playing* at a glance, and *show me it*
/// on click.
struct NowPlayingDisc: View {
    let nowPlaying: PlayerService.NowPlaying
    let onOpen: () -> Void
    /// Nudges the mark into a corner. The panel tucks it against the search
    /// bar's edge; the plaque wants it centred in its own slot.
    var nudge: CGSize = CGSize(width: 2, height: 0)

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One breath every two and a half seconds — near enough to a resting pulse
    /// to read as alive, slow enough not to pull the eye off a search field
    /// somebody is typing into.
    private static let secondsPerBreath = 2.5

    var body: some View {
        TimelineView(.animation(paused: !isAnimating)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate

            ZStack {
                notes(at: elapsed)
                mark(at: elapsed)
            }
        }
        .frame(width: 34, height: 26)
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onOpen)
        .animation(.easeOut(duration: 0.14), value: isHovered)
        .animation(.easeOut(duration: 0.2), value: nowPlaying.isPlaying)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }

    private var isAnimating: Bool { nowPlaying.isPlaying && !reduceMotion }

    private var label: String {
        let what = nowPlaying.artist.map { "\(nowPlaying.title) — \($0)" } ?? nowPlaying.title
        return nowPlaying.isPlaying ? "Playing \(what). Click to open." : "Paused: \(what). Click to open."
    }

    // MARK: - The mark

    private func mark(at elapsed: TimeInterval) -> some View {
        // A sine rather than a repeating ease: a breath has no beginning and no
        // end, and any keyframed loop shows its seam eventually.
        let phase = sin(elapsed / Self.secondsPerBreath * 2 * .pi)
        let breath = isAnimating ? 1 + phase * 0.035 : 1

        return CueMark(height: 15)
            .scaleEffect(breath * (isHovered ? 1.1 : 1))
            // Paused is dimmed rather than greyed: the mark keeps its colour so
            // it still reads as Cue, it simply stops being lit.
            .opacity(nowPlaying.isPlaying ? 1 : 0.45)
            .shadow(color: .black.opacity(0.4), radius: 1.5, y: 0.5)
            .offset(x: nudge.width, y: nudge.height)
    }

    // MARK: - The notes

    /// Two notes rising and fading, on offset phases.
    ///
    /// Computed from the timeline's clock rather than held in state, so they
    /// need no animation to drive them, cannot drift out of step with the
    /// breath, and stop dead the moment the music does.
    private func notes(at elapsed: TimeInterval) -> some View {
        ForEach(0..<2, id: \.self) { index in
            let period = 2.4
            let cycle = ((elapsed / period) + Double(index) * 0.5)
                .truncatingRemainder(dividingBy: 1)

            Image(systemName: index == 0 ? "music.note" : "music.quarternote.3")
                .font(.system(size: index == 0 ? 7.5 : 8.5, weight: .medium))
                .foregroundStyle(.secondary)
                .offset(
                    x: -7 - cycle * 6 + sin(cycle * .pi * 2) * 2,
                    y: 1 - cycle * 13
                )
                // In quickly, out slowly: a note that fades in over the same
                // duration it fades out spends most of its life at half
                // opacity, which reads as blur rather than motion.
                .opacity(isAnimating ? min(cycle * 5, 1) * (1 - cycle) : 0)
        }
    }
}
