import AppKit
import SwiftUI

/// The panel, its contents, and the keyboard — wired together.
///
/// The window's frame is constant. It is created at the tallest the panel can
/// be and never resized; the contents animate inside it. That keeps window
/// geometry out of the animation loop entirely, and it means the search field
/// stays exactly where it was while results appear underneath it.
@MainActor
final class CueWindowController {
    let presenter = CuePresenter()

    private let coordinator: LibraryCoordinator
    private let settings: SettingsStore
    private let thumbnails: ThumbnailProvider
    private let playback: PlaybackService

    private let panel: CuePanel
    private let container: CuePanelContentView
    private var hostingView: NSHostingView<AnyView>!

    private var keyMonitor: Any?
    private var resignObserver: (any NSObjectProtocol)?

    /// When the panel last appeared, and whether its focus has already been
    /// rescued once. See `shouldReassertFocus`.
    private var presentedAt: Date?
    private var didReassertFocus = false

    /// How long after presenting a loss of focus is treated as the system's
    /// doing rather than the user's.
    ///
    /// Measured at around 340ms on this machine; 600 leaves room without being
    /// long enough for a real click to fall inside it.
    private static let focusSettlingWindow: TimeInterval = 0.6

    private let logger = Diagnostics.logger("panel")

    /// Raised when the user asks for Settings from inside the panel.
    var onShowSettings: (() -> Void)?

    init(
        coordinator: LibraryCoordinator,
        settings: SettingsStore,
        thumbnails: ThumbnailProvider,
        playback: PlaybackService
    ) {
        self.coordinator = coordinator
        self.settings = settings
        self.thumbnails = thumbnails
        self.playback = playback

        let frame = NSRect(
            x: 0,
            y: 0,
            width: CueLayout.panelWidth,
            height: CueLayout.panelHeight
        )

        panel = CuePanel(contentRect: frame)
        container = CuePanelContentView(frame: frame)

        configureContent()

        panel.contentView = container
        panel.onCancel = { [weak self] in self?.escape() }

        presenter.onDismissed = { [weak self] in
            self?.panel.orderOut(nil)
        }

        configureFocusHandling()
    }

