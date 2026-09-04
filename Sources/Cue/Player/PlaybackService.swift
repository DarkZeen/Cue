import AppKit
import Foundation

/// Where a chosen item actually goes.
///
/// One place, so the panel does not have to know whether Cue plays music itself
/// this week, and so the choice between the two is a setting rather than a
/// rewrite.
@MainActor
final class PlaybackService {
    let player: PlayerService

    private let settings: SettingsStore
    private let coordinator: LibraryCoordinator
    private let logger = Diagnostics.logger("playback")

    init(settings: SettingsStore, player: PlayerService, coordinator: LibraryCoordinator) {
        self.settings = settings
        self.player = player
        self.coordinator = coordinator
    }

    /// Plays or hands off, depending on the setting. Returns false when it
    /// could do neither, so the caller can leave the panel open rather than
    /// dismissing it as though something happened.
    @discardableResult
    func open(_ item: MusicItem) -> Bool {
        switch settings.playbackDestination {
        case .inApp:
            // An album has to be resolved to its playlist before it can play,
            // and that costs a request. Started rather than awaited, so the
            // panel closes on the click instead of after the network — the
            // whole point of the app is that picking something is instant.
            let shuffles = settings.shufflesContainers
            Task { [player, coordinator] in
                let playable = await coordinator.playable(for: item)
                // Anything without a track of its own is a container — an
                // album, a playlist, a radio — and containers are what
                // shuffling means. A single song has nothing to shuffle.
                let isContainer = playable.videoID == nil && playable.playlistID != nil
                _ = player.play(playable, shuffled: shuffles && isContainer)
            }
            return true

        case .browser:
            guard let url = item.playbackURL else {
                logger.error("No playable URL for a \(item.kind.rawValue, privacy: .public).")
                return false
            }
            logger.notice("Handing a \(item.kind.rawValue, privacy: .public) to the browser.")
            return NSWorkspace.shared.open(url)
        }
    }
}

/// What happens when you pick something.
enum PlaybackDestination: String, Codable, CaseIterable, Sendable {
    /// Cue's own player window. The default, and the point of the app.
    case inApp
    /// The system browser, as Cue did before it had a player of its own. Kept
    /// because someone whose browser is already signed in, already playing, and
    /// already where they want their music may genuinely prefer it.
    case browser

    var title: String {
        switch self {
        case .inApp: "Play in Cue"
        case .browser: "Open in my browser"
        }
    }
}
