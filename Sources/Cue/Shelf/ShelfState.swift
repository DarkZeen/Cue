import AppKit

/// Everything the shelf owns, assembled once (§42).
///
/// What was Tray's composition root, and still is for the shelf: `AppState`
/// makes one of these and starts it, and nothing else in Cue reaches past it.
/// Kept small on purpose. There is one shelf, one set of settings, one tray per
/// display, and this is where those meet. Nothing here holds state of its own —
/// it wires the pieces together and reconciles what the system tells us at
/// launch.
@MainActor
final class ShelfState {
    let store = TrayStore()
    let thumbnails = FileThumbnailProvider()
    let settings: ShelfSettingsStore
    let launchAtLogin: LaunchAtLoginService
    let quickLook = QuickLookService()

    private(set) var displays: DisplayCoordinator!
    private let statusItem = StatusItemController()
    private var settingsWindow: SettingsWindowController?

    private let logger = Diagnostics.logger("shelf")

    /// The login item belongs to the app, not the shelf, so it is handed in:
    /// one registration, one switch, whichever settings page it is shown on.
    init(launchAtLogin: LaunchAtLoginService) {
        ShelfSettingsStore.importFromTray()
        self.settings = ShelfSettingsStore()
        self.launchAtLogin = launchAtLogin
    }

    func start() {
        displays = DisplayCoordinator(
            store: store,
            thumbnails: thumbnails,
            settings: settings
        )

        displays.onQuickLookRequest = { [weak self] item in
            guard let self else { return }
            self.quickLook.preview(item, within: self.store.items)
        }

        displays.onOpenSettingsRequest = { [weak self] in self?.showSettings() }

        // Changing how the tray looks opens the tray. Set here rather than in
        // the store's initialiser because the displays do not exist yet then.
        settings.onPreviewRequested = { [weak self] in self?.displays.previewActive() }

        configureStatusItem()

        // The startup repair pass from §34: the stored wish and the system's
        // registration are reconciled before anything else can read either.
        settings.launchAtLoginIntent = launchAtLogin.reconcile(
            intent: settings.launchAtLoginIntent
        )

        seedForDebugging()

        logger.notice("Shelf started with \(NSScreen.screens.count, privacy: .public) display(s).")
    }

    /// Compiles away entirely outside debug builds — see `Diagnostics`.
    private func seedForDebugging() {
        let urls = Diagnostics.debugSeedURLs
        if !urls.isEmpty { store.add(urls) }

        // Holding the tray open implies wanting to see it, including when it
        // is empty — which is the one state a seed cannot produce.
        if Diagnostics.debugSettingsPane != nil { showSettings() }

        guard !urls.isEmpty || Diagnostics.holdsTrayOpen else { return }
        displays.openActive()
    }

    // MARK: - Menu bar

    private func configureStatusItem() {
        statusItem.onOpenTray = { [weak self] in self?.displays.openActive() }
        statusItem.onOpenSettings = { [weak self] in self?.showSettings() }
        statusItem.isLaunchAtLoginEnabled = { [weak self] in
            self?.launchAtLogin.state.isEffectivelyEnabled ?? false
        }
        statusItem.launchAtLoginExplanation = { [weak self] in
            self?.launchAtLogin.state.explanation
        }
        statusItem.onToggleLaunchAtLogin = { [weak self] in
            guard let self else { return }
            self.setLaunchAtLogin(!self.launchAtLogin.state.isEffectivelyEnabled)
        }

        statusItem.setVisible(settings.showsMenuBarIcon)
    }

    /// Writes the wish first, then attempts the registration, then adopts
    /// whatever actually happened — so the UI can never show a toggle the
    /// system disagrees with (§34).
    func setLaunchAtLogin(_ enabled: Bool) {
        // A deliberate choice, so it is recorded as one.
        settings.launchAtLoginIntent = enabled
        let result = launchAtLogin.setEnabled(enabled)

        if case .requiresApproval = result {
            launchAtLogin.openLoginItemsSettings()
        }
    }

    func setMenuBarIconVisible(_ visible: Bool) {
        settings.showsMenuBarIcon = visible
        statusItem.setVisible(visible)
    }

    // MARK: - Settings

    func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(state: self)
        }
        settingsWindow?.show()
    }
}
