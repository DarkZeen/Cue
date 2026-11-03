import AppKit

/// The panel's content view: the tray's entire relationship with the mouse
/// (§13, §74, §75).
///
/// Three regions, kept deliberately distinct:
///
/// * **content region** — the visible tray. Clicks, hover and item drags.
/// * **hover activation region** — the content region plus a little slop, and
///   when closed, a narrow strip. Narrow on purpose: ordinary pointer travel
///   across the top of the screen must not keep springing the shelf open.
/// * **drag activation region** — much wider, and live only while a mouse
///   button is down. Throwing a file at the top of the screen should not
///   demand aim.
///
/// Every point outside the region that currently applies returns `nil` from
/// `hitTest`, so the window is genuinely transparent to the app underneath.
/// The alternative — a permanently live strip across the top of the display —
/// is the "giant invisible mouse trap" §74 forbids.
///
/// `hitTest` is only half of it. The panel is transparent, and the window
/// server sends the mouse — and every drag — to a transparent window only
/// over pixels it has actually painted; everywhere else it goes straight to
/// whatever is underneath, and `hitTest` is never asked. So the region that
/// applies is also *painted*, by `catchmentLayer`, too faintly to see.
/// Without that, the tray's real target was whatever the surface happened to
/// draw: a soft shadow once, and with the island's shadow gone, a 56 × 5
/// handle tucked behind the camera housing — which no dragged file ever found.
final class TrayDropView: NSView {
    /// The visible tray, in this view's coordinates. Set by the controller
    /// whenever the shape changes.
    var contentRect: CGRect = .zero {
        didSet {
            guard contentRect != oldValue else { return }
            needsLayout = true
            window?.invalidateCursorRects(for: self)
            // The region moved under a stationary pointer, so what was inside
            // may now be outside without the mouse having gone anywhere.
            revalidatePointerRegion()
        }
    }

    /// Whether the tray is currently open, which decides how generous the
    /// hover region is allowed to be.
    var isOpen = false {
        didSet {
            guard isOpen != oldValue else { return }
            needsLayout = true
            revalidatePointerRegion()
        }
    }

    /// A drag is under way somewhere on the system, so the wider drag region
    /// is painted and live as well as the hover one. Set by the controller
    /// from `SystemDragMonitor`.
    var isSystemDragActive = false {
        didSet {
            guard isSystemDragActive != oldValue else { return }
            needsLayout = true
        }
    }

    /// How opaque the catchment is: the least the window server will count as
    /// "painted" once rounded to 8 bits, and well below anything visible —
    /// 1% black over a white menu bar moves it by two levels out of 255.
    static let catchmentAlpha: CGFloat = 0.01

    /// The faint fill that makes the live region real to the window server.
    private let catchmentLayer: CALayer = {
        let layer = CALayer()
        layer.backgroundColor = NSColor.black.withAlphaComponent(TrayDropView.catchmentAlpha).cgColor
        // Moves with the regions, never animates between them: a catchment
        // that lags the shape is a target that is somewhere else.
        layer.actions = ["bounds": NSNull(), "position": NSNull(), "frame": NSNull()]
        layer.zPosition = -1
        return layer
    }()

    /// Where the catchment is currently painted, in this view's coordinates.
    var catchmentFrame: CGRect { catchmentLayer.frame }

    /// Keyboard commands. The tray only has a keyboard while it is key, which
    /// only happens when the user clicks into it — hovering and dropping never
    /// take focus (§28).
    var onDelete: () -> Void = {}
    var onCopy: () -> Void = {}
    var onPaste: () -> Void = {}
    var onSelectAll: () -> Void = {}
    var onQuickLook: () -> Void = {}
    var onEscape: () -> Void = {}
    var onStepSelection: (Int) -> Void = { _ in }
    var onClearSelection: () -> Void = {}

    var onPointerEnter: () -> Void = {}
    var onPointerExit: () -> Void = {}
    var onDragEnter: () -> Void = {}
    var onDragExit: () -> Void = {}
    var onDragSessionEnded: () -> Void = {}
    var onDragApproach: () -> Void = {}
    var dragAcceptance: (any NSDraggingInfo) -> FileDropHandler.Acceptance = { _ in .unsupported }
    var performDrop: (any NSDraggingInfo) -> Bool = { _ in false }

