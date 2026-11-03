import AppKit

/// Notices that a drag is under way somewhere on the system (§13, §75).
///
/// The tray's drag region is wider than its hover region, but it is only any
/// use if the window server routes the drag to the panel — which it does only
/// over pixels the panel has painted. Painting the whole drag region all the
/// time would be the invisible mouse trap §74 forbids: every click in it would
/// land on the tray and go nowhere. So it is painted only while the button is
/// down and moving, and this is what says when that is.
///
/// Event-driven, not a poll (§26): the global monitor runs only when the user
/// is actually pressing, dragging or releasing in another app, and does no
/// more than flip a flag. Mouse events need no Accessibility permission —
/// only key events do.
@MainActor
final class SystemDragMonitor {
    /// Raised with `true` when a drag starts and `false` when it ends.
    var onChange: (Bool) -> Void = { _ in }

    private(set) var isDragging = false

    private var monitors: [Any] = []

    func start() {
        guard monitors.isEmpty else { return }

        // Other apps' drags: the ones that bring files to the tray.
        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp],
            handler: { [weak self] event in
                // Global monitor handlers arrive on the main thread.
                let dragging = event.type == .leftMouseDragged
                MainActor.assumeIsolated { self?.update(dragging) }
            }
        ) {
            monitors.append(global)
        }

        // Our own presses. A press that lands on the tray is invisible to the
        // global monitor, and it is the one that matters if a release was ever
        // missed: whatever drag there was is certainly over once the button
        // goes down again, so the wide catchment cannot stay stuck on.
        if let local = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp],
            handler: { [weak self] event in
                MainActor.assumeIsolated { self?.update(false) }
                return event
            }
        ) {
            monitors.append(local)
        }
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        update(false)
    }

    /// Exposed for the drop view's own drag callbacks, which see the end of a
    /// drag that finished over the tray — where the global monitor, by
    /// definition, sees nothing.
    func update(_ dragging: Bool) {
        guard dragging != isDragging else { return }
        isDragging = dragging
        onChange(dragging)
    }

    isolated deinit {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
    }
}
