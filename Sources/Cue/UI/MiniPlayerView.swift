import SwiftUI

/// The plaque: a record, three transport buttons and a volume control.
///
/// What is left of the player once the window is gone. It has to work at a
/// glance and from the corner of the eye, so it carries no text — the title is
/// in its tooltip and in Now Playing, and a strip of truncated song name in the
/// corner of the screen is noise rather than information.
struct MiniPlayerView: View {
    let nowPlaying: PlayerService.NowPlaying

    let onOpen: () -> Void
    let onPrevious: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onToggleMute: () -> Void
    let onAdjustVolume: (Double) -> Void

    var body: some View {
        HStack(spacing: 14) {
            NowPlayingDisc(nowPlaying: nowPlaying, onOpen: onOpen, nudge: .zero)
                .frame(width: 26)

            button("backward.end.fill", "Previous", action: onPrevious)
            button(
                nowPlaying.isPlaying ? "pause.fill" : "play.fill",
                nowPlaying.isPlaying ? "Pause" : "Play",
                size: 15,
                action: onPlayPause
            )
            button("forward.end.fill", "Next", action: onNext)
            button(
                nowPlaying.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                nowPlaying.isMuted ? "Unmute" : "Mute",
                action: onToggleMute
            )
            // Click mutes, scroll adjusts. A slider would need somewhere to
            // live, and the plaque is deliberately five glyphs wide.
            .onScrollWheel { delta in onAdjustVolume(delta) }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background {
            // Solid rather than a material: this floats over other people's
            // windows, and a translucent plaque takes on whatever is behind it
            // — which over a bright document makes the glyphs unreadable.
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.white.opacity(0.09), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 10, y: 3)
        }
        // Room above and to the left for the notes to drift out of the plaque
        // without being clipped by it.
        .padding(.top, 14)
        .padding(.leading, 12)
        .help((nowPlaying.artist.map { "\(nowPlaying.title) — \($0)" } ?? nowPlaying.title)
            + "  ·  scroll the speaker for volume")
    }

    private func button(
        _ symbol: String,
        _ label: String,
        size: CGFloat = 13,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 22, height: 22)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}