    private var trackingArea: NSTrackingArea?

    /// Whether the pointer is currently within the region that counts as "on
    /// the tray". Tracked here rather than inferred from AppKit's enter and
    /// exit events, for the reason spelled out on `updateTrackingAreas`.
    private var pointerIsInsideRegion = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
        layer?.addSublayer(catchmentLayer)
        needsLayout = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Regions

    /// Where the pointer counts as "on the tray".
    ///
    /// When open this is the shelf plus a few points of slop, so the tray does
    /// not collapse out from under a pointer that drifted a pixel past the
    /// edge. When closed it is a narrow strip at the top centre (§75).
    ///
    /// Open, it also keeps the closed strip. `isOpen` flips a beat before the
    /// new shape is reported, and in that beat `contentRect` is still the
    /// handle: without the strip, a pointer resting where it opened the tray
    /// counted as having left, the tray closed, the strip came back and it
    /// opened again — ten times a second. Once the shelf is out it covers the
    /// strip anyway, so this costs nothing at rest.
    var hoverActivationRect: CGRect {
        guard isOpen else { return closedActivationRect }
        return contentRect
            .insetBy(dx: -TrayMetrics.hoverSlop, dy: -TrayMetrics.hoverSlop)
            .union(closedActivationRect)
    }

    /// The narrow strip at the top centre that a resting pointer opens the
    /// tray from — or the closed shape, if that is bigger.
    private var closedActivationRect: CGRect {
        let width = max(TrayMetrics.hoverActivationWidth, contentRect.width)
        let height = max(TrayMetrics.hoverActivationHeight, contentRect.height)
        return CGRect(
            x: bounds.midX - width / 2,
            y: bounds.maxY - height,
            width: width,
            height: height
        )
    }

    /// The wider catchment for an incoming drag (§75). Live only while a
    /// button is held, so it costs ordinary mouse use nothing.
    var dragActivationRect: CGRect {
        let width = max(TrayMetrics.dragActivationWidth, contentRect.width + 40)
        let height = max(TrayMetrics.dragActivationHeight, contentRect.height)
        return CGRect(
            x: bounds.midX - width / 2,
            y: bounds.maxY - height,
            width: width,
            height: height
        )
    }

    /// The region that currently counts: the hover region, widened to the
    /// drag region while a drag might be heading this way.
    private func liveRegion(widened: Bool) -> CGRect {
        widened ? dragActivationRect.union(hoverActivationRect) : hoverActivationRect
    }

    /// The button is held right now.
    ///
    /// A single cheap query at hit-test time, not a monitor and not a poll
    /// (§26). Every file drag has the button down, which is exactly the
    /// condition that should widen the target.
    private var pointerButtonIsDown: Bool {
        NSEvent.pressedMouseButtons & 0x1 != 0
    }

    override func layout() {
        super.layout()
        catchmentLayer.frame = liveRegion(widened: isSystemDragActive)
    }

    // MARK: - Keyboard (§35, §36)

    override var acceptsFirstResponder: Bool { true }

