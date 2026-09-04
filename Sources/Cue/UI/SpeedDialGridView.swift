import SwiftUI

/// The three-by-three grid.
///
/// A fixed nine positions in reading order, always drawn, whether or not there
/// is anything in them. That is the entire idea: the thing in the second slot
/// is in the second slot every time, so it can be reached with ⌘2 without
/// looking, and an empty slot is a place rather than an absence.
struct SpeedDialGridView: View {
    let coordinator: LibraryCoordinator
    let presenter: CuePresenter
    let thumbnails: ThumbnailProvider
    let onOpen: (MusicItem) -> Void

    var body: some View {
        let tiles = coordinator.tiles

        VStack(spacing: CueLayout.tileSpacing) {
            ForEach(0..<CueLayout.gridRows, id: \.self) { row in
                HStack(spacing: CueLayout.tileSpacing) {
                    ForEach(0..<CueLayout.gridColumns, id: \.self) { column in
                        let index = row * CueLayout.gridColumns + column
                        TileView(
                            item: tiles.indices.contains(index) ? tiles[index] : nil,
                            index: index,
                            isPinned: coordinator.isPinned(at: index),
                            isSelected: presenter.selection == index,
                            thumbnails: thumbnails,
                            onOpen: {
                                guard let item = tiles[index] else { return }
                                onOpen(item)
                            },
                            onPin: {
                                guard let item = tiles[index] else { return }
                                coordinator.pin(item, at: index)
                            },
                            onUnpin: { coordinator.unpin(at: index) }
                        )
                    }
                }
            }
        }
        .frame(height: CueLayout.gridHeight)
        .onAppear {
            presenter.setSelectableCount(SettingsStore.tileCount)
            // Opening the panel is the only signal Cue gets that someone wants
            // to look at their library, so it is the only place a refresh is
            // triggered from. `refresh` rate-limits itself; opening the panel
            // ten times in a minute is one request.
            coordinator.refresh()
            for tile in coordinator.tiles { thumbnails.prefetch(tile?.thumbnailURL) }
        }
    }
}
