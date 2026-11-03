import AppKit
import SwiftUI

/// One display's tray: the panel, the mouse layer, and the SwiftUI content,
/// wired together (§11, §27).
///
/// The panel's frame never changes. It is created large enough to hold the
/// shelf at its widest and stays that way; the tray animates *inside* it. That
/// keeps window-server geometry out of the animation loop entirely, which is
/// what §16 is really asking for, and it means the hit regions the user is
/// aiming at never move out from under them mid-gesture (§74).
@MainActor
final class TrayWindowController {
    let geometry: ScreenGeometry
    let presenter = TrayPresenter()
    let selection = TraySelection()

    private let store: TrayStore
    private let thumbnails: FileThumbnailProvider
    private let settings: ShelfSettingsStore
    private let dropHandler: FileDropHandler

    private let panel: TrayPanel
    private let dropView: TrayDropView
    private var hostingView: TrayHostingView<AnyView>!

    private var focusObserver: (any NSObjectProtocol)?

    /// Widens the painted drop catchment while a drag is under way (§75).
    private let systemDrags = SystemDragMonitor()

    private let logger = Diagnostics.logger("tray-window")

    /// Raised so the app can put a preview on screen without the tray needing
    /// to know what Quick Look is.
    var onQuickLookRequest: ((TrayItem) -> Void)?

    /// Raised by the header menu, for the same reason: the tray does not know
    /// there is a settings window.
    var onOpenSettingsRequest: (() -> Void)?

    init(
        geometry: ScreenGeometry,
        store: TrayStore,
        thumbnails: FileThumbnailProvider,
        settings: ShelfSettingsStore
    ) {
        self.geometry = geometry
        self.store = store
        self.thumbnails = thumbnails
        self.settings = settings
        self.dropHandler = FileDropHandler(store: store)

        let frame = Self.panelFrame(for: geometry)
        self.panel = TrayPanel(contentRect: frame)
        self.dropView = TrayDropView(frame: NSRect(origin: .zero, size: frame.size))

        presenter.collapseDelay = { [settings] in settings.autoCollapseDelay }
        presenter.holdsOpenWhenClicked = { [settings] in settings.staysOpenAfterClick }
        presenter.expandsAfterDrop = { [settings] in settings.expandsAfterDrop }

        configureContent()
        configureMouseHandling()
        configureFocusHandling()

        // Notch geometry is nearly impossible to reason about and trivial to
        // check, so the numbers this display actually produced go in the log
        // (§8, §71).
        logger.notice(
            """
            Tray on display \(geometry.id, privacy: .public): \
            screen \(geometry.frame.debugDescription, privacy: .public), \
            notch \(geometry.notchSize?.debugDescription ?? "none", privacy: .public), \
            safeArea.top \(geometry.topInset, privacy: .public), \
            menuBar \(geometry.menuBarHeight, privacy: .public), \
            panel \(frame.debugDescription, privacy: .public)
            """
        )

        panel.contentView = dropView
        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()
    }

    // MARK: - Geometry

    /// The window is the largest the tray can ever be, plus room for its
    /// shadow, anchored to the top edge of this display (§9, §87).
    private static func panelFrame(for geometry: ScreenGeometry) -> NSRect {
        // Sized for the widest the shelf is ever allowed to be, plus room for
        // its shadow. The window never resizes — the shelf animates inside it —
        // so it has to be big enough for the largest setting, not for the
        // current one.
        let cutout = TrayMetrics.cutout(
            notchSize: geometry.notchSize,
            menuBarHeight: geometry.menuBarHeight,
            screenWidth: geometry.frame.width
        )

        let widest = TrayShape.expandedWidth(
            screenWidth: geometry.frame.width,
            cutoutWidth: cutout.width,
            size: .custom,
            customWidth: TraySize.widthRange(
                screenWidth: geometry.frame.width,
                cutoutWidth: cutout.width
            ).upperBound
        )
        let width = min(
            geometry.frame.width,
            widest + TrayMetrics.panelPadding * 2
        )

        // A custom height has no bracket any more, so the tallest the shelf can
        // be is the display — and the window has to be able to hold it. Being
        // large costs nothing: the panel is transparent, hit-tests to nothing
        // outside the shelf, and never resizes while the shelf animates in it.
        //
        // The debug overlay hangs below the tray and would otherwise be clipped
        // by the window it lives in — a diagnostic you cannot read is not one.
        let height = min(
            geometry.usableHeight,
            TrayItemMetrics.maximumExpandedHeight(screenHeight: geometry.usableHeight)
                + cutout.height
                + TrayMetrics.spacing
                + TrayMetrics.panelPadding
                + (Diagnostics.isDebugOverlayEnabled ? 140 : 0)
        )

        return NSRect(
            x: geometry.anchorCenterX - width / 2,
            y: geometry.topEdgeY - height,
            width: width,
            height: height
        )
    }

