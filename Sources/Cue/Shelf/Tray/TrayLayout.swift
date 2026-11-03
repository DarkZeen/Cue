import CoreGraphics
import Foundation

/// Every dimension the tray has, in one place (§7).
///
/// The numbers are the Dynamic Island's, not invented here: a 14pt shoulder
/// where the shape leaves the top edge, a 28pt bottom radius, 28pt of side
/// inset, a 36pt header, 18pt between the header and the content, 22pt under
/// it. Copying the island's *proportions* rather than approximating them is
/// the whole point — a black shape hanging off the notch is only convincing
/// while its measurements agree with the hardware's.
nonisolated enum TrayMetrics {
    // MARK: Silhouette

    /// How far the shape draws in from the top edge before it becomes a wall.
    ///
    /// The island's shoulders are concave and *inside* the declared width: the
    /// shape spans the full width where it meets the bezel and narrows by this
    /// much on each side, which is what makes it read as carved out of the
    /// display rather than taped underneath it.
    static let shoulder: CGFloat = 14

    /// The bottom corners. Clamped against the height in `TrayShape`, so the
    /// closed cutout and the open shelf are the same radius expression at two
    /// sizes rather than two constants that have to be kept in step.
    static let cornerRadius: CGFloat = 28

    // MARK: Chrome

    static let horizontalInset: CGFloat = 28

    /// The gap between the menu bar strip and the first row of files, and the
    /// air underneath them.
    static let spacing: CGFloat = 12
    static let bottomInset: CGFloat = 14

    /// How far the name and the buttons sit from the sides of the shelf.
    ///
    /// The island keeps everything on one inset because everything in it is
    /// content — pages of controls that have to line up down the left edge.
    /// Tray's header is not content: it is the name of the thing and the way
    /// out of it, and those belong in the corners, leaving the whole of the
    /// middle to the files. How far into the corners is a matter of taste, so
    /// it is a setting.
    ///
    /// Sides only. There is no vertical equivalent to set: the header sits in
    /// the menu bar's own strip, and anything that moved it out of that strip
    /// would take it off the line it is there to share.
    static let defaultHeaderInset: CGFloat = 16

    /// From flush with the wall to most of the way in. A header inside the
    /// shoulder would be a header drawn outside the shape.
    static let headerInsetRange: ClosedRange<Double> = Double(shoulder)...80

    /// The header does not get a band of its own: it lives in the menu bar.
    ///
    /// The tray is drawn over the top of the menu bar, so the strip the housing
    /// occupies is already there and already the right height — and the things
    /// in it, the name and the buttons, are the same kind of thing as the menu
    /// bar items sitting either side of the shelf. Putting them anywhere else
    /// left that strip black and empty and everything below it one row lower
    /// than it needed to be. What the header gets instead is a size for its
    /// buttons that fits whatever menu bar this Mac has.
    static func headerButtonSize(inBand band: CGFloat) -> CGFloat {
        max(18, min(28, band - 4))
    }

    /// Clear space between the header's left corner and the housing, so what
    /// is playing never runs under the camera.
    static let headerGap: CGFloat = 8


    /// What "Spacious" buys over "Compact": the island's own 40pt.
    static let spaciousExtra: CGFloat = 40

    /// The island never touches the sides or the bottom of the display.
    static let screenMargin: CGFloat = 24
    static let bottomScreenMargin: CGFloat = 48

    /// The shelf is never narrower than the housing plus a little on each side.
    static let minimumSideRoom: CGFloat = 36

    // MARK: The resting cutout

    /// A camera housing for a display that has none.
    ///
    /// The island puts the same black cutout on every Mac, scaled to the menu
    /// bar it has to sit in — 180pt wide against a 32pt bar. Recreating it is
    /// what keeps one design on a MacBook Pro and an external display, instead
    /// of a notch shape on one and a floating pill on the other.
    static let simulatedCutoutWidth: CGFloat = 180
    static let simulatedCutoutReference: CGFloat = 32

    /// The housing this display has, real or recreated.
    static func cutout(notchSize: CGSize?, menuBarHeight: CGFloat, screenWidth: CGFloat) -> CGSize {
        let bar = menuBarHeight.isFinite ? min(64, max(16, menuBarHeight)) : 24
        let widest = max(1, screenWidth * 0.7)

        if let notchSize, notchSize.width > 0, notchSize.height > 0 {
            return CGSize(
                width: min(notchSize.width, widest),
                height: min(notchSize.height, 64)
            )
        }

        return CGSize(
            width: min(simulatedCutoutWidth * bar / simulatedCutoutReference, widest),
            height: bar
        )
    }

    /// The empty, resting tray: a handle, not a panel (§77). Present enough to
    /// be found, quiet enough to be forgotten. The island shows its bare
    /// cutout here; Tray keeps the handle, because an empty shelf claiming a
    /// notch-sized piece of an external display is a claim about nothing.
    static let handleWidth: CGFloat = 56
    static let handleHeight: CGFloat = 5

    // MARK: Now playing

    /// The wings the closed shelf grows while Cue's own player has a track:
    /// the cover on the left, the mark on the right, the housing between them.
    ///
    /// Everything here is a function of the housing's height, never a pixel
    /// count, for the same reason the cutout is (§8): a 32pt notch, a 24pt
    /// menu bar and a 38pt one at a larger text size all have to come out
    /// looking like the same object. At 32pt they give the island's own
    /// numbers — a 22pt cover, 8pt of air either side of it.

    /// The cover, square. Clamped so a very short bar still has a cover large
    /// enough to recognise and a very tall one does not get a poster.
    static func wingArtSize(forHeight height: CGFloat) -> CGFloat {
        min(28, max(16, (height * 0.6875).rounded()))
    }

    /// The cover's corners: the same proportion at every size, so it reads as
    /// a small tile rather than as a circle at 16pt and a square at 28pt.
    static func wingArtRadius(forHeight height: CGFloat) -> CGFloat {
        wingArtSize(forHeight: height) * 0.27
    }

    /// The air either side of what a wing holds.
    static func wingPadding(forHeight height: CGFloat) -> CGFloat {
        max(6, (height * 0.25).rounded())
    }

    /// How far a shape this tall actually draws in at the top.
    ///
    /// Must agree with `TraySurface.path(in:)`, which scales the shoulder down
    /// on a short shape: content has to sit inside the visible body, and the
    /// body's outer wall is this far in from the declared width.
    static func effectiveShoulder(forHeight height: CGFloat) -> CGFloat {
        min(shoulder, max(0, height) * 0.28)
    }

    /// One wing, wall to housing: the shoulder, then the padding, the cover or
    /// the mark, and the padding again.
    static func wingWidth(forHeight height: CGFloat) -> CGFloat {
        effectiveShoulder(forHeight: height)
            + wingPadding(forHeight: height) * 2
            + wingArtSize(forHeight: height)
    }

    // MARK: Drop hint

    /// The dashed outline around the drop area, inset from the surface edge.
    static let defaultDropOutlineInset: CGFloat = 7
    static let dropOutlineInsetRange: ClosedRange<Double> = 0...30
    static let dropOutlineDash: CGFloat = 5
    static let dropOutlineGap: CGFloat = 4
    static let dropOutlineCornerRadius: CGFloat = 16

    // MARK: Items

    /// How large a file is drawn. Adjustable, because how much of the shelf a
    /// file should occupy depends on what you keep in it — a row of photographs
    /// wants a different size from a row of documents.
    static let defaultThumbnailSize: CGFloat = 52
    static let thumbnailSizeRange: ClosedRange<Double> = 32...88

    static let itemSpacing: CGFloat = 12

    /// How much wider than its thumbnail an item is, so that filenames get
    /// somewhere to live without every one of them ending in an ellipsis.
    static let itemLabelMargin: CGFloat = 14

    /// The gap between a thumbnail and the name beneath it.
    static let labelSpacing: CGFloat = 5
    static let labelHeight: CGFloat = 13

    /// How far the shelf's contents fade out at a scrolling edge (§20).
    static let scrollFade: CGFloat = 18

    // MARK: Hit regions (§74)

    /// How far outside the visible shape the pointer still counts as "on" the
    /// tray. Stops the shelf collapsing out from under a pointer that drifted
    /// a pixel past the edge.
    static let hoverSlop: CGFloat = 8

    /// The resting hover target: narrow, so ordinary mouse travel across the
    /// menu bar does not keep tripping it (§12, §75).
    static let hoverActivationWidth: CGFloat = 148
    static let hoverActivationHeight: CGFloat = 30

    /// The drag target is deliberately wider — throwing a file at the top of
    /// the screen should not demand precision (§75).
    static let dragActivationWidth: CGFloat = 320
    static let dragActivationHeight: CGFloat = 46

    /// The panel is a fixed-size window; the tray is drawn inside it and the
    /// window never resizes. Resizing an `NSWindow` per frame is the classic
    /// source of the jitter §16 warns about, so the surface animates in the
    /// view layer and the window just stays big enough to contain the largest
    /// state.
    static let panelPadding: CGFloat = 44
}

