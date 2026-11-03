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
/// * **control regions** — while closed, the now-playing wings either side of
///   the housing. Live, so they can be clicked, but never hover: pointing at
///   the mark to pause it must not open the shelf around it.
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
            if !isMovingRegions { revalidatePointerRegion() }
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

    /// Things on the closed shelf that are clicked rather than hovered — the
    /// now-playing wings — in this view's coordinates. Set by the controller
    /// from the shape; empty while open, and whenever there are no wings.
    var controlRects: [CGRect] = [] {
        didSet {
            guard controlRects != oldValue else { return }
            needsLayout = true
            // Wings growing under a resting pointer move the boundary without
            // the pointer moving — and must not count as it arriving.
            if !isMovingRegions { revalidatePointerRegion() }
        }
    }

    /// Set while `setRegions` moves the shape and its controls together.
    private var isMovingRegions = false

    /// Moves the shape and its controls in one step, checking a resting
    /// pointer once against the finished pair.
    ///
    /// Separately, there is always a moment with one new and one old. Wings
    /// arriving after a shape already pill-wide leave a strip that spans the
    /// whole pill; wings leaving before the shape narrows do the same — and a
    /// pointer resting on a wing in that moment counts as having entered, and
    /// the shelf opens under it.
    func setRegions(content: CGRect, controls: [CGRect]) {
        isMovingRegions = true
        contentRect = content
        controlRects = controls
        isMovingRegions = false
        revalidatePointerRegion()
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

    /// One faint fill per control, beside the main catchment rather than
    /// merged into it. A single rectangle around strip and wings together
    /// would paint — and claim clicks in — whatever its corners take in
    /// besides: on a 24pt bar, a band under each wing over the app below,
    /// which is the trap §74 forbids.
    private var controlCatchments: [CALayer] = []

    /// Where the controls' catchments are painted, in this view's coordinates.
    var controlCatchmentFrames: [CGRect] { controlCatchments.map(\.frame) }

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
    ///
    /// The shape less its wings: the strip is the housing's, and the wings
    /// either side of it are for clicking.
    private var closedActivationRect: CGRect {
        // What lies between the controls, when there are any: measured from
        // them rather than by subtracting their widths, which stop short of
        // the shape's ends where the menu bar shows through.
        let housing = controlRects.count == 2
            ? controlRects.map(\.minX).max()! - controlRects.map(\.maxX).min()!
            : contentRect.width
        let width = max(TrayMetrics.hoverActivationWidth, housing)
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

    /// Whether a point counts as the pointer being "on the tray" — inside the
    /// hover region, and not on a control.
    ///
    /// The controls are carved out only while closed. Open, the shelf covers
    /// where the wings were and all of it is hover; and `isOpen` flips a beat
    /// before the controller clears them, which must not leave a hole in the
    /// region the pointer just opened the shelf from.
    func countsAsHover(_ point: CGPoint) -> Bool {
        guard hoverActivationRect.contains(point) else { return false }
        guard !isOpen else { return true }
        return !controlRects.contains { $0.contains(point) }
    }

    /// The main region that currently counts: the hover region, widened to
    /// the drag region while a drag might be heading this way. The controls
    /// count beside it, each exactly its own rectangle.
    private func liveRegion(widened: Bool) -> CGRect {
        widened ? dragActivationRect.union(hoverActivationRect) : hoverActivationRect
    }

    /// Whether a point is anywhere that answers: the live region or a control.
    /// What is painted has to be exactly what answers, so `layout` paints the
    /// same rectangles this tests.
    private func isLive(_ point: CGPoint, widened: Bool) -> Bool {
        liveRegion(widened: widened).contains(point)
            || controlRects.contains { $0.contains(point) }
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

        while controlCatchments.count < controlRects.count {
            let layer = CALayer()
            layer.backgroundColor = catchmentLayer.backgroundColor
            layer.actions = catchmentLayer.actions
            layer.zPosition = catchmentLayer.zPosition
            self.layer?.addSublayer(layer)
            controlCatchments.append(layer)
        }
        while controlCatchments.count > controlRects.count {
            controlCatchments.removeLast().removeFromSuperlayer()
        }
        for (layer, rect) in zip(controlCatchments, controlRects) {
            layer.frame = rect
        }
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
        guard isLive(local, widened: isSystemDragActive || pointerButtonIsDown) else { return nil }
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
        setPointerInside(countsAsHover(local))
    }

    /// Where the pointer is right now, in this view's coordinates, when that
    /// cannot wait for it to move. Replaceable so a test — which has no window
    /// and no pointer — can say where it is.
    var locatePointer: (() -> CGPoint?)?

    private func currentPointerLocation() -> CGPoint? {
        if let locatePointer { return locatePointer() }
        guard let window else { return nil }
        let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        return convert(inWindow, from: nil)
    }

    /// Re-checks where the pointer is without waiting for it to move.
    ///
    /// A single query of the current location, not a poll: it runs when the
    /// tray changes shape, which is exactly when a stationary pointer can find
    /// itself on the other side of the boundary.
    private func revalidatePointerRegion() {
        guard let local = currentPointerLocation() else { return }
        setPointerInside(bounds.contains(local) && countsAsHover(local))
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

    /// Where a drag is, as far as the tray is concerned (§13).
    enum DragPhase: Equatable {
        /// Nearby: the tray should lean toward it.
        case approaching
        /// Over the target: releasing would stash.
        case over
    }

    /// The whole shape counts, wings included. The wings are kept out of
    /// hover so a pointer can reach the mark without opening the shelf, but a
    /// file dragged onto them is a file aimed at the shelf.
    func dragPhase(at local: CGPoint) -> DragPhase {
        contentRect.insetBy(dx: -TrayMetrics.hoverSlop, dy: -TrayMetrics.hoverSlop).contains(local)
            ? .over
            : .approaching
    }

    /// Distinguishes "a drag is nearby and the tray should lean toward it"
    /// from "a drag is over the target and releasing would stash" (§13).
    private func updateDragPhase(for sender: any NSDraggingInfo) {
        switch dragPhase(at: convert(sender.draggingLocation, from: nil)) {
        case .over: onDragEnter()
        case .approaching: onDragApproach()
        }
    }
}
