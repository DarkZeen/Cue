import Foundation
import Testing

@testable import Tray

/// When the tray opens and closes (§12, §17).
@MainActor
struct TrayPresenterTests {
    private func presenter(closeAfter delay: TimeInterval) -> TrayPresenter {
        let presenter = TrayPresenter()
        presenter.collapseDelay = { delay }
        return presenter
    }

    @Test func `with no delay the tray closes as the pointer leaves`() {
        let tray = presenter(closeAfter: 0)
        tray.open()
        #expect(tray.state == .expanded)

        tray.pointerExited()

        // Synchronously, not on the next runloop pass: the whole point of a
        // zero delay is that there is no hesitation to see.
        #expect(tray.state == .collapsed)
    }

    @Test func `with a delay the tray stays open for now`() {
        let tray = presenter(closeAfter: 1)
        tray.open()

        tray.pointerExited()

        #expect(tray.state == .expanded)
        #expect(tray.isCollapseScheduled)
    }

    @Test func `a pointer returning during the grace period cancels the close`() {
        let tray = presenter(closeAfter: 1)
        tray.open()
        tray.pointerExited()

        tray.pointerEntered()

        #expect(!tray.isCollapseScheduled)
        #expect(tray.state == .expanded)
    }

    @Test func `a tray being worked in does not close when the pointer leaves`() {
        // Selecting an item and reaching for Delete moves the pointer away from
        // the tray. Closing then would make the keyboard commands unreachable.
        let tray = presenter(closeAfter: 0)
        tray.open()
        tray.beganInteracting()

        tray.pointerExited()

        #expect(tray.state == .expanded)
        #expect(tray.isInteracting)
    }

    @Test func `finishing in the tray lets it close again`() {
        let tray = presenter(closeAfter: 0)
        tray.open()
        tray.beganInteracting()
        tray.pointerExited()

        tray.endedInteracting()

        #expect(tray.state == .collapsed)
    }

    @Test func `a drop is visible for longer than an impatient close delay`() {
        // Something just landed; the user gets a moment to see what, whatever
        // the auto-collapse setting says.
        let tray = presenter(closeAfter: 0)
        tray.dropCompleted()

        #expect(tray.state == .expanded)
        #expect(tray.isCollapseScheduled)
    }

    @Test func `a tray opened from the menu bar does not sit open forever`() {
        // There is no pointer on it to leave, so nothing else would ever
        // schedule its close.
        let tray = presenter(closeAfter: 0)
        tray.open()

        #expect(tray.state == .expanded)
        #expect(tray.isCollapseScheduled)
    }

    @Test func `dragging an item out holds the tray open`() {
        let tray = presenter(closeAfter: 0)
        tray.open()
        let id = UUID()

        tray.beganDraggingItems(ids: [id])

        #expect(tray.state == .draggingItems([id]))
        #expect(tray.state.isOpen)
    }

    @Test func `a whole selection can leave together`() {
        // A state that could only hold one id meant the rest of a dragged
        // selection carried on looking like it had stayed behind.
        let tray = presenter(closeAfter: 0)
        tray.open()
        let ids: Set<UUID> = [UUID(), UUID(), UUID()]

        tray.beganDraggingItems(ids: ids)

        #expect(tray.state.draggedItemIDs == ids)
        for id in ids { #expect(tray.state.draggedItemIDs.contains(id)) }
    }

    @Test func `dragging nothing is not a drag`() {
        let tray = presenter(closeAfter: 0)
        tray.open()

        tray.beganDraggingItems(ids: [])

        #expect(tray.state == .expanded)
    }

    @Test func `escape closes a tray that is being worked in`() {
        let tray = presenter(closeAfter: 1)
        tray.open()
        tray.beganInteracting()

        tray.collapseNow()

        #expect(tray.state == .collapsed)
        #expect(!tray.isInteracting)
    }

    // MARK: - Drags that end badly
    //
    // A tray that still believes a drag is overhead refuses to close, which is
    // how the shelf ended up occasionally stuck open.

    @Test func `a drag that ends without leaving still lets the tray close`() {
        // `draggingExited` is not guaranteed: a drag cancelled with Escape, or
        // one that finishes somewhere else, may never produce one.
        let tray = presenter(closeAfter: 0)
        tray.dragApproached()
        #expect(tray.state == .expanded)
        #expect(tray.isDragApproaching)

        tray.dragSessionEnded()

        #expect(!tray.isDragApproaching)
        #expect(tray.state == .collapsed)
    }

    @Test func `a drag session ending after a drop does not cut the drop short`() {
        // AppKit sends `draggingEnded` after a successful drop too. If that
        // rescheduled the close, the moment §4 gives the user to see what
        // landed would be silently replaced by the ordinary delay.
        let tray = presenter(closeAfter: 0)
        tray.dragEntered()
        tray.dropCompleted()
        #expect(tray.state == .expanded)

        tray.dragSessionEnded()

        #expect(tray.state == .expanded)
    }

    @Test func `a drag ending while the pointer is on the tray leaves it open`() {
        let tray = presenter(closeAfter: 0)
        tray.pointerEntered()
        tray.dragApproached()

        tray.dragSessionEnded()

        #expect(tray.state == .expanded)
    }

    // MARK: - Opening after a drop

    @Test func `with open-after-drop off the shelf closes when the drop is done`() {
        let tray = presenter(closeAfter: 0)
        tray.expandsAfterDrop = { false }
        tray.dragEntered()

        tray.dropCompleted()

        #expect(tray.state == .collapsed)
    }

    @Test func `with open-after-drop on the shelf shows what landed`() {
        let tray = presenter(closeAfter: 0)
        tray.expandsAfterDrop = { true }
        tray.dragEntered()

        tray.dropCompleted()

        #expect(tray.state == .expanded)
        #expect(tray.isCollapseScheduled)
    }

    @Test func `an incoming drag opens a closed tray`() {
        let tray = presenter(closeAfter: 0)
        #expect(tray.state == .collapsed)

        tray.dragApproached()
        #expect(tray.state == .expanded)

        tray.dragEntered()
        #expect(tray.state == .dragOver)
        #expect(tray.state.isDropTargetActive)
    }
}