/// How big the open shelf is (§7).
///
/// The island's three: two presets that decide for you and a custom size for
/// anyone who would rather decide themselves. Spacious is the default there
/// and the default here, because the preset that shows the most is the one
/// worth landing on first.
nonisolated enum TraySize: String, CaseIterable, Sendable {
    case compact
    case spacious
    case custom

    /// Where a custom shelf starts before anyone touches it. The island's own
    /// 440, and a height that suits one row of files.
    static let defaultWidth: Double = 440
    static let defaultHeight: Double = 240

    /// Sanity, not design.
    ///
    /// There is no bracket on a custom size any more. The only limits are
    /// physical — the display the shelf is on, the camera housing it hangs
    /// from, and the icons it is holding — and all three are applied where the
    /// shape is built, against the screen that is actually there. A number on
    /// its way to disk only has to be a number.
    static let storable: ClosedRange<Double> = 1...10_000

    /// Every width this display can actually show, so the whole of a slider's
    /// travel does something.
    ///
    /// The floor is the housing plus a little on each side: a shelf narrower
    /// than the notch it hangs from would be a shelf hiding behind it. The
    /// ceiling is the display, less the margin that keeps the shelf reading as
    /// an object on the screen rather than a second menu bar (§20).
    static func widthRange(screenWidth: CGFloat, cutoutWidth: CGFloat) -> ClosedRange<Double> {
        let low = Double(cutoutWidth + TrayMetrics.minimumSideRoom)
        let high = Double(screenWidth - TrayMetrics.screenMargin)
        return low...max(low, high)
    }

    /// Every height this display can show, measured under the housing — which
    /// is how the setting itself reads, so the number on the slider is the
    /// number of points of shelf you get.
    ///
    /// The floor is whatever the current icons and the chrome need; shrink the
    /// icons or turn off file names and it drops.
    static func heightRange(
        screenHeight: CGFloat,
        cutoutHeight: CGFloat,
        item: TrayItemMetrics
    ) -> ClosedRange<Double> {
        let low = Double(item.contentFloor)
        let high = Double(
            screenHeight - TrayMetrics.bottomScreenMargin
                - cutoutHeight - TrayMetrics.spacing
        )
        return low...max(low, high)
    }

    var title: String {
        switch self {
        case .compact: "Compact"
        case .spacious: "Spacious"
        case .custom: "Custom"
        }
    }

    var note: String {
        switch self {
        case .compact: "A narrow shelf that stays close to the housing."
        case .spacious: "The island's own width, with a little more room under it."
        case .custom: "Pick the width and height yourself."
        }
    }

    /// The width this preset asks for, before it is clamped to the display.
    /// `nil` for custom, which asks for whatever the user set.
    var preferredWidth: CGFloat? {
        switch self {
        case .compact: 480
        case .spacious: 560
        case .custom: nil
        }
    }

    static func clamped(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
}

/// Where the shelf's contents sit across its width.
///
/// Centred by default, which is what a shelf hanging off the middle of the
/// screen wants when it is holding three files. Left suits anyone who thinks
/// of it as a shelf that fills up from one end, and is steadier to aim at:
/// centred, every file moves when a new one lands.
nonisolated enum TrayAlignment: String, CaseIterable, Sendable {
    case leading
    case center
    case trailing

    var title: String {
        switch self {
        case .leading: "Left"
        case .center: "Centre"
        case .trailing: "Right"
        }
    }

    var note: String {
        switch self {
        case .leading: "Files fill the shelf from the left."
        case .center: "Files sit in the middle of the shelf."
        case .trailing: "Files fill the shelf from the right."
        }
    }
}

/// How big one item on the shelf is.
///
/// Derived from the two settings that change it, and passed down as one value
/// so that the layout, the views and the thumbnail cache cannot disagree about
/// how large a file is meant to be.
nonisolated struct TrayItemMetrics: Equatable, Sendable {
    var thumbnailSize: CGFloat
    var showsFilename: Bool

    static let `default` = TrayItemMetrics(
        thumbnailSize: TrayMetrics.defaultThumbnailSize,
        showsFilename: true
    )

    var itemWidth: CGFloat { thumbnailSize + TrayMetrics.itemLabelMargin }

    var itemHeight: CGFloat {
        thumbnailSize + (showsFilename ? TrayMetrics.labelSpacing + TrayMetrics.labelHeight : 0)
    }

    /// The shortest the shelf can be below the menu bar strip and still show
    /// what is on it: the row of files, plus the air underneath.
    var contentFloor: CGFloat { itemHeight + TrayMetrics.bottomInset }

    /// The tallest the shelf can get on a given display, used to size the
    /// window once rather than resizing it whenever a setting moves.
    ///
    /// With no bracket on a custom height, that is the display itself. The
    /// panel is transparent and hit-tests to nothing outside the shelf, so a
    /// tall one costs the pointer nothing — and a shelf the user asked to make
    /// half the screen tall has to have somewhere to be drawn.
    static func maximumExpandedHeight(screenHeight: CGFloat) -> CGFloat {
        let byContent = TrayItemMetrics(
            thumbnailSize: TrayMetrics.thumbnailSizeRange.upperBound,
            showsFilename: true
        ).contentFloor + TrayMetrics.spaciousExtra
        return max(byContent, screenHeight - TrayMetrics.bottomScreenMargin)
    }
}

/// The size of the tray surface for a given state and item count.
nonisolated struct TrayShape: Equatable {
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat

    /// How far the top corners draw in. The surface scales it down on a short
    /// shape, so the closed cutout keeps the same 14 as the open shelf.
    var shoulder: CGFloat = TrayMetrics.shoulder

    /// Where the files start: below the menu bar strip the header sits in.
    ///
    /// Nothing drawn under a real notch is visible — it is a hole in the
    /// display, not a dark rectangle — and on a display without one the shape
    /// still covers the menu bar. Either way the row of files starts under it,
    /// and the header is up in the strip alongside the menu bar's own items.
    var contentTop: CGFloat = 0

    /// How wide each now-playing wing is. Zero for every shape but the closed
    /// one that has grown them, which is how the window knows where the
    /// clickable parts of a closed shelf are (§74).
    var wingWidth: CGFloat = 0

    /// The island's radius expression, clamped so the closed cutout rounds
    /// like a cutout and the open shelf like a shelf without two constants
    /// having to agree.
    static func radius(forHeight height: CGFloat) -> CGFloat {
        min(TrayMetrics.cornerRadius, max(0, height) / 2)
    }

    static func collapsed(cutout: CGSize, isEmpty: Bool) -> TrayShape {
        // Empty and closed, the surface contracts all the way down to a
        // handle rather than sitting there as a small black slab (§77).
        if isEmpty {
            return TrayShape(
                width: TrayMetrics.handleWidth,
                height: TrayMetrics.handleHeight,
                cornerRadius: TrayMetrics.handleHeight / 2,
                shoulder: 0
            )
        }

        // Closed, the tray is the housing: the real cutout on a notched Mac,
        // the island's recreation of it anywhere else.
        return TrayShape(
            width: cutout.width,
            height: cutout.height,
            cornerRadius: radius(forHeight: cutout.height)
        )
    }

    /// Closed, with Cue playing: the housing with a wing either side.
    ///
    /// The same surface growing wider, never a second one beside it (§16), so
    /// the morph from the plain cutout to this and back is one continuous
    /// change of width. It starts from the housing even when the shelf is
    /// empty: wings hung off a 56 × 5 handle would be wings hung off nothing.
    static func nowPlaying(cutout: CGSize) -> TrayShape {
        let wing = TrayMetrics.wingWidth(forHeight: cutout.height)
        return TrayShape(
            width: cutout.width + wing * 2,
            height: cutout.height,
            cornerRadius: radius(forHeight: cutout.height),
            wingWidth: wing
        )
    }

    /// The two wings, in an unflipped view's coordinates, for a shape hanging
    /// from `top` and centred on `midX`. Empty when the shape has none.
    ///
    /// These are what the cover and the mark are clicked through, so the
    /// window keeps them live while closed and keeps them out of the hover
    /// strip — reaching for the mark must not open the shelf (§74, §75).
    ///
    /// Each stops at the body's outer wall, not the shape's outer edge: the
    /// outermost shoulder's width is where the surface draws in over the
    /// bezel and the menu bar shows through, and a click there was aimed at
    /// whatever sits beside the notch.
    func wingRects(centredOn midX: CGFloat, top: CGFloat) -> [CGRect] {
        guard wingWidth > 0 else { return [] }
        let shoulder = TrayMetrics.effectiveShoulder(forHeight: height)
        let minX = midX - width / 2
        let y = top - height
        let clickable = wingWidth - shoulder
        return [
            CGRect(x: minX + shoulder, y: y, width: clickable, height: height),
            CGRect(x: minX + width - wingWidth, y: y, width: clickable, height: height),
        ]
    }

    /// Width the shelf's items want, before any clamping.
    static func contentWidth(itemCount: Int, item: TrayItemMetrics) -> CGFloat {
        guard itemCount > 0 else { return 0 }
        return CGFloat(itemCount) * item.itemWidth
            + CGFloat(itemCount - 1) * TrayMetrics.itemSpacing
            + TrayMetrics.horizontalInset * 2
    }

    /// The open shelf's width for a size setting, clamped to this display.
    static func expandedWidth(
        screenWidth: CGFloat,
        cutoutWidth: CGFloat,
        size: TraySize,
        customWidth: Double
    ) -> CGFloat {
        let preferred = size.preferredWidth
            ?? TraySize.clamped(customWidth, to: TraySize.storable, fallback: TraySize.defaultWidth)
        // Never the full span: the shelf has to read as an object on the
        // screen rather than as a second menu bar (§20).
        return min(
            max(preferred, cutoutWidth + TrayMetrics.minimumSideRoom),
            max(1, screenWidth - TrayMetrics.screenMargin)
        )
    }

    /// Whether the items fit, or whether the shelf has to start scrolling (§20).
    static func fits(
        itemCount: Int,
        screenWidth: CGFloat,
        cutoutWidth: CGFloat = 0,
        size: TraySize,
        customWidth: Double = TraySize.defaultWidth,
        item: TrayItemMetrics
    ) -> Bool {
        contentWidth(itemCount: itemCount, item: item)
            <= expandedWidth(
                screenWidth: screenWidth,
                cutoutWidth: cutoutWidth,
                size: size,
                customWidth: customWidth
            )
    }

    static func expanded(
        screenWidth: CGFloat,
        screenHeight: CGFloat = .greatestFiniteMagnitude,
        cutout: CGSize,
        size: TraySize,
        customWidth: Double = TraySize.defaultWidth,
        customHeight: Double = TraySize.defaultHeight,
        item: TrayItemMetrics = .default
    ) -> TrayShape {
        let width = expandedWidth(
            screenWidth: screenWidth,
            cutoutWidth: cutout.width,
            size: size,
            customWidth: customWidth
        )

        // The header occupies the housing's own strip, so the only thing the
        // content owes it is the gap underneath.
        let contentTop = cutout.height + TrayMetrics.spacing
        // The island's own sum: clearance for the housing, then the chrome,
        // then whatever the content needs, then Spacious's extra room.
        let floor = contentTop + item.contentFloor
        let preferred: CGFloat

        switch size {
        case .compact:
            preferred = floor
        case .spacious:
            preferred = floor + TrayMetrics.spaciousExtra
        case .custom:
            // Whatever was asked for, with two things it cannot ask for: less
            // room than the icons need — a shelf shorter than what it holds
            // would clip it — and more of the display than the clamp below
            // allows.
            let requested = TraySize.clamped(
                customHeight,
                to: TraySize.storable,
                fallback: TraySize.defaultHeight
            )
            preferred = max(contentTop + requested, floor)
        }

        let height = min(preferred, max(floor, screenHeight - TrayMetrics.bottomScreenMargin))

        return TrayShape(
            width: width,
            height: height,
            cornerRadius: radius(forHeight: height),
            contentTop: contentTop
        )
    }

    var size: CGSize { CGSize(width: width, height: height) }
}