    isolated deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }

    // MARK: - Presentation

    /// Shows the panel on whichever display the pointer is on.
    ///
    /// The pointer rather than the frontmost window, because a shortcut is
    /// pressed by someone who is already looking somewhere, and where they are
    /// looking is where the mouse is. `NSScreen.main` is the screen with the
    /// key window, which on a two-monitor desk is regularly the wrong one.
    func present() {
        guard presenter.state != .visible else {
            // Already up. Treat a second press as "I meant it" and put the
            // caret back in the field rather than doing nothing.
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let screen = Self.screenUnderPointer()
        let visible = screen.visibleFrame

        // Applied every time rather than once at build: the size and the anchor
        // are settings, and this is the one moment the window is off screen and
        // free to change shape.
        applyMetrics()

        let origin = CueLayout.origin(
            in: visible,
            panelHeight: CueLayout.panelHeight,
            anchor: settings.panelAnchor
        )

        presentedAt = Date()
        didReassertFocus = false

        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()

        // Keyboard events go to the *active application*, so an overlay that
        // is typed into has to activate — a non-activating panel can be key
        // without the app being active, and then quietly receives nothing.
        // Activation is why `AppDelegate` installs a main menu: it is what
        // makes ⌘A, ⌘C and ⌘V work in the search field.
        //
        // Activated *after* the window is on screen, so that there is
        // something for the system to bring forward. See `shouldReassertFocus`
        // for what happens when it was activated before there was.
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)

        installKeyMonitor()
        presenter.present()
        coordinator.refresh()

        logger.notice("Panel presented on a \(Int(visible.width), privacy: .public)×\(Int(visible.height), privacy: .public) display.")
    }

    func dismiss() {
        guard presenter.state == .visible else { return }
        presentedAt = nil
        removeKeyMonitor()
        presenter.dismiss()
        // Cleared as it goes rather than on the way back in, so the next open
        // is the grid rather than the last search still sitting there.
        coordinator.clearSearch()
    }

    func toggle() {
        presenter.state == .visible ? dismiss() : present()
    }

    /// Whether a loss of focus this soon after presenting should be believed.
    ///
    /// It should not, once, and the reason is worth writing down because it
    /// cost an hour to find. When a shortcut runs `open cue://open`,
    /// LaunchServices activates Cue *before* delivering the URL — at which
    /// point Cue is an accessory app with no windows at all, so macOS decides
    /// there is nothing to activate and hands the foreground back to whatever
    /// was there. That deactivation is already in flight by the time the panel
    /// exists, and it arrives a third of a second later looking exactly like
    /// the user clicking away.
    ///
    /// So the first one inside the settling window is answered by taking focus
    /// again rather than by closing. Only the first: a second means the user
    /// really did click somewhere else, and a panel that fights for focus is
    /// far worse than one that closes early.
    private var shouldReassertFocus: Bool {
        guard !didReassertFocus, presenter.state == .visible, let presentedAt else { return false }
        return Date().timeIntervalSince(presentedAt) < Self.focusSettlingWindow
    }

    /// Resizes the window to whatever the current settings make it.
    ///
    /// The panel's frame is otherwise constant — the contents animate inside a
    /// window that never moves — so this is the one place it changes, and it
    /// happens between presentations rather than during one.
    func applyMetrics() {
        CueLayout.panelWidth = CGFloat(settings.panelWidth)

        let size = NSSize(width: CueLayout.panelWidth, height: CueLayout.panelHeight)
        guard panel.frame.size != size else { return }

        panel.setContentSize(size)
        container.frame = NSRect(origin: .zero, size: size)
        hostingView.frame = container.bounds
        container.contentHeight = size.height
    }

    private static func screenUnderPointer() -> NSScreen {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    // MARK: - Content

    private func configureContent() {
        let view = CueContentView(
            coordinator: coordinator,
            presenter: presenter,
            thumbnails: thumbnails,
            settings: settings,
            player: playback.player,
            onOpen: { [weak self] item in self?.open(item) },
            onShowSettings: { [weak self] in
                self?.dismiss()
                self?.onShowSettings?()
            },
            onOpenPlayer: { [weak self] in
                guard let self else { return }
                // The panel goes away: the player window is the thing being
                // asked for, and leaving a floating panel over it is clutter.
                self.dismiss()
                self.playback.player.showCurrent()
            },
            onHeightChange: { [weak self] height in
                self?.container.contentHeight = height
            }
        )

        hostingView = NSHostingView(rootView: AnyView(
            // Top-aligned inside a window that is always the taller of the two
            // layouts, so that shrinking the contents leaves empty space at the
            // bottom rather than moving the search field.
            VStack(spacing: 0) {
                view
                Spacer(minLength: 0)
            }
        ))
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        hostingView.layer?.backgroundColor = .clear
        container.addSubview(hostingView)
        applyMetrics()
    }

    private func open(_ item: MusicItem) {
        guard playback.open(item) else { return }
        if settings.closesAfterOpening { dismiss() }
    }

    // MARK: - Focus

    /// Clicking anywhere outside the panel closes it.
    ///
    /// The behaviour every overlay of this shape has, and the reason there is
    /// no close button: the way out is to carry on with what you were doing.
    private func configureFocusHandling() {
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard !Diagnostics.holdsPanelOpen else { return }

                if self.shouldReassertFocus {
                    // Not the user clicking away — see `shouldReassertFocus`.
                    self.didReassertFocus = true
                    self.logger.debug("Re-asserting focus after a launch-time deactivation.")
                    NSApp.activate()
                    self.panel.makeKeyAndOrderFront(nil)
                    return
                }

                self.dismiss()
            }
        }
    }

    // MARK: - Keyboard

    /// The panel's keyboard, installed while it is on screen.
    ///
    /// A local monitor rather than the responder chain, because the search
    /// field is first responder the entire time the panel is open and would
    /// otherwise swallow the arrow keys as caret movement and Return as
    /// nothing at all. A monitor sees the event first and can decline to pass
    /// it on, which is exactly the split needed: navigation keys belong to the
    /// panel, every other key belongs to the field.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.presenter.isInteractive else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Returns true when the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if event.keyCode == 123 || event.keyCode == 124 {
            logger.notice(
                "Arrow \(event.keyCode, privacy: .public): mode=\(String(describing: self.presenter.mode), privacy: .public) gallery=\(self.isGallery, privacy: .public) page=\(self.presenter.page.rawValue, privacy: .public) modifiers=\(modifiers.rawValue, privacy: .public)"
            )
        }

        // ⌘1 … ⌘9 open a tile without looking at it. The whole reason the grid
        // has fixed positions.
        if modifiers == .command,
           let characters = event.charactersIgnoringModifiers,
           let digit = Int(characters), (1...9).contains(digit) {
            openTile(at: digit - 1)
            return true
        }

        // ⌘R redeals the page, matching the shuffle control in its header.
        if modifiers == .command,
           event.charactersIgnoringModifiers?.lowercased() == "r",
           isGallery {
            coordinator.reshuffle(presenter.page)
            presenter.select(nil)
            return true
        }

        guard modifiers.isEmpty || modifiers == .shift else { return false }

        switch event.keyCode {
        case 53: // Escape
            escape()
            return true

        case 36, 76: // Return, Enter
            return activateSelection()

        case 125: // Down
            presenter.moveSelection(by: presenter.mode == .grid ? CueLayout.gridColumns : 1)
            return true

        case 126: // Up
            presenter.moveSelection(by: presenter.mode == .grid ? -CueLayout.gridColumns : -1)
            return true

        case 123 where presenter.mode == .grid: // Left
            // In the gallery the arrows move between pages, which is the
            // gesture the design promises with its dots. Selection moves by row
            // on Up and Down and by one on Tab, so nothing is lost.
            isGallery ? presenter.movePage(by: -1) : presenter.moveSelection(by: -1)
            return true

        case 124 where presenter.mode == .grid: // Right
            isGallery ? presenter.movePage(by: 1) : presenter.moveSelection(by: 1)
            return true

        case 48: // Tab
            presenter.moveSelection(by: modifiers == .shift ? -1 : 1)
            return true

        default:
            return false
        }
    }

    /// Escape backs out one step at a time.
    ///
    /// A search in the field is the thing to clear first; only an already-empty
    /// panel closes. Otherwise Escape after a mistyped query throws away the
    /// panel too, and the user has to press the shortcut again to get back to
    /// where they already were.
    private func escape() {
        if !coordinator.query.isEmpty {
            coordinator.clearSearch()
        } else {
            dismiss()
        }
    }

    private func activateSelection() -> Bool {
        switch presenter.mode {
        case .grid:
            guard let index = presenter.selection else { return false }
            openTile(at: index)
            return true


        case .results:
            // Return with nothing highlighted takes the first result, which is
            // what "type and hit Return" has meant in every search field since
            // the browser address bar.
            let index = presenter.selection ?? 0
            guard coordinator.results.indices.contains(index) else { return false }
            open(coordinator.results[index])
            return true
        }
    }

    /// Whether the panel is currently drawing the paged gallery.
    private var isGallery: Bool { settings.panelDesign == .gallery }

    /// The nine things ⌘1–⌘9 currently address.
    ///
    /// The *visible* page, always. Numbers that kept addressing the first page
    /// while a different one was on screen would be the one way to break what
    /// the grid is for.
    private var visibleTiles: [MusicItem?] {
        isGallery ? coordinator.tiles(for: presenter.page) : coordinator.tiles
    }

    private func openTile(at index: Int) {
        let tiles = visibleTiles
        guard tiles.indices.contains(index), let item = tiles[index] else { return }
        open(item)
    }
}

/// The panel's content view, which declines to be clicked where nothing is
/// drawn.
///
/// The window is always as tall as the grid, so a short results list leaves
/// transparent window below it. Without this, that strip would swallow clicks
/// meant for the app underneath — an invisible dead zone, which is the worst
/// kind.
final class CuePanelContentView: NSView {
    /// How much of the window, measured from the top, is actually drawn on.
    var contentHeight: CGFloat = CueLayout.panelHeight

    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` arrives in the superview's coordinates, which for a window's
        // content view is the window's own — origin at the bottom left.
        guard point.y >= bounds.height - contentHeight else { return nil }
        return super.hitTest(point)
    }
}
