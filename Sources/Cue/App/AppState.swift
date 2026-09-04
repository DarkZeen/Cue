import AppKit
import SwiftUI

/// Where everything is built and held.
///
/// One composition root rather than singletons scattered through the app: the
/// providers, the coordinator, the panel and the settings window are all made
/// here, once, and handed to whatever needs them. It is the only place in Cue
/// that knows the whole shape of the app.
@MainActor
final class AppState {
    let settings = SettingsStore()
    let thumbnails = ThumbnailProvider()
    let launchAtLogin = LaunchAtLoginService()
    let hotKey = HotKeyService()
    let coordinator: LibraryCoordinator
    let player: PlayerService
    let playback: PlaybackService
    let miniPlayer: MiniPlayerController
    let layoutEditor = LayoutEditor()

    private var panel: CueWindowController?
    private var settingsWindow: NSWindow?

    private let logger = Diagnostics.logger("app-state")

    init() {
        // Before anything that reads the keychain. See `repairKeychainIfNeeded`.
        Self.repairKeychainIfNeeded()

        let coordinator = LibraryCoordinator(settings: settings)
        let player = PlayerService()

        self.coordinator = coordinator
        self.player = player
        self.playback = PlaybackService(settings: settings, player: player, coordinator: coordinator)
        self.miniPlayer = MiniPlayerController(player: player, settings: settings)
    }


    /// Repairs keychain items left behind by a differently-signed build.
    ///
    /// Called from `init`, before anything else, and that ordering is the whole
    /// point: `GoogleOAuthService` reads the refresh token in *its* init, so a
    /// repair that ran later would fire after the prompts it exists to prevent.
    ///
    /// Whether it is needed is asked of the keychain rather than of
    /// preferences — see `Keychain.needsRepair`. A preference recording that
    /// the repair has run is true of the build that ran it and useless to every
    /// other one.
    private static func repairKeychainIfNeeded() {
        guard Keychain.needsRepair else { return }

        let outcome = Keychain.reclaim(Keychain.allAccounts)
        // Marked only when nothing failed. A declined prompt is exactly the
        // case that needs trying again, and marking it done regardless is how
        // the repair silently never happens.
        if outcome.failed == 0 {
            Keychain.markRepaired()
        }
    }

    func start() {

        let panel = CueWindowController(
            coordinator: coordinator,
            settings: settings,
            thumbnails: thumbnails,
            playback: playback
        )
        panel.onShowSettings = { [weak self] in self?.showSettings() }
        self.panel = panel

        // Toggle rather than open: a shortcut that only ever opens leaves the
        // user reaching for Escape to undo a keystroke they pressed by mistake.
        hotKey.onFire = { [weak self] in self?.togglePanel() }
        settings.onHotKeyChange = { [weak self] in
            guard let self else { return }
            self.hotKey.register(self.settings.hotKey)
        }
        hotKey.register(settings.hotKey)

        // The plaque is the only thing on screen that says Cue is playing, so
        // it has to keep up with both the music and the window it stands in
        // for.
        // Read before anything is built, so the first presentation is already
        // the chosen size rather than briefly the designed default.
        CueLayout.panelWidth = CGFloat(settings.panelWidth)
        settings.onPanelMetricsChange = { [weak self] in self?.panel?.applyMetrics() }

        // The API borrows the player's session. Both talk to YouTube Music as
        // the same person; only one of them keeps its credentials current.
        coordinator.ytSession.liveCookies = { [weak player] in
            await player?.currentCookies() ?? []
        }

        layoutEditor.onBegin = { [weak self] in
            self?.panel?.beginEditing()
            self?.miniPlayer.beginEditing()
        }
        layoutEditor.onEnd = { [weak self] in
            self?.panel?.endEditing()
            self?.miniPlayer.endEditing()
        }
        panel.onEndEditing = { [weak self] in self?.layoutEditor.end() }

        player.onStateChange = { [weak self] in
            guard let self else { return }
            self.miniPlayer.sync()

            // The page says whether it is signed in; the API provider needs to
            // know, because signing in inside the player is now the only
            // sign-in there is.
            if let signedIn = self.player.isSignedIn,
               signedIn != self.coordinator.ytSession.playerIsSignedIn {
                self.coordinator.ytSession.playerIsSignedIn = signedIn
                self.coordinator.refresh(force: true)
            }
        }
        settings.onMiniPlayerChange = { [weak self] in self?.miniPlayer.sync() }

        let shortcut = settings.hotKey?.displayString ?? "none"
        logger.notice("Started. \(self.coordinator.connectionSummary, privacy: .public); shortcut \(shortcut, privacy: .public).")

        if let videoID = Diagnostics.debugPlayVideoID {
            playback.open(MusicItem(
                id: "debug:\(videoID)",
                title: "Debug",
                kind: .song,
                videoID: videoID,
                source: .dataAPI
            ))
        }
        if let query = Diagnostics.debugQuery { coordinator.query = query }
        // Built at launch rather than on first play, so the window gets its one
        // moment of visibility, and YouTube Music gets the seconds it needs to
        // build a player, before anyone has asked for a song.
        if settings.playbackDestination == .inApp { player.warmUp() }

        if Diagnostics.opensPanelAtLaunch || Diagnostics.debugQuery != nil { openPanel() }
        if Diagnostics.debugSettingsPane != nil { showSettings() }
    }

    // MARK: - Panel

    func openPanel() {
        panel?.present()
    }

    func togglePanel() {
        panel?.toggle()
    }

    func closePanel() {
        panel?.dismiss()
    }

    // MARK: - Player

    /// Shows the player window, or hides it if it is already up.
    func togglePlayer() {
        player.isWindowVisible ? player.hide() : player.showHome()
    }

    // MARK: - Settings

    func showSettings() {
        // The panel and the settings window are two different answers to the
        // same question and should never be on screen together — the panel
        // closes when it loses focus anyway, but doing it here means the
        // settings window is not competing with a dismissal animation.
        closePanel()

        if let settingsWindow {
            NSApp.activate()
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }

        let view = SettingsView(
            settings: settings,
            coordinator: coordinator,
            launchAtLogin: launchAtLogin,
            hotKey: hotKey,
            player: player,
            onResetMiniPlayer: { [weak self] in self?.miniPlayer.resetPosition() },
            onEditLayout: { [weak self] in self?.layoutEditor.begin() }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Cue Settings"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("CueSettings")

        settingsWindow = window

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
