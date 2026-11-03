import AppKit

/// The window the tray lives in (§28, §29, §30).
///
/// A non-activating panel, so that dragging a file at it never pulls the user
/// out of the app they were working in. Tray has no business stealing focus;
/// it is a surface, not a destination.
///
/// The panel's frame is *constant* — sized to hold the tray at its largest —
/// and the shelf animates inside it. Resizing an `NSWindow` on every frame of
/// a spring is the classic source of the jitter §16 warns about, and it also
/// makes hit regions move out from under the pointer (§74).
final class TrayPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // No chrome, no background: the tray draws its own surface and
        // everything around it is genuinely transparent.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        isFloatingPanel = true
        hidesOnDeactivate = false
        isMovable = false
        isMovableByWindowBackground = false
        isRestorable = false

        // A click on the tray gives it the keyboard, so that Delete, ⌘C and ⌘V
        // have something to act on. Hovering, dropping and dragging never do —
        // this is a non-activating panel, so even taking key leaves the user's
        // app frontmost and Tray out of ⌘-Tab (§28).
        becomesKeyOnlyIfNeeded = false

        // The lowest level that puts the tray at the top edge alongside the
        // menu bar, per §29's instruction to start conservatively. Anything
        // above this is reserved for things far more important than a shelf.
        level = .statusBar

        // The minimum combination that gets the tray onto every Space and
        // alongside full-screen apps (§30). `.stationary` keeps it from being
        // dragged around by Mission Control's space animations.
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]

        // We animate; AppKit should not add its own fade on top.
        animationBehavior = .none
        acceptsMouseMovedEvents = true
    }

    /// Allowed, but only on demand — see `becomesKeyOnlyIfNeeded`. A borderless
    /// panel returns `false` by default, which would break keyboard access to
    /// the shelf entirely (§35, §36).
    ///
    /// Except for a click on the now-playing wings. Pausing the music is not
    /// a click into the shelf, and taking key for it would leave the user's
    /// next keystrokes going to a closed tray instead of the document they
    /// were typing in.
    override var canBecomeKey: Bool { !isClickingControl }

    /// Set for the length of one mouse-down that lands on a wing.
    private var isClickingControl = false

    /// AppKit makes a panel key from inside `sendEvent`, before the view under
    /// the pointer sees the click, so this is the only place that can say no.
    override func sendEvent(_ event: NSEvent) {
        guard event.type == .leftMouseDown,
              let contentView,
              contentView.hitTest(event.locationInWindow) is PillClickView
        else {
            super.sendEvent(event)
            return
        }

        isClickingControl = true
        defer { isClickingControl = false }
        super.sendEvent(event)
    }

    /// Never. Becoming main is what would make Tray look like the foreground
    /// application (§28, §37).
    override var canBecomeMain: Bool { false }
}
