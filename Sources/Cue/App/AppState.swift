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
    let updates: UpdateService

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
        self.updates = UpdateService(settings: settings)
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
        // Every launch, not once.
        //
        // A keychain item's access list is built when the item is written and
        // names the application that wrote it — and every rebuild, and every
        // automatic update, replaces that application. Recording the repair as
        // done meant it never ran again, so the prompts returned after the next
        // update and stayed. Rewriting the items each launch costs four silent
        // reads when nothing has changed, and makes the one prompt after an
        // update the last one.
        Keychain.reclaim(Keychain.allAccounts)
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
        coordinator.player = player
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
                // The first refresh runs before the player has loaded, so it
                // goes out with the stale stored cookie and comes back as a
                // stranger's library. This is the moment to ask again with
                // credentials that work.
                self.coordinator.refreshNow()
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

        player.wantsAnalysis = settings.analysesAudio
        settings.onAudioAnalysisChange = { [weak self] in
            guard let self else { return }
            self.player.wantsAnalysis = self.settings.analysesAudio

            if self.settings.analysesAudio {
                self.player.beginAnalysis()
            } else {
                // Turning it off reloads the page, which is the undo.
                //
                // `createMediaElementSource` cannot be reversed for an element,
                // but the element does not survive a reload — so the switch is
                // reversible after all, at the cost of restarting the track.
                // That matters more than the cost: it means someone whose music
                // has gone silent has a way back that is not "quit the app".
                self.player.reloadForAnalysisChange()
            }
        }

        updates.startChecking()

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
            onEditLayout: { [weak self] in self?.layoutEditor.begin() },
            updates: updates,
            onShowPlayer: { [weak self] in self?.player.showHome() }
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
