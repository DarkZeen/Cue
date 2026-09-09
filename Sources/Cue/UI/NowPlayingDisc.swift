import SwiftUI

/// Cue's mark in the corner, moving with the music.
///
/// It has been three things now, and the reasons are worth keeping. A spinning
/// record was a stock illustration of music rather than a sign of this app, and
/// a thing that turns forever stops meaning anything by the second day. A
/// breathing logo was better but said only "on" — every track looked identical.
/// A waveform can say how loud, how busy, how the music is actually going, and
/// it is the app's own mark rather than a borrowed one.
///
/// One job each way round: *something is playing* at a glance, and *show me it*
/// on click.
struct NowPlayingDisc: View {
    let nowPlaying: PlayerService.NowPlaying
    /// 0 to 1. The page's own analysis when it will give it up, and a stand-in
    /// otherwise — see `PlayerService.audioLevel`.
    var level: Double = 0
    let onOpen: () -> Void
    /// Nudges the mark into a corner. The panel tucks it against the search
    /// bar's edge; the plaque wants it centred in its own slot.
    var nudge: CGSize = .zero

    @State private var isHovered = false

    var body: some View {
        CueWaveformView(
            height: 17,
            level: level,
            isPlaying: nowPlaying.isPlaying,
            tint: .white
        )
        // Paused is dimmed rather than greyed: the mark keeps its colour so it
        // still reads as Cue, it simply stops being lit.
        .opacity(nowPlaying.isPlaying ? 1 : 0.42)
        .scaleEffect(isHovered ? 1.08 : 1)
        .offset(x: nudge.width, y: nudge.height)
        .frame(width: 32, height: 24)
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onOpen)
        .animation(.easeOut(duration: 0.14), value: isHovered)
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
