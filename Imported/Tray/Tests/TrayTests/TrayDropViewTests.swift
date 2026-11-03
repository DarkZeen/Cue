import AppKit
import Testing

@testable import Tray

/// The tray's catchment, as the window server sees it (§74, §75).
///
/// A transparent window only receives the mouse — and drags — over pixels it
/// has actually painted. `hitTest` can claim as much of the panel as it likes;
/// if nothing is drawn there, macOS sends the drag to whatever is underneath
/// and the tray never hears about it. These pin the painted catchment to the
/// region `hitTest` answers for.
@MainActor
struct TrayDropViewTests {
    /// A panel-sized drop view holding the empty, closed handle — the smallest
    /// thing the tray ever draws, and the case that broke.
    private func closedEmptyView() -> TrayDropView {
        let view = TrayDropView(frame: NSRect(x: 0, y: 0, width: 900, height: 400))
        let handle = TrayShape.collapsed(cutout: CGSize(width: 180, height: 32), isEmpty: true)
        view.contentRect = CGRect(
            x: view.bounds.midX - handle.width / 2,
            y: view.bounds.maxY - handle.height,
            width: handle.width,
            height: handle.height
        )
        view.layoutSubtreeIfNeeded()
        return view
    }

    @Test func `closed, the painted catchment covers the whole hover region`() {
        let view = closedEmptyView()

        #expect(view.catchmentFrame == view.hoverActivationRect)
        // Far bigger than the 56 × 5 handle, which is all a surface with no
        // shadow paints on its own.
        #expect(view.catchmentFrame.width >= TrayMetrics.hoverActivationWidth)
        #expect(view.catchmentFrame.height >= TrayMetrics.hoverActivationHeight)
    }

    @Test func `a drag under way widens the painted catchment to the drag region`() {
        let view = closedEmptyView()

        view.isSystemDragActive = true
        view.layoutSubtreeIfNeeded()

        #expect(view.catchmentFrame == view.dragActivationRect.union(view.hoverActivationRect))
        #expect(view.catchmentFrame.width >= TrayMetrics.dragActivationWidth)
    }

    @Test func `the catchment shrinks back once the drag is over`() {
        let view = closedEmptyView()

        view.isSystemDragActive = true
        view.layoutSubtreeIfNeeded()
        view.isSystemDragActive = false
        view.layoutSubtreeIfNeeded()

        #expect(view.catchmentFrame == view.hoverActivationRect)
    }

    /// The tray flags itself open a beat before SwiftUI reports the bigger
    /// shape. If the region shrank to the old handle in that beat, a pointer
    /// resting in the strip that opened it would count as having left — the
    /// tray closed, the strip came back, it opened again, ten times a second.
    @Test func `opening never shrinks the region the pointer opened it from`() {
        let view = closedEmptyView()
        let closedRegion = view.hoverActivationRect

        view.isOpen = true   // shape not yet reported: still the handle

        #expect(view.hoverActivationRect.contains(closedRegion))
    }

    @Test func `the catchment is painted, but too faintly to see`() {
        let alpha = TrayDropView.catchmentAlpha
        // Zero is what the window server treats as "not there".
        #expect(alpha > 0)
        // And at 8 bits it must still round to something non-zero.
        #expect((alpha * 255).rounded() >= 1)
        #expect(alpha <= 0.02)
    }
}
