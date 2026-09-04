import Foundation
import SwiftUI

/// Every number the panel is drawn from.
///
/// In one place because the panel's height is computed in AppKit — the window
/// has to be the size of its contents before SwiftUI has laid anything out —
/// while the contents are drawn in SwiftUI. Two sets of constants that have to
/// agree is one set of constants.
enum CueLayout {
    /// The panel's width, and through it the size of everything in it.
    ///
    /// A `var` because it is a setting: tiles, the grid and the panel's own
    /// height are all derived from it, so one number scales the whole surface
    /// and nothing has to be adjusted to match. `AppState` sets it at launch
    /// and whenever it changes.
    ///
    /// The default of 540 is where the design was drawn. Three squares across a
    /// 620-point panel are 192 each, which makes the grid alone 596 tall and
    /// the panel over 730 — most of the height of a laptop screen, for
    /// something meant to be a glance.
    static var panelWidth: CGFloat = defaultPanelWidth

    static let defaultPanelWidth: CGFloat = 540
    /// Narrow enough that three covers are still worth looking at, wide enough
    /// that the panel does not start competing with the screen.
    static let panelWidthRange: ClosedRange<CGFloat> = 440...760

    static let cornerRadius: CGFloat = 20
    static let outerPadding: CGFloat = 12
    /// Between the search field and whatever is under it.
    static let sectionGap: CGFloat = 8

    static let searchHeight: CGFloat = 48
    static let searchCornerRadius: CGFloat = 12

    // MARK: - Grid

    static let gridColumns = 3
    static let gridRows = 3
    static let tileSpacing: CGFloat = 10
    static let tileCornerRadius: CGFloat = 12
    static let tileHeight: CGFloat = 128
    /// Square, and as tall as the tile allows once the two lines of label are
    /// taken out. Artwork is the thing being aimed at; the words are
    /// confirmation.
    static let tileArtworkSize: CGFloat = 72

    static var tileWidth: CGFloat {
        let available = panelWidth - outerPadding * 2 - tileSpacing * CGFloat(gridColumns - 1)
        return available / CGFloat(gridColumns)
    }

    static var gridHeight: CGFloat {
        tileHeight * CGFloat(gridRows) + tileSpacing * CGFloat(gridRows - 1)
    }

    // MARK: - Gallery

    /// The redesigned grid: three pages of artwork, one page at a time.
    ///
    /// Its numbers live beside the classic grid's rather than replacing them,
    /// because both designs ship and the window has to be built tall enough for
    /// whichever one is switched on.
    enum Gallery {
        static let tileCornerRadius: CGFloat = 10
        static let tileSpacing: CGFloat = 10

        /// The page's name and its randomize control.
        static let headerHeight: CGFloat = 28
        /// The dots that say which of three pages this is.
        static let dotsHeight: CGFloat = 16

        /// Square. Album art is square, and a rectangular tile either crops it
        /// or letterboxes it — the first throws away part of the only thing on
        /// the tile worth seeing, the second puts bars around it.
        static func tileSide(for panelWidth: CGFloat) -> CGFloat {
            let available = panelWidth - outerPadding * 2 - tileSpacing * CGFloat(gridColumns - 1)
            return available / CGFloat(gridColumns)
        }

        static func gridHeight(for panelWidth: CGFloat) -> CGFloat {
            tileSide(for: panelWidth) * CGFloat(gridRows) + tileSpacing * CGFloat(gridRows - 1)
        }

        /// The width one page occupies, which is also how far the strip of
        /// pages slides when the page changes.
        static func pageWidth(for panelWidth: CGFloat) -> CGFloat {
            panelWidth - outerPadding * 2
        }
    }

    /// The height of the whole panel showing the gallery, at a given width.
    ///
    /// Every one of these takes the width rather than reading the stored one.
    /// A static `panelWidth` is invisible to SwiftUI — moving the slider
    /// resized the window while the contents went on laying themselves out at
    /// the old size, which is a mess that looks like a layout bug and is really
    /// an observation bug.
    static func galleryModeHeight(for panelWidth: CGFloat) -> CGFloat {
        outerPadding + searchHeight + sectionGap
            + Gallery.headerHeight + 6
            + Gallery.gridHeight(for: panelWidth) + 8
            + Gallery.dotsHeight + outerPadding
    }

    /// The window's height at a given width: tall enough for whichever design
    /// and mode needs the most.
    static func panelHeight(for panelWidth: CGFloat) -> CGFloat {
        max(
            galleryModeHeight(for: panelWidth),
            max(gridModeHeight, resultsModeHeight(count: maximumVisibleResults))
        )
    }

    // MARK: - Results

    static let resultRowHeight: CGFloat = 52
    static let resultArtworkSize: CGFloat = 36
    /// Past seven rows the list stops being something you scan and starts
    /// being something you scroll, and a panel that fills the screen has lost
    /// the plot. The rest are still reachable with the arrow keys.
    static let maximumVisibleResults = 7

    // MARK: - Heights

    /// The height of the whole panel in grid mode.
    static var gridModeHeight: CGFloat {
        outerPadding + searchHeight + sectionGap + gridHeight + outerPadding
    }

    /// The height of the whole panel showing `count` results.
    ///
    /// Computed rather than measured so the window can be resized in the same
    /// turn of the run loop that the content changes in — a window that
    /// resizes one frame after its contents is the flicker every overlay of
    /// this kind eventually has to fix.
    static func resultsModeHeight(count: Int) -> CGFloat {
        let rows = min(max(count, 1), maximumVisibleResults)
        return outerPadding + searchHeight + sectionGap
            + resultRowHeight * CGFloat(rows) + outerPadding
    }

    /// The window's height, which never changes.
    ///
    /// The panel is built at the tallest its contents can be and the contents
    /// animate *inside* it. Resizing an `NSWindow` on every frame of a spring
    /// is the classic source of jitter in an overlay like this, and it makes
    /// the search field — the one thing the user is looking at — move while
    /// they are typing into it. The cost is a strip of transparent window
    /// below a short results list, and `CuePanelContentView` declines to hit-
    /// test that strip so it is not a dead zone over another app.
    static var panelHeight: CGFloat { panelHeight(for: panelWidth) }

    /// Where the panel sits, given a position expressed as a fraction of the
    /// room it has to move in.
    static func origin(in visible: NSRect, size: NSSize, position: CGPoint) -> NSPoint {
        let free = NSSize(
            width: max(visible.width - size.width, 0),
            height: max(visible.height - size.height, 0)
        )
        return NSPoint(
            x: visible.minX + free.width * position.x,
            y: visible.minY + free.height * position.y
        )
    }

    /// The inverse: what fraction a given origin represents. Used while
    /// dragging, so the position that gets saved is display-independent.
    static func position(of origin: NSPoint, size: NSSize, in visible: NSRect) -> CGPoint {
        let free = NSSize(
            width: max(visible.width - size.width, 0),
            height: max(visible.height - size.height, 0)
        )
        return CGPoint(
            x: free.width > 0 ? min(max((origin.x - visible.minX) / free.width, 0), 1) : 0.5,
            y: free.height > 0 ? min(max((origin.y - visible.minY) / free.height, 0), 1) : 0.5
        )
    }
}