    /// Re-reads this display's geometry after the arrangement changed (§11).
    func reposition(to geometry: ScreenGeometry) {
        let frame = Self.panelFrame(for: geometry)
        panel.setFrame(frame, display: true)
        dropView.frame = NSRect(origin: .zero, size: frame.size)
        hostingView.frame = dropView.bounds
        dropView.needsLayout = true
    }

    func close() {
        systemDrags.stop()
        panel.orderOut(nil)
    }

    isolated deinit {
        if let focusObserver {
            NotificationCenter.default.removeObserver(focusObserver)
        }
    }

    // MARK: - Content

    private func configureContent() {
        let view = TrayContentView(
            store: store,
            presenter: presenter,
            selection: selection,
            thumbnails: thumbnails,
            settings: settings,
            geometry: geometry,
            onRemove: { [weak self] item in self?.remove([item]) },
            onCopy: { [weak self] items in self?.copy(items) },
            onClick: { [weak self] item, modifiers in self?.click(item, modifiers) },
            onReveal: { item in
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            },
            onQuickLook: { [weak self] item in
                self?.onQuickLookRequest?(item)
            },
            onItemDragBegan: { [weak self] items in
                self?.presenter.beganDraggingItems(ids: Set(items.map(\.id)))
            },
            onItemDragEnded: { [weak self] items, didLand in
                self?.finishItemDrag(items, didLand: didLand)
            },
            onClearAll: { [weak self] in self?.clearAll() },
            onOpenSettings: { [weak self] in self?.onOpenSettingsRequest?() },
            onShapeChange: { [weak self] shape in
                self?.updateHitRegions(for: shape)
            }
        )

        let root = AnyView(
            ZStack(alignment: .top) {
                view
                if Diagnostics.isDebugOverlayEnabled {
                    TrayDebugOverlay(presenter: presenter, store: store, geometry: geometry)
                }
            }
        )

        hostingView = TrayHostingView(rootView: root)
        hostingView.frame = dropView.bounds
        hostingView.autoresizingMask = [.width, .height]
        // The window is mostly empty space; only the tray should ever paint.
        hostingView.layer?.backgroundColor = .clear
        dropView.addSubview(hostingView)
    }

    /// Keeps the interactive regions exactly on the visible pixels (§74).
    private func updateHitRegions(for shape: TrayShape) {
        let rect = CGRect(
            x: dropView.bounds.midX - shape.width / 2,
            y: dropView.bounds.maxY - shape.height,
            width: shape.width,
            height: shape.height
        )
        dropView.contentRect = rect
        dropView.isOpen = presenter.state.isOpen
    }

    // MARK: - Mouse and drags

    private func configureMouseHandling() {
        dropView.onPointerEnter = { [weak self] in
            guard let self, self.settings.activation.allowsHover else { return }
            self.presenter.pointerEntered()
        }

        dropView.onPointerExit = { [weak self] in
            self?.presenter.pointerExited()
        }

        dropView.dragAcceptance = { [weak self] info in
            guard let self, self.settings.activation.allowsDrag else { return .unsupported }
            return self.dropHandler.acceptance(of: info)
        }

        dropView.onDragApproach = { [weak self] in
            self?.presenter.dragApproached()
        }

        dropView.onDragEnter = { [weak self] in
            self?.presenter.dragEntered()
        }

        dropView.onDragExit = { [weak self] in
            self?.presenter.dragExited()
        }

        dropView.onDragSessionEnded = { [weak self] in
            self?.systemDrags.update(false)
            self?.presenter.dragSessionEnded()
        }

        systemDrags.onChange = { [weak self] dragging in
            self?.dropView.isSystemDragActive = dragging
        }
        systemDrags.start()

        dropView.performDrop = { [weak self] info in
            guard let self else { return false }
            return self.accept(info)
        }

        presenter.onStateChange = { [weak self] state in
            guard let self else { return }
            self.dropView.isOpen = state.isOpen
            // A closed tray has nothing to have selected, and leaving a stale
            // selection behind means the next Delete acts on something the user
            // picked minutes ago.
            if !state.isOpen { self.clearSelection() }
        }

        configureKeyboard()
    }

    // MARK: - Focus

