import SwiftUI

/// One cover in the gallery grid.
///
/// The artwork is the tile. A title sits over it, and nothing else does: nine
/// covers with two lines of metadata each is eighteen lines of text competing
/// with the only thing on screen that is actually recognisable at a glance.
struct ArtworkTileView: View {
    let item: MusicItem?
    let index: Int
    let isSelected: Bool
    let isPinned: Bool
    let showsEmptySlots: Bool
    /// The tile's side. Passed in rather than read from a static, so moving the
    /// size slider actually re-lays the tile out.
    let side: CGFloat
    let thumbnails: ThumbnailProvider

    let onOpen: () -> Void
    let onPin: () -> Void
    let onUnpin: () -> Void
    let isInAlbums: Bool
    let onToggleAlbum: () -> Void

    @State private var isHovered = false

    var body: some View {
        Group {
            if let item {
                filled(item)
            } else if showsEmptySlots {
                empty
            } else {
                Color.clear
            }
        }
        .frame(width: side, height: side)
        .clipShape(.rect(cornerRadius: CueLayout.Gallery.tileCornerRadius))
        .overlay(selectionRing)
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .onTapGesture { if item != nil { onOpen() } }
        .animation(.easeOut(duration: 0.14), value: isHovered)
        .animation(CueAnimation.selection, value: isSelected)
        .contextMenu { menu }
        .help(item.map(description) ?? "Empty")
        .accessibilityLabel(item.map(description) ?? "Empty slot \(index + 1)")
        .accessibilityAddTraits(item == nil ? [] : .isButton)
    }

    private func description(_ item: MusicItem) -> String {
        item.subtitle.map { "\(item.title) — \($0)" } ?? item.title
    }

    private func filled(_ item: MusicItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            artwork(item)

            // A scrim rather than a solid bar: the bottom of a cover is rarely
            // the part worth seeing, and a bar would cut every tile at the same
            // line regardless of what is underneath it.
            LinearGradient(
                colors: [.clear, .black.opacity(0.15), .black.opacity(0.82)],
                startPoint: .center,
                endPoint: .bottom
            )

            HStack(spacing: 5) {
                // Albums and playlists are containers; a song plays. The one
                // distinction worth a glyph, because it changes what a click
                // does.
                if item.videoID == nil {
                    Image(systemName: item.kind == .album ? "square.stack.fill" : "music.note.list")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                }

                Text(item.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // Covers are photographs. Without this the title is
                    // unreadable over the bright ones however dark the scrim.
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 0.5)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 9)
        }
        // Lifts toward the pointer. The scale is small because nine tiles
        // enlarging by a noticeable amount turns a grid into a fairground.
        .scaleEffect(isHovered ? 1.02 : 1)
        .brightness(isHovered ? 0.04 : 0)
    }

    private func artwork(_ item: MusicItem) -> some View {
        // Read so this view redraws when a cover arrives. See
        // `ThumbnailProvider.version`.
        let _ = thumbnails.version

        return ZStack {
            CuePalette.tileGround

            if let image = thumbnails.image(for: item.thumbnailURL) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                // Not a spinner. A tile that is briefly a quiet rectangle reads
                // as artwork arriving; a tile with a spinner in it reads as
                // something going wrong.
                CueMark(height: 26, markerColor: .white.opacity(0.25), accentColor: .white.opacity(0.14))
            }
        }
        .frame(width: side, height: side)
        .clipped()
        .animation(.easeOut(duration: 0.2), value: thumbnails.image(for: item.thumbnailURL) != nil)
        .onAppear { thumbnails.prefetch(item.thumbnailURL, soon: true) }
    }

    private var empty: some View {
        RoundedRectangle(cornerRadius: CueLayout.Gallery.tileCornerRadius)
            .strokeBorder(.white.opacity(0.09), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
            .overlay(
                Text("\(index + 1)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.22))
            )
    }

    @ViewBuilder
    private var selectionRing: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: CueLayout.Gallery.tileCornerRadius)
                .strokeBorder(CuePalette.accent, lineWidth: 2)
        }
    }

    @ViewBuilder
    private var menu: some View {
        if let item {
            Button("Play", action: onOpen)
            Divider()
            if isPinned {
                Button("Unpin", action: onUnpin)
            } else {
                Button("Keep in the Speed Dial", action: onPin)
            }
            Button(isInAlbums ? "Remove from Albums" : "Add to Albums", action: onToggleAlbum)
            Divider()
            Button("Copy Link") {
                guard let url = item.playbackURL else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
        } else {
            Text("Search for something, then keep it here.")
        }
    }
}
