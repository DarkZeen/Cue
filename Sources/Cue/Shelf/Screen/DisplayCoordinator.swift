import AppKit

/// One tray per display, kept in step with the hardware (§11).
///
/// The tray is not pinned to the main display. Every connected screen gets its
/// own panel, so a file dragged toward the top of the second monitor is caught
/// by *that* monitor's tray — which is the behaviour §11 makes mandatory.
///
/// All the displays share one `TrayStore`: the shelf is a single set of files
/// that happens to be reachable from several places, not a separate pile per
/// screen.
///
/// What is playing is the exception. It is shown on one display only — see
/// `nowPlayingDisplay(among:)`.
@MainActor
final class DisplayCoordinator {
    private let store: TrayStore
    private let thumbnails: FileThumbnailProvider
    private let settings: ShelfSettingsStore
    private let nowPlaying: NowPlayingSource?
    private let screens = ScreenGeometryService()

    private var controllers: [CGDirectDisplayID: TrayWindowController] = [:]
    private let logger = Diagnostics.logger("displays")

    var onQuickLookRequest: ((TrayItem) -> Void)?
    var onOpenSettingsRequest: (() -> Void)?

    init(
        store: TrayStore,
        thumbnails: FileThumbnailProvider,
        settings: ShelfSettingsStore,
        nowPlaying: NowPlayingSource? = nil
    ) {
        self.store = store
        self.thumbnails = thumbnails
        self.settings = settings
        self.nowPlaying = nowPlaying

        screens.onChange = { [weak self] in
            self?.synchronise()
        }
        synchronise()
    }

    /// The tray the user is currently looking at — the one on the display the
    /// pointer is on.
    var activeController: TrayWindowController? {
        if let id = screens.geometryUnderPointer?.id, let controller = controllers[id] {
            return controller
        }
        return controllers.values.first
    }

    func openActive() {
        activeController?.open()
    }

    func toggleActive() {
        activeController?.toggle()
    }

    /// Shows the tray on the display the pointer is on, because a setting that
    /// changes how it looks just changed. The pointer is over the Settings
    /// window, so this is the screen the user is already looking at.
    func previewActive() {
        activeController?.showPreview()
    }

    func collapseAll() {
        for controller in controllers.values { controller.collapse() }
    }

    // MARK: - What is playing

    /// The one display whose shelf grows the now-playing wings.
    ///
    /// One, not all: the wings are controls, and a double click that likes a
    /// song on every screen at once, or a mark animating on each of them, is
    /// several of a thing that should be single (§26). Not the display under
    /// the pointer either, which changes as the pointer moves — the wings
    /// would hop between screens on the way to them.
    ///
    /// The built-in notched display when there is one, because that is where
    /// the island lives; otherwise the first screen, which is the one with the
    /// menu bar. `geometries` is in `NSScreen.screens` order.
    static func nowPlayingDisplay(among geometries: [ScreenGeometry]) -> CGDirectDisplayID? {
        (geometries.first(where: \.hasNotch) ?? geometries.first)?.id
    }

    // MARK: - Reacting to hardware

    /// Adds trays for new displays, removes trays for departed ones, and
    /// repositions the rest. Covers connect, disconnect, resolution change,
    /// rearrangement and wake in one path, because macOS reports all of them
    /// the same way (§11).
    private func synchronise() {
        let current = screens.geometries
        let currentIDs = Set(current.map(\.id))
        let showing = nowPlaying == nil ? nil : Self.nowPlayingDisplay(among: current)

        for (id, controller) in controllers where !currentIDs.contains(id) {
            logger.notice("Display \(id, privacy: .public) went away; removing its tray.")
            controller.close()
            controllers[id] = nil
        }

        for geometry in current {
            if let existing = controllers[geometry.id] {
                existing.reposition(to: geometry)
                // Every time, not only when a display arrives: unplugging the
                // screen that had the wings has to hand them to another.
                existing.showsNowPlaying = geometry.id == showing
            } else {
                logger.notice("Display \(geometry.id, privacy: .public) appeared; adding a tray.")
                let controller = TrayWindowController(
                    geometry: geometry,
                    store: store,
                    thumbnails: thumbnails,
                    settings: settings,
                    nowPlaying: nowPlaying,
                    showsNowPlaying: geometry.id == showing
                )
                controller.onQuickLookRequest = { [weak self] item in
                    self?.onQuickLookRequest?(item)
                }
                controller.onOpenSettingsRequest = { [weak self] in
                    self?.onOpenSettingsRequest?()
                }
                controllers[geometry.id] = controller
            }
        }
    }
}
