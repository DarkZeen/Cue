import SwiftUI

/// What replaces the grid once there is something in the search field.
struct ResultsListView: View {
    let coordinator: LibraryCoordinator
    let presenter: CuePresenter
    let thumbnails: ThumbnailProvider
    let onOpen: (MusicItem) -> Void

    var body: some View {
        Group {
            if coordinator.results.isEmpty {
                placeholder
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var list: some View {
        ScrollViewReader { scroller in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(coordinator.results.enumerated()), id: \.element.id) { index, item in
                        ResultRow(
                            item: item,
                            isSelected: presenter.selection == index,
                            thumbnails: thumbnails,
                            onOpen: { onOpen(item) },
                            onPin: { coordinator.pinToFirstFreeSlot(item) }
                        )
                        .id(index)
                    }
                }
            }
            .scrollIndicators(.never)
            .onChange(of: presenter.selection) { _, selection in
                // Arrowing past the bottom of a seven-row window has to bring
                // the row into view, or the highlight is somewhere the user
                // cannot see and Return becomes a guess.
                guard let selection else { return }
                withAnimation(CueAnimation.selection) {
                    scroller.scrollTo(selection, anchor: .center)
                }
            }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 6) {
            if let message = coordinator.message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if coordinator.isSearching {
                // Nothing at all. The spinner is already in the search field,
                // and a second one here would be two answers to one question.
                Color.clear
            } else {
                Text("No results")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }
}

/// One search result.
private struct ResultRow: View {
    let item: MusicItem
    let isSelected: Bool
    let thumbnails: ThumbnailProvider
    let onOpen: () -> Void
    let onPin: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            artwork

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            // Only on the row being aimed at. A symbol on every row is nine
            // symbols competing with the artwork they sit next to.
            if isSelected || isHovered {
                Image(systemName: item.kind.symbolName)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: CueLayout.resultRowHeight)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(fill)
        )
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onOpen)
        .animation(.easeOut(duration: 0.1), value: isHovered)
        .animation(CueAnimation.selection, value: isSelected)
        .contextMenu {
            Button("Open in YouTube Music", action: onOpen)
            Button("Keep in the Grid", action: onPin)
            Divider()
            Button("Copy Link") {
                guard let url = item.playbackURL else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
        }
    }

    /// Selected beats hovered: the keyboard and the mouse can point at
    /// different rows at the same time, and the one Return would act on is the
    /// one that has to look chosen.
    private var fill: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(.tint.opacity(0.22)) }
        if isHovered { return AnyShapeStyle(.quaternary.opacity(0.4)) }
        return AnyShapeStyle(.clear)
    }

    private var artwork: some View {
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
                            .font(.system(size: 12, weight: .light))
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .frame(width: CueLayout.resultArtworkSize, height: CueLayout.resultArtworkSize)
        .clipShape(.rect(cornerRadius: 6))
        .onAppear { thumbnails.prefetch(item.thumbnailURL) }
    }
}