    /// A click anywhere on the tray that is not on an item clears the
    /// selection, the way clicking the background of any list does.
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        onClearSelection()
    }

    override func keyDown(with event: NSEvent) {
        guard let characters = event.charactersIgnoringModifiers, !characters.isEmpty else {
            super.keyDown(with: event)
            return
        }

        switch characters.unicodeScalars.first! {
        case Unicode.Scalar(NSDeleteCharacter)!,        // ⌫
             Unicode.Scalar(NSDeleteFunctionKey)!:      // ⌦
            onDelete()

        case Unicode.Scalar(NSLeftArrowFunctionKey)!:
            onStepSelection(-1)

        case Unicode.Scalar(NSRightArrowFunctionKey)!:
            onStepSelection(1)

        case " ":
            // Select an item, press Space — the same gesture as Finder (§24).
            onQuickLook()

        case Unicode.Scalar(27):                        // Escape
            onEscape()

        default:
            super.keyDown(with: event)
        }
    }

    /// ⌘C, ⌘V and ⌘A.
    ///
    /// Handled as key *equivalents* rather than in `keyDown`, because there is
    /// no menu bar menu carrying these commands — a borderless panel has no
    /// Edit menu to route them through.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let characters = event.charactersIgnoringModifiers
        else { return super.performKeyEquivalent(with: event) }

        switch characters.lowercased() {
        case "c": onCopy(); return true
        case "v": onPaste(); return true
        case "a": onSelectAll(); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }

    // MARK: - Hit testing

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let region = liveRegion(widened: isSystemDragActive || pointerButtonIsDown)

        guard region.contains(local) else { return nil }
        return super.hitTest(point) ?? self
    }

    // MARK: - Hover tracking

    /// One tracking area covering the whole panel, which is never rebuilt.
    ///
    /// It used to be sized to the hover region and rebuilt every time the tray
    /// changed shape. That is what made the shelf occasionally stick open: a
    /// rebuild makes AppKit re-evaluate containment and emit enter/exit events
    /// that do not correspond to any pointer movement, and once an *enter* was
    /// missed that way, the matching exit never arrived either — so nothing
    /// ever told the tray the pointer had gone.
    ///
    /// Now the area is constant and `.inVisibleRect`, so AppKit's bookkeeping
    /// cannot drift, and whether the pointer is on the tray is decided here
    /// from its actual position.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        updatePointerRegion(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updatePointerRegion(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        // Left the panel altogether, so it is outside every region in it.
        setPointerInside(false)
    }

    private func updatePointerRegion(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        setPointerInside(hoverActivationRect.contains(local))
    }

    /// Re-checks where the pointer is without waiting for it to move.
    ///
    /// A single query of the current location, not a poll: it runs when the
    /// tray changes shape, which is exactly when a stationary pointer can find
    /// itself on the other side of the boundary.
    private func revalidatePointerRegion() {
        guard let window else { return }
        let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let local = convert(inWindow, from: nil)
        setPointerInside(bounds.contains(local) && hoverActivationRect.contains(local))
    }

    private func setPointerInside(_ inside: Bool) {
        guard inside != pointerIsInsideRegion else { return }
        pointerIsInsideRegion = inside
        inside ? onPointerEnter() : onPointerExit()
    }

    // MARK: - Drag destination (§13, §14, §38)

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        respond(to: sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        respond(to: sender)
    }

    /// Answers macOS's question "what will you do with this?" honestly.
    ///
    /// A full shelf opens but advertises nothing, so the pointer shows the
    /// refusal and the file flies back — macOS's own vocabulary for a drop that
    /// will not work. Claiming `.copy` and then quietly discarding the file is
    /// the one answer that is worse than saying no.
    private func respond(to sender: any NSDraggingInfo) -> NSDragOperation {
        switch dragAcceptance(sender) {
        case .accept:
            updateDragPhase(for: sender)
            return FileDropHandler.advertisedOperation

        case .full:
            // Still open: being shown a shelf with everything already on it
            // explains the refusal better than a message would.
            onDragApproach()
            return []

        case .unsupported:
            return []
        }
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onDragExit()
    }

    /// The other way a drag can stop mattering to us.
    ///
    /// `draggingExited` is not guaranteed for every way a session can end — a
    /// drag cancelled with Escape, or one that finishes elsewhere, may not
    /// produce one. Without this the tray was left believing a drag was still
    /// approaching, and a tray that thinks a drag is overhead refuses to close.
    override func draggingEnded(_ sender: any NSDraggingInfo) {
        onDragSessionEnded()
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        dragAcceptance(sender) == .accept
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        performDrop(sender)
    }

    /// Distinguishes "a drag is nearby and the tray should lean toward it"
    /// from "a drag is over the target and releasing would stash" (§13).
    private func updateDragPhase(for sender: any NSDraggingInfo) {
        let local = convert(sender.draggingLocation, from: nil)
        if contentRect.insetBy(dx: -TrayMetrics.hoverSlop, dy: -TrayMetrics.hoverSlop).contains(local) {
            onDragEnter()
        } else {
            onDragApproach()
        }
    }
}
