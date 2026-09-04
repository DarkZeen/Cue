import Foundation
import SwiftUI

/// Every number the panel is drawn from.
///
/// In one place because the panel's height is computed in AppKit — the window
/// has to be the size of its contents before SwiftUI has laid anything out —
/// while the contents are drawn in SwiftUI. Two sets of constants that have to
/// agree is one set of constants.
enum CueLayout {
    /// Wide enough for three tiles that can hold a real playlist name, narrow
    /// enough to read as an overlay rather than a window.
    static let panelWidth: CGFloat = 620

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
    static var panelHeight: CGFloat {
        max(gridModeHeight, resultsModeHeight(count: maximumVisibleResults))
    }

    /// Where the panel sits on screen.
    ///
    /// Horizontally centred, and a third of the way down rather than halfway:
    /// the optical centre of a screen is above its geometric one, and a panel
    /// pinned to the true middle reads as slightly low. This is where Spotlight
    /// and every launcher since has put it, for the same reason.
    static func origin(in screen: NSRect, panelHeight: CGFloat) -> NSPoint {
        NSPoint(
            x: screen.midX - panelWidth / 2,
            y: screen.midY + screen.height * 0.12 - panelHeight / 2
        )
    }
}
