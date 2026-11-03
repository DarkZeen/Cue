import AppKit
import Testing

@testable import Cue

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

    // MARK: - The now-playing wings

    private let housing = CGSize(width: 180, height: 32)

    private func rect(for shape: TrayShape, in view: TrayDropView) -> CGRect {
        CGRect(
            x: view.bounds.midX - shape.width / 2,
            y: view.bounds.maxY - shape.height,
            width: shape.width,
            height: shape.height
        )
    }

    private func wings(of shape: TrayShape, in view: TrayDropView) -> [CGRect] {
        shape.wingRects(centredOn: view.bounds.midX, top: view.bounds.maxY)
    }

    /// Closed, holding files, with Cue playing: the housing and its wings, set
    /// the way the controller sets them.
    private func closedPillView() -> TrayDropView {
        let view = TrayDropView(frame: NSRect(x: 0, y: 0, width: 900, height: 400))
        let pill = TrayShape.nowPlaying(cutout: housing)
        view.setRegions(content: rect(for: pill, in: view), controls: wings(of: pill, in: view))
        view.layoutSubtreeIfNeeded()
        return view
    }

    private func centre(_ rect: CGRect) -> CGPoint {
        CGPoint(x: rect.midX, y: rect.midY)
    }

    private func move(_ view: TrayDropView, to point: CGPoint) {
        let event = NSEvent.mouseEvent(
            with: .mouseMoved,
            location: point,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        )!
        view.mouseMoved(with: event)
    }

    @Test func `the wings can be clicked`() {
        let view = closedPillView()

        #expect(view.controlRects.count == 2)
        for wing in view.controlRects {
            #expect(view.hitTest(centre(wing)) != nil)
        }
    }

    @Test func `pointing at a wing does not open the shelf`() {
        let view = closedPillView()
        var entered = 0
        view.onPointerEnter = { entered += 1 }

        for wing in view.controlRects {
            #expect(!view.countsAsHover(centre(wing)))
            move(view, to: centre(wing))
        }
        #expect(entered == 0)

        // The housing between them still opens it.
        move(view, to: CGPoint(x: view.bounds.midX, y: view.bounds.maxY - 10))
        #expect(entered == 1)
    }

    @Test func `wings growing under a resting pointer do not open the shelf`() {
        // Closed with files and no music; the pointer is resting over the
        // menu bar where the right wing is about to appear.
        let view = TrayDropView(frame: NSRect(x: 0, y: 0, width: 900, height: 400))
        let closed = TrayShape.collapsed(cutout: housing, isEmpty: false)
        view.setRegions(content: rect(for: closed, in: view), controls: [])

        let pill = TrayShape.nowPlaying(cutout: housing)
        let resting = centre(wings(of: pill, in: view)[1])
        view.locatePointer = { resting }
        #expect(!view.countsAsHover(resting))

        var entered = 0
        view.onPointerEnter = { entered += 1 }

        // Music starts.
        view.setRegions(content: rect(for: pill, in: view), controls: wings(of: pill, in: view))
        #expect(entered == 0)

        // And stops again.
        view.setRegions(content: rect(for: closed, in: view), controls: [])
        #expect(entered == 0)
    }

    @Test func `the painted catchment covers the wings, and only the wings`() {
        let view = closedPillView()

        #expect(view.catchmentFrame == view.hoverActivationRect)
        #expect(view.controlCatchmentFrames == view.controlRects)
    }

    /// The pill on a display without a notch and a 24pt menu bar: a housing
    /// narrower than the hover strip's minimum and shorter than its height.
    private func shortBarPillView() -> TrayDropView {
        let view = TrayDropView(frame: NSRect(x: 0, y: 0, width: 900, height: 400))
        let cutout = TrayMetrics.cutout(notchSize: nil, menuBarHeight: 24, screenWidth: 900)
        let pill = TrayShape.nowPlaying(cutout: cutout)
        view.setRegions(content: rect(for: pill, in: view), controls: wings(of: pill, in: view))
        view.layoutSubtreeIfNeeded()
        return view
    }

    @Test func `on a short bar, nothing under a wing answers`() {
        let view = shortBarPillView()

        for wing in view.controlRects {
            // Just below the wing, beside the strip: the app's window.
            let below = CGPoint(x: wing.midX, y: wing.minY - 3)
            guard !view.hoverActivationRect.contains(below) else { continue }
            #expect(view.hitTest(below) == nil)
        }
    }

    @Test func `on a short bar, the inside of a wing still does not open the shelf`() {
        // The hover strip's 148pt minimum is wider than this housing, so it
        // reaches into both wings; only the carve-out keeps them clickable.
        let view = shortBarPillView()
        #expect(view.controlRects.contains { $0.intersects(view.hoverActivationRect) })

        for wing in view.controlRects {
            let overlap = wing.intersection(view.hoverActivationRect)
            guard !overlap.isNull, !overlap.isEmpty else { continue }
            #expect(!view.countsAsHover(centre(overlap)))
        }
    }

    @Test func `the hover strip is the housing's, not the pill's`() {
        let view = closedPillView()

        #expect(abs(view.hoverActivationRect.width - max(TrayMetrics.hoverActivationWidth, housing.width)) < 0.001)
    }

    @Test func `a file dragged onto a wing is aimed at the shelf`() {
        let view = closedPillView()

        for wing in view.controlRects {
            #expect(view.dragActivationRect.contains(centre(wing)))
            #expect(view.dragPhase(at: centre(wing)) == .over)
        }
    }

    @Test func `opened, the wings are part of the shelf again`() {
        let view = closedPillView()
        let closedRegion = view.hoverActivationRect
        let wing = centre(view.controlRects[0])

        // The flag flips a beat before the controller clears the wings.
        view.isOpen = true

        #expect(view.hoverActivationRect.contains(closedRegion))
        #expect(view.countsAsHover(wing))
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
