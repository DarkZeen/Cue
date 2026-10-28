import SwiftUI

/// What a song's context menu can do besides open it.
///
/// Handed down through the environment rather than as three more closures on
/// every tile and row: the grid, the gallery and the results list all want the
/// same three entries, and none of them has anything to add to them.
struct SongActions {
    var isAvailable: (MusicItem) -> Bool = { _ in false }
    var playNext: (MusicItem) -> Void = { _ in }
    var rate: (MusicItem, PlayerService.Rating) -> Void = { _, _ in }
}

extension EnvironmentValues {
    @Entry var songActions = SongActions()
}

/// Play Next, Like and Dislike — for songs only, and only when Cue is the one
/// playing them. An album has no single thing to like, and a browser hand-off
/// has no queue Cue can reach.
struct SongMenu: View {
    let item: MusicItem

    @Environment(\.songActions) private var actions

    var body: some View {
        if actions.isAvailable(item) {
            Button("Play Next") { actions.playNext(item) }
            Divider()
            Button("Like") { actions.rate(item, .like) }
            Button("Dislike") { actions.rate(item, .dislike) }
        }
    }
}
