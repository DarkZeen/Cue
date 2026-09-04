import SwiftUI

/// The search field, and the only control in the panel that is always there.
struct SearchBarView: View {
    @Binding var text: String
    let isSearching: Bool
    @FocusState.Binding var isFocused: Bool
    let onClear: () -> Void
    let onSettings: () -> Void

    /// What is playing, if anything, and the way back to it.
    let nowPlaying: PlayerService.NowPlaying?
    let onOpenPlayer: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search YouTube Music", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .regular))
                .focused($isFocused)
                // Return is handled globally, alongside the arrow keys, so
                // that it means the same thing whether the caret is in the
                // field or not. Left to the field, it would only ever mean
                // "the first result".
                .onSubmit {}

            // Progress and clear occupy the same place, because they are never
            // both true and a field whose right-hand side jumps as results
            // arrive is a field that flickers.
            ZStack(alignment: .trailing) {
                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.8)
                } else if !text.isEmpty {
                    Button(action: onClear) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear")
                }
            }
            .frame(width: 16)

            if let nowPlaying {
                NowPlayingDisc(nowPlaying: nowPlaying, onOpen: onOpenPlayer)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }

            Divider()
                .frame(height: 18)

            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, 14)
        .frame(height: CueLayout.searchHeight)
        .background(
            RoundedRectangle(cornerRadius: CueLayout.searchCornerRadius)
                .fill(.quaternary.opacity(0.4))
        )
        .animation(.easeOut(duration: 0.12), value: isSearching)
        .animation(.easeOut(duration: 0.12), value: text.isEmpty)
        .animation(CueAnimation.present, value: nowPlaying == nil)
    }
}
