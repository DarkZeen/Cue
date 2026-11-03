import AppKit
import SwiftUI

/// The AppKit interaction layer for a single tray item (§21, §27, §81).
///
/// Dragging out has to be a *real* `NSDraggingSession`, not a simulated one —
/// that is the difference between a file that lands in Finder, an upload
/// field or a Save dialog, and an animation that looks like it did. It also
/// has to report its outcome, which is why this is AppKit rather than
/// SwiftUI's `.onDrag`: the tray removes an item on a successful drop and
/// springs it back on a cancel (§22), and only a drag *source* is told which
/// happened.
///
/// Since this view is already sitting over the item to catch the drag, it owns
/// the rest of the item's mouse behaviour too — hover, secondary click, and
/// double click — rather than fighting SwiftUI over the same events.
final class ItemInteractionView: NSView {
    var item: TrayItem
    var onHoverChanged: (Bool) -> Void = { _ in }
    /// Everything this drag should carry. Resolved at the moment the drag
    /// starts and held for its duration, because the selection can change
    /// underneath a drag that is already in flight.
    var dragPayload: () -> [TrayItem] = { [] }
    var dragImage: (TrayItem) -> NSImage? = { _ in nil }
    var onDragBegan: ([TrayItem]) -> Void = { _ in }
    var onDragEnded: ([TrayItem], Bool) -> Void = { _, _ in }
    var onOpenQuickLook: () -> Void = {}
    /// A plain click. The modifier flags come along so ⌘-click can extend the
    /// selection rather than replace it.
    var onClick: (NSEvent.ModifierFlags) -> Void = { _ in }
    var menuBuilder: () -> NSMenu? = { nil }

    private var trackingArea: NSTrackingArea?
    private var itemsInFlight: [TrayItem] = []
    private var mouseDownEvent: NSEvent?

    /// How far the pointer must travel with the button down before this counts
    /// as a drag rather than a click (§10 of the fluid-interface rules: a small
    /// hysteresis, then 1:1 tracking).
    private static let dragThreshold: CGFloat = 3

    init(item: TrayItem) {
        self.item = item
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged(false) }

    // MARK: - Drag out

    /// Lets the first click on an inactive tray both focus nothing and still
    /// start a drag, so the user never has to click twice (§28: the app is
    /// never activated, so every click here is a "first" one).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event

        // Hand the keyboard to the tray, so Delete and ⌘C have a subject.
        // Nothing else in the app does this: hovering and dropping leave focus
        // exactly where it was (§28).
        if let dropView = enclosingDropView {
            window?.makeFirstResponder(dropView)
        }
    }

    /// The ancestor that owns the tray's keyboard handling. This view lives
    /// inside a hosting view inside it, so the chain has to be walked.
    private var enclosingDropView: TrayDropView? {
        var candidate: NSView? = superview
        while let view = candidate {
            if let dropView = view as? TrayDropView { return dropView }
            candidate = view.superview
        }
        return nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownEvent else { return }
        let travelled = hypot(
            event.locationInWindow.x - start.locationInWindow.x,
            event.locationInWindow.y - start.locationInWindow.y
        )
        guard travelled >= Self.dragThreshold else { return }
        mouseDownEvent = nil
        beginDrag(with: start)
    }

    override func mouseUp(with event: NSEvent) {
        // A drag clears `mouseDownEvent` when it starts, so a nil here means
        // the press already turned into a drag and this is not a click.
        let isClick = mouseDownEvent != nil
        mouseDownEvent = nil
        guard isClick else { return }

        if event.clickCount == 2 {
            onOpenQuickLook()
        } else {
            onClick(event.modifierFlags.intersection(.deviceIndependentFlagsMask))
        }
    }

    private func beginDrag(with event: NSEvent) {
        let payload = dragPayload().filter(\.isAvailable)
        guard !payload.isEmpty else { return }

        // `NSURL` is the pasteboard writer every file destination on macOS
        // understands. The tray writes a reference to each original file; it
        // never has a copy to offer (§3, §38).
        let draggingItems = payload.enumerated().map { index, item -> NSDraggingItem in
            let draggingItem = NSDraggingItem(pasteboardWriter: item.url as NSURL)

            guard let image = dragImage(item) else {
                draggingItem.setDraggingFrame(bounds, contents: nil)
                return draggingItem
            }

            // Cascaded rather than stacked exactly: several files under the
            // pointer should read as several, and identical frames would hide
            // all but the last.
            let offset = CGFloat(index) * 5
            let size = image.size
            draggingItem.setDraggingFrame(
                NSRect(
                    x: bounds.midX - size.width / 2 + offset,
                    y: bounds.midY - size.height / 2 - offset,
                    width: size.width,
                    height: size.height
                ),
                contents: image
            )
            return draggingItem
        }

        itemsInFlight = payload
        onDragBegan(payload)
        beginDraggingSession(with: draggingItems, event: event, source: self)
    }

    // MARK: - Context menu (§23)

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menuBuilder() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? { menuBuilder() }
}

extension ItemInteractionView: NSDraggingSource {
    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        switch context {
        case .outsideApplication:
            // Copy only. A `.move` would let a destination relocate the user's
            // original file, and the tray promised not to touch it (§3).
            .copy
        case .withinApplication:
            // Reordering inside the shelf is handled by the tray itself, not
            // by a pasteboard round trip.
            []
        @unknown default:
            .copy
        }
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        let carried = itemsInFlight
        itemsInFlight = []
        onDragEnded(carried, operation != [])
    }
}

/// Hosts `ItemInteractionView` over a SwiftUI item.
struct ItemInteractionLayer: NSViewRepresentable {
    let item: TrayItem
    let onHoverChanged: (Bool) -> Void
    let dragPayload: () -> [TrayItem]
    let onDragBegan: ([TrayItem]) -> Void
    let onDragEnded: ([TrayItem], Bool) -> Void
    let onOpenQuickLook: () -> Void
    let onClick: (NSEvent.ModifierFlags) -> Void
    let menuBuilder: () -> NSMenu?
    let dragImage: (TrayItem) -> NSImage?

    func makeNSView(context: Context) -> ItemInteractionView {
        let view = ItemInteractionView(item: item)
        apply(to: view)
        return view
    }

    func updateNSView(_ view: ItemInteractionView, context: Context) {
        view.item = item
        apply(to: view)
    }

    private func apply(to view: ItemInteractionView) {
        view.onHoverChanged = onHoverChanged
        view.dragPayload = dragPayload
        view.onDragBegan = onDragBegan
        view.onDragEnded = onDragEnded
        view.onOpenQuickLook = onOpenQuickLook
        view.onClick = onClick
        view.menuBuilder = menuBuilder
        view.dragImage = dragImage
    }
}
