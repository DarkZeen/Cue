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

    private var panel: CueWindowController?
    private var settingsWindow: NSWindow?

    private let logger = Diagnostics.logger("app-state")

    init() {
        let coordinator = LibraryCoordinator(settings: settings)
        let player = PlayerService()

        self.coordinator = coordinator
        self.player = player
        self.playback = PlaybackService(settings: settings, player: player)
        self.miniPlayer = MiniPlayerController(player: player, settings: settings)
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
        player.onStateChange = { [weak self] in self?.miniPlayer.sync() }
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
            player: player
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
