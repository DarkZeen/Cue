import Foundation
import Observation
import OSLog

/// Owns the tray's state and every transition into it (§43).
///
/// All the timing that makes the tray feel considered rather than twitchy
/// lives here: the short delay before hover opens it, the grace period before
/// it closes, and the rule that a returning pointer cancels a pending collapse
/// (§17).
///
/// Delays are cancellable `Task`s rather than timers, so a reversal — pointer
/// leaves, pointer comes straight back — cancels cleanly instead of racing.
@Observable
final class TrayPresenter {
    private(set) var state: TrayPresentationState = .collapsed

    /// True while a collapse is waiting out its grace period. The tray is still
    /// open; it has simply been told to close soon, and can be reprieved.
    private(set) var isCollapseScheduled = false

    /// A drag is somewhere in the wider activation zone but has not entered the
    /// drop area yet — the tray leans toward it without committing (§13).
    private(set) var isDragApproaching = false

    /// True for the moment after something lands, while the shelf takes the
    /// impact (§46).
    private(set) var isAbsorbingDrop = false

    private var dropImpactTask: Task<Void, Never>?

    /// The container's scale (§13, §46).
    ///
    /// Lives here rather than on `TrayPresentationState` because two of its
    /// three inputs — an approaching drag and a landing drop — are facts about
    /// what is happening *around* the tray, not about which state it is in.
    /// That is why §13's anticipation step was specified with a value and then
    /// never wired: there was nowhere in the state enum for it to come from.
    var containerScale: CGFloat {
        if isAbsorbingDrop { return TrayScale.dropImpact }
        if state.isDropTargetActive { return TrayScale.dropTargetActive }
        // A drag is in the neighbourhood but not yet over the target: the shelf
        // leans toward it without committing.
        if isDragApproaching { return TrayScale.dragApproaching }
        return TrayScale.resting
    }

    private let logger = Diagnostics.logger("presenter")

    /// True while the user is working *in* the tray — something is selected,
    /// the panel has the keyboard. An interacting tray does not close when the
    /// pointer wanders off, because the pointer is no longer the thing driving
    /// it. Without this, selecting an item and reaching for Delete would close
    /// the shelf on the way to the keyboard.
    private(set) var isInteracting = false

    /// How long to wait before closing once the pointer leaves. Supplied by the
    /// caller so the setting is the single source of truth rather than a
    /// constant that quietly disagrees with it.
    var collapseDelay: () -> TimeInterval = { TrayAnimation.collapseDelay }

    /// Whether clicking into the tray pins it open until dismissed. When this
    /// is off, the pointer leaving always closes the shelf, and the keyboard
    /// only reaches it while the pointer is on it.
    var holdsOpenWhenClicked: () -> Bool = { true }

    /// Whether the shelf stays open to show what just landed, or closes as soon
    /// as the drop is done.
    var expandsAfterDrop: () -> Bool = { true }

    private var pointerIsInside = false
    private var openTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?

    /// Fires whenever the state actually changes, so the window layer can
    /// react (raise level, enable key handling) without observing internals.
    var onStateChange: ((TrayPresentationState) -> Void)?

    // MARK: - Pointer (§12)