    /// Clicking away from the tray ends whatever was going on in it.
    ///
    /// Without this, a tray the user clicked into stays open forever: the
    /// interaction gate is holding it, and the pointer leaving no longer
    /// closes it.
    private func configureFocusHandling() {
        focusObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.selection.clear()
                self.presenter.endedInteracting()
            }
        }
    }

    // MARK: - Keyboard

    private func configureKeyboard() {
        dropView.onDelete = { [weak self] in
            guard let self else { return }
            self.remove(self.selection.items(from: self.store.items))
        }

        dropView.onCopy = { [weak self] in
            guard let self else { return }
            self.copy(self.selection.items(from: self.store.items))
        }

        dropView.onPaste = { [weak self] in self?.paste() }

        dropView.onSelectAll = { [weak self] in
            guard let self else { return }
            self.selection.selectAll(self.store.items.map(\.id))
        }

        dropView.onQuickLook = { [weak self] in
            guard let self,
                  let item = self.selection.items(from: self.store.items).first
            else { return }
            self.onQuickLookRequest?(item)
        }

        dropView.onEscape = { [weak self] in
            self?.clearSelection()
            self?.presenter.collapseNow()
        }

        dropView.onStepSelection = { [weak self] offset in
            guard let self else { return }
            self.selection.step(by: offset, within: self.store.items.map(\.id))
        }

        dropView.onClearSelection = { [weak self] in self?.clearSelection() }
    }

    private func click(_ item: TrayItem, _ modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            selection.toggle(item.id)
        } else {
            selection.select(item.id)
        }
        presenter.beganInteracting()
    }

    private func clearSelection() {
        selection.clear()
        presenter.endedInteracting()
    }

    /// ⌘C. Writes file URLs, which is what Finder writes — so pasting lands
    /// the file itself, and the original never moves (§3).
    private func copy(_ items: [TrayItem]) {
        guard !items.isEmpty else { return }
        let wrote = TrayPasteboard.copy(items)
        logger.debug("Copied \(items.count, privacy: .public) item(s): \(wrote, privacy: .public)")
    }

    /// ⌘V. The mirror of a drop, and it obeys the same rule: what lands on the
    /// shelf is a reference, not a copy of the bytes.
    private func paste() {
        let urls = TrayPasteboard.pasteableURLs()
        guard !urls.isEmpty else { return }

        store.refreshAvailability()
        if case .added(let ids) = store.add(urls) {
            // Select what just arrived, so a paste is visible rather than
            // merely successful.
            selection.selectAll(ids)
            presenter.beganInteracting()
        }
        presenter.dropCompleted()
    }

    /// A drop stores references. It never copies, moves or modifies the
    /// original files (§3, §38).
    private func accept(_ info: any NSDraggingInfo) -> Bool {
        store.refreshAvailability()
        let outcome = dropHandler.accept(info)
        presenter.dropCompleted()

        switch outcome {
        case .added(let ids):
            logger.debug("Drop accepted: \(ids.count, privacy: .public) new item(s).")
            return true

        case .allDuplicates:
            // Still a successful drop as far as the source is concerned — the
            // file the user aimed at is on the shelf, it was already there.
            return true

        case .rejectedAtCapacity:
            // Reported as a failure so the file flies back. Returning true here
            // would animate a successful drop and then discard the file, which
            // is the one outcome worse than refusing it.
            logger.notice("Drop refused: the shelf is full.")
            return false

        case .nothingUsable:
            return false
        }
    }

    private func finishItemDrag(_ items: [TrayItem], didLand: Bool) {
        presenter.endedDraggingItems()

        // Landed somewhere: they have done their job and leave the shelf (§22).
        // Cancelled: they spring back, which is the absence of any change here
        // plus the scale animation unwinding.
        if didLand {
            remove(items)
        }
    }

    /// Everything off the shelf at once, from the header menu.
    ///
    /// The one bulk command the tray has. It goes through `remove` rather than
    /// emptying the store directly, so the thumbnail cache and the selection
    /// are cleaned up the same way a one-file removal cleans them up.
    private func clearAll() {
        remove(store.items)
    }

    private func remove(_ items: [TrayItem]) {
        guard !items.isEmpty else { return }
        for item in items {
            store.remove(id: item.id)
            thumbnails.forget(item)
        }
        selection.prune(to: store.items.map(\.id))
        if selection.isEmpty { presenter.endedInteracting() }
    }

    // MARK: - Commands

    /// Opens the shelf to show a setting the user is changing.
    ///
    /// Deliberately not `open()`: that re-checks every file on disk, which is
    /// the right thing to do when someone asks to see the shelf and the wrong
    /// thing to do sixty times a second while they drag a slider.
    func showPreview() {
        presenter.open()
    }

    func open() {
        store.refreshAvailability()
        presenter.open()
    }

    func collapse() {
        presenter.collapseNow()
    }

    func toggle() {
        if !presenter.state.isOpen { store.refreshAvailability() }
        presenter.toggle()
    }
}

/// The SwiftUI host, with one thing changed.
///
/// Tray's panel is non-activating and the user's own app stays frontmost, so
/// *every* click on the shelf is a click into an inactive window — the one
/// AppKit swallows by default to stop a stray click firing a control. The
/// items already opt in through `FileDragSource`; the header's buttons live in
/// SwiftUI, and without this the chevron and the menu would need a click to
/// wake the panel and a second one to do anything.
private final class TrayHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
