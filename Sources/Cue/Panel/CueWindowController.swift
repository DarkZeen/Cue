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
    /// Raised when Escape ends an edit, so the session's owner can tear the
    /// guides down too.
    var onEndEditing: (() -> Void)?

    /// True while the layout is being arranged. The panel stays put, ignores
    /// focus loss, and shows its resize edge.
    private(set) var isEditing = false

    /// Where the pointer and the window were when the current drag began.
    ///
    /// The pointer's position is taken from the screen rather than from
    /// SwiftUI's translation, and that is the whole point: the translation a
    /// gesture reports is measured relative to its own window, so moving the
    /// window during the drag feeds straight back into the next measurement.
    /// The panel shook itself across the screen. Global coordinates do not move
    /// when the window does.
    private var dragAnchor: (mouse: NSPoint, frame: NSRect)?

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
            size: panel.frame.size,
            position: settings.panelPosition
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

    // MARK: - Editing the layout

    /// Puts the panel into the arranging state and leaves it on screen.
    func beginEditing() {
        isEditing = true
        if presenter.state != .visible { present() }
        // The root view captures `isEditing` when it is built, so the chrome
        // only appears once the content is rebuilt around the new value.
        configureContent()
        panel.orderFrontRegardless()
    }

    func endEditing() {
        guard isEditing else { return }
        isEditing = false
        dragAnchor = nil
        configureContent()
    }

    /// The pointer's movement since the drag began, in screen coordinates.
    private func dragDelta() -> (delta: NSPoint, frame: NSRect) {
        let mouse = NSEvent.mouseLocation
        let anchor = dragAnchor ?? (mouse, panel.frame)
        if dragAnchor == nil { dragAnchor = anchor }

        return (
            NSPoint(x: mouse.x - anchor.mouse.x, y: mouse.y - anchor.mouse.y),
            anchor.frame
        )
    }

    /// Moves the window by a drag, pulling onto a guide when close.
    func dragPanel(isEnd: Bool) {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame

        let (delta, start) = dragDelta()
        let proposed = NSPoint(x: start.minX + delta.x, y: start.minY + delta.y)

        let free = NSSize(
            width: max(visible.width - start.width, 0),
            height: max(visible.height - start.height, 0)
        )

        let snapped = NSPoint(
            x: visible.minX + LayoutGuides.snap(offset: proposed.x - visible.minX, free: free.width),
            y: visible.minY + LayoutGuides.snap(offset: proposed.y - visible.minY, free: free.height)
        )

        panel.setFrameOrigin(snapped)

        if isEnd {
            settings.panelPosition = CueLayout.position(of: snapped, size: start.size, in: visible)
            dragAnchor = nil
        }
    }

    /// Resizes by dragging the panel's edge.
    func resizePanel(edge: Int, stepped: Bool, isEnd: Bool) {
        let (delta, start) = dragDelta()

        // Dragging the left edge grows the panel leftwards, so the pointer's
        // movement counts the other way and the far edge is what stays put.
        var width = start.width + delta.x * CGFloat(edge)
        if stepped { width = LayoutGuides.step(width) }
        width = min(max(width, CueLayout.panelWidthRange.lowerBound), CueLayout.panelWidthRange.upperBound)

        // Written through the setting rather than straight onto the window, so
        // the contents resize with it — a size the views cannot see is exactly
        // what made the slider do nothing.
        settings.panelWidth = Double(width)
        applyMetrics()

        // The edge being dragged is the one that moves; the opposite one stays
        // where it is. Repositioning from the saved fraction instead would pull
        // the panel out from under the pointer on every frame, which was the
        // other half of the shake.
        let origin = edge < 0
            ? NSPoint(x: start.maxX - panel.frame.width, y: start.minY)
            : start.origin
        panel.setFrameOrigin(origin)

        if isEnd {
            dragAnchor = nil
            if let screen = panel.screen ?? NSScreen.main {
                settings.panelPosition = CueLayout.position(
                    of: panel.frame.origin,
                    size: panel.frame.size,
                    in: screen.visibleFrame
                )
            }
        }
    }

    /// Puts the panel back where its saved position says, at its current size.
    func reposition() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        panel.setFrameOrigin(CueLayout.origin(
            in: screen.visibleFrame,
            size: panel.frame.size,
            position: settings.panelPosition
        ))
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
        let width = CGFloat(settings.panelWidth)
        CueLayout.panelWidth = width

        let size = NSSize(width: width, height: CueLayout.panelHeight(for: width))
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
            },
            isEditing: isEditing,
            onDragMove: { [weak self] isEnd in self?.dragPanel(isEnd: isEnd) },
            onDragResize: { [weak self] edge, stepped, isEnd in
                self?.resizePanel(edge: edge, stepped: stepped, isEnd: isEnd)
            }
        )

        hostingView?.removeFromSuperview()
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
                guard !Diagnostics.holdsPanelOpen, !self.isEditing else { return }

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

        // Left and Right are deliberately absent. This monitor never received
        // them — the panel's arrows did nothing until SwiftUI's focus system
        // was given them in `CueContentView` — and leaving a second handler
        // here would mean two mechanisms racing to move one page.

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
        if isEditing {
            onEndEditing?()
            return
        }
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