    func pointerEntered() {
        pointerIsInside = true
        cancelScheduledCollapse()

        guard state == .collapsed else { return }
        guard openTask == nil else { return }

        // A short delay, not zero. Instant opening from a pointer merely
        // crossing the top of the screen is what makes this class of app
        // annoying; 100ms is below the threshold where deliberate movement
        // feels delayed, but above accidental travel.
        openTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(TrayAnimation.hoverActivationDelay))
            guard !Task.isCancelled, let self, self.pointerIsInside else { return }
            self.openTask = nil
            self.transition(to: .expanded)
        }
    }

    func pointerExited() {
        pointerIsInside = false
        openTask?.cancel()
        openTask = nil

        guard state.isOpen else { return }
        scheduleCollapse(after: collapseDelay())
    }

    // MARK: - Working in the tray

    func beganInteracting() {
        // Selecting still works either way — this only decides whether the
        // selection is enough to hold the shelf open.
        guard holdsOpenWhenClicked() else { return }
        isInteracting = true
        cancelScheduledCollapse()
    }

    func endedInteracting() {
        guard isInteracting else { return }
        isInteracting = false
        guard state.isOpen, !pointerIsInside else { return }
        scheduleCollapse(after: collapseDelay())
    }

    // MARK: - External drags (§13, §14)

    /// A drag has entered the wide activation zone but not the drop area.
    func dragApproached() {
        guard !isDragApproaching else { return }
        isDragApproaching = true
        cancelScheduledCollapse()
        openTask?.cancel()
        openTask = nil
        if state == .collapsed {
            transition(to: .expanded)
        }
    }

    /// A drag is over the drop area and a release would stash.
    func dragEntered() {
        isDragApproaching = true
        cancelScheduledCollapse()
        openTask?.cancel()
        openTask = nil
        transition(to: .dragOver)
    }

    /// The drag left without dropping.
    func dragExited() {
        isDragApproaching = false
        guard state == .dragOver || state == .expanded else { return }
        transition(to: .expanded)

        // A drag that merely clipped the edge of the target gets a shorter
        // leash than a pointer, but still a leash — slamming shut mid-gesture
        // would be worse than staying open a beat too long.
        if !pointerIsInside {
            scheduleCollapse(after: TrayAnimation.dragExitGrace + collapseDelay())
        }
    }

    /// Something was dropped (§4, §17).
    func dropCompleted() {
        isDragApproaching = false
        transition(to: .expanded)
        absorbDrop()
        guard !pointerIsInside else { return }

        if expandsAfterDrop() {
            // Longer than an ordinary close: something just landed and the user
            // deserves a moment to see what it was, however impatient the
            // auto-collapse setting is.
            scheduleCollapse(after: max(collapseDelay(), TrayAnimation.collapseDelay) * 2)
        } else {
            scheduleCollapse(after: collapseDelay())
        }
    }

    /// The shelf gives a little as something lands on it, then springs back.
    ///
    /// Two values and an underdamped spring, rather than the three keyframes
    /// §46 describes: the overshoot on the way back *is* the 1.02.
    private func absorbDrop() {
        dropImpactTask?.cancel()
        isAbsorbingDrop = true
        dropImpactTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(TrayAnimation.dropImpactDuration))
            guard !Task.isCancelled else { return }
            self?.isAbsorbingDrop = false
        }
    }

    /// A drag session ended, however it ended.
    ///
    /// `draggingExited` is not guaranteed — a drag cancelled with Escape, or
    /// one that finishes somewhere else, may never produce one — and a tray
    /// that still believes a drag is overhead refuses to close. A drop clears
    /// the flag first, so this does nothing after a successful one and cannot
    /// cut short the moment §4 gives the user to see what landed.
    func dragSessionEnded() {
        guard isDragApproaching else { return }
        isDragApproaching = false
        guard state.isOpen, !pointerIsInside else { return }
        scheduleCollapse(after: collapseDelay())
    }

    // MARK: - Dragging items out (§21, §22)

    func beganDraggingItems(ids: Set<TrayItem.ID>) {
        guard !ids.isEmpty else { return }
        cancelScheduledCollapse()
        transition(to: .draggingItems(ids))
    }

    func endedDraggingItems() {
        guard !state.draggedItemIDs.isEmpty else { return }
        transition(to: .expanded)
        if !pointerIsInside {
            scheduleCollapse(after: collapseDelay())
        }
    }

    // MARK: - Explicit commands (menu bar, keyboard)

    /// Opened deliberately — from the menu bar, or a keyboard shortcut.
    func open() {
        cancelScheduledCollapse()
        openTask?.cancel()
        openTask = nil
        transition(to: .expanded)

        // A tray opened from the menu bar has no pointer on it to leave, so
        // nothing would ever schedule its collapse and it would sit open until
        // the user happened to hover it. It gets a longer leash than a hover —
        // the user asked for it and needs time to reach it — but it does close
        // on its own.
        if !pointerIsInside {
            // Opened deliberately from the menu bar, with the pointer nowhere
            // near — the user needs time to travel there, whatever the
            // auto-collapse setting says.
            scheduleCollapse(after: max(collapseDelay(), TrayAnimation.collapseDelay) * 4)
        }
    }

    func collapseNow() {
        cancelScheduledCollapse()
        openTask?.cancel()
        openTask = nil
        isDragApproaching = false
        isInteracting = false
        dropImpactTask?.cancel()
        isAbsorbingDrop = false
        transition(to: .collapsed)
    }

    func toggle() {
        state.isOpen ? collapseNow() : open()
    }

    // MARK: - Machinery

    private func scheduleCollapse(after delay: TimeInterval) {
        guard !Diagnostics.holdsTrayOpen else { return }
        guard !isInteracting else { return }

        collapseTask?.cancel()

        // Zero means close on the way out, not on the next runloop pass. Going
        // through a task for it would put a visible frame of hesitation on the
        // one setting whose whole point is that there is none.
        guard delay > 0 else {
            isCollapseScheduled = false
            collapseTask = nil
            transition(to: .collapsed)
            return
        }

        isCollapseScheduled = true
        logger.debug("collapse scheduled in \(delay, privacy: .public)s")
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            guard !self.pointerIsInside, !self.isDragApproaching else {
                self.isCollapseScheduled = false
                return
            }
            self.isCollapseScheduled = false
            self.collapseTask = nil
            self.transition(to: .collapsed)
        }
    }

    /// The reprieve. A pointer that comes back during the grace period keeps
    /// the tray open with no visible hitch (§17).
    private func cancelScheduledCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
        isCollapseScheduled = false
    }

    private func transition(to next: TrayPresentationState) {
        guard state != next else { return }
        logger.debug("\(String(describing: self.state), privacy: .public) → \(String(describing: next), privacy: .public)")
        state = next
        onStateChange?(next)
    }
}
