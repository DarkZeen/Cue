import SwiftUI

/// One square of the speed dial.
///
/// Three states worth telling apart: pinned (the user put it there), suggested
/// (Cue guessed, and it may be something else tomorrow), and empty. A suggested
/// tile is drawn a little back so that the difference is visible without a
/// badge — the point of a speed dial is muscle memory, and the tiles you can
/// trust to stay put should look different from the ones you cannot.
struct TileView: View {
    let item: MusicItem?
    let index: Int
    let isPinned: Bool
    let isSelected: Bool
    let thumbnails: ThumbnailProvider

    let onOpen: () -> Void
    let onPin: () -> Void
    let onUnpin: () -> Void

    @State private var isHovered = false

    var body: some View {
        Group {
            if let item {
                filled(item)
            } else {
                empty
            }
        }
        .frame(width: CueLayout.tileWidth, height: CueLayout.tileHeight)
        .background(background)
        .clipShape(.rect(cornerRadius: CueLayout.tileCornerRadius))
        .overlay(selectionRing)
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .onTapGesture { if item != nil { onOpen() } }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(CueAnimation.selection, value: isSelected)
        .contextMenu { menu }
        .help(item.map(\.title) ?? "Empty")
    }

    private func filled(_ item: MusicItem) -> some View {
        VStack(spacing: 8) {
            artwork(item)

            VStack(spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 12)
        // Suggested tiles sit back. Not greyed out — they are perfectly good
        // things to click — just quieter than the ones that were chosen.
        .opacity(isPinned ? 1 : 0.82)
    }

    private func artwork(_ item: MusicItem) -> some View {
        ZStack {
            if let image = thumbnails.image(for: item.thumbnailURL) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.quaternary.opacity(0.5))
                    .overlay(
                        Image(systemName: item.kind.symbolName)
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .frame(width: CueLayout.tileArtworkSize, height: CueLayout.tileArtworkSize)
        .clipShape(.rect(cornerRadius: 8))
        .onAppear { thumbnails.prefetch(item.thumbnailURL) }
    }

    private var empty: some View {
        // A hairline dashed square rather than nothing at all: nine positions
        // that keep their shape when eight of them are full is what makes the
        // grid a grid.
        RoundedRectangle(cornerRadius: CueLayout.tileCornerRadius)
            .strokeBorder(
                .quaternary,
                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
            )
            .overlay(
                Text("\(index + 1)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.quaternary)
            )
            .padding(1)
    }

    @ViewBuilder
    private var background: some View {
        if item == nil {
            Color.clear
        } else {
            Rectangle().fill(.quaternary.opacity(isHovered ? 0.5 : 0.28))
        }
    }

    @ViewBuilder
    private var selectionRing: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: CueLayout.tileCornerRadius)
                .strokeBorder(.tint, lineWidth: 2)
        }
    }

    @ViewBuilder
    private var menu: some View {
        if let item {
            Button("Open in YouTube Music", action: onOpen)
            Divider()
            if isPinned {
                Button("Unpin", action: onUnpin)
            } else {
                // The tile is already here — it was suggested. Pinning is
                // saying "and keep it here", which is why the wording is not
                // "Add".
                Button("Keep in This Slot", action: onPin)
            }
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
