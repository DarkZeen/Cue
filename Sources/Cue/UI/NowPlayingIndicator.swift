import SwiftUI

/// The mark in the corner: whether anything is playing, and the way back to it.
///
/// Three forms, because the right one is a matter of taste and none of them is
/// obviously correct. What they share is the discipline: motion only while the
/// music is moving, nothing that overshoots, and everything derived from one
/// clock so no two parts can drift.
///
/// None of them listens to the audio. WebKit will not start an `AudioContext`
/// without a gesture inside the page, and Cue's player is deliberately never
/// touched — so the honest thing is motion that is *shaped* like music without
/// pretending to follow any. See `ProceduralMotion` for what that costs.
struct NowPlayingIndicator: View {
    let nowPlaying: PlayerService.NowPlaying
    /// 0 to 1, from the tap. Zero when nothing is listening, which is when the
    /// styles fall back to motion of their own.
    var level: Double = 0
    /// The spectrum, low to high. Empty unless the tap is running.
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
                case .wave:
                    WaveIndicator(elapsed: elapsed, level: level, bands: bands, isAnimating: isAnimating)
                case .disc:
                    DiscIndicator(elapsed: elapsed, level: level, bands: bands, isAnimating: isAnimating)
                case .bars:
                    BarsIndicator(elapsed: elapsed, level: level, bands: bands, isAnimating: isAnimating)
                case .orbit:
                    OrbitIndicator(elapsed: elapsed, level: level, bands: bands, isAnimating: isAnimating)
                }
            }
            // Paused is dimmed rather than greyed: the mark keeps its colour so
            // it still reads as Cue, it simply stops being lit.
            .opacity(nowPlaying.isPlaying ? 1 : 0.42)
        }
        .frame(width: style.markWidth, height: 26)
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
