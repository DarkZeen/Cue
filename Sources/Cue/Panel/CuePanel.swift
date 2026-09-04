import AppKit

/// The window the panel lives in.
///
/// A borderless non-activating panel, for the usual overlay reasons: no title
/// bar, no place in ⌘-Tab, no Dock tile, and it can appear over a full-screen
/// app without dragging the user out of it.
///
/// The one thing that separates this from a purely passive overlay — Tray's
/// shelf, say — is that Cue is typed into. A search field that cannot take the
/// keyboard is not a search field, so this panel does become key, and
/// `AppState` activates the app when it presents. What it never becomes is
/// *main*: the app the system considers frontmost stays the one the user was
/// working in, which is what makes dismissing the panel put them back exactly
/// where they were with no visible switch.
final class CuePanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // No chrome and no background: the panel draws its own rounded,
        // translucent surface and everything outside it is genuinely nothing.
        isOpaque = false
        backgroundColor = .clear
        // The shadow is AppKit's rather than a drawn one, so it matches every
        // other floating surface on the system exactly.
        hasShadow = true

        isFloatingPanel = true
        // Deliberately false. `hidesOnDeactivate` would tie the panel's life to
        // the app being active, and the whole design is that the app is never
        // active in the way that word usually means.
        hidesOnDeactivate = false
        isMovable = false
        isMovableByWindowBackground = false
        isRestorable = false

        // The search field needs the keyboard the moment the panel appears,
        // not after a click.
        becomesKeyOnlyIfNeeded = false

        // Above ordinary windows, below the menu bar and its status items —
        // there is nothing in this panel worth covering a system alert with.
        level = .floating

        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]

        animationBehavior = .none
        acceptsMouseMovedEvents = true
    }

    /// A borderless panel returns `false` by default, which would leave the
    /// search field permanently unfocusable.
    override var canBecomeKey: Bool { true }

    /// Never. Becoming main is what would make Cue look like the foreground
    /// application, and it is the difference between an overlay and a window.
    override var canBecomeMain: Bool { false }

    /// ⌘W and ⌘. close the panel, because a window that looks like a sheet
    /// should behave like one. Escape is handled with the rest of the keyboard
    /// in `CueWindowController`, where the search field's own use of it can be
    /// taken into account.
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    var onCancel: (() -> Void)?
}
