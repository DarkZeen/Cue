import AppKit
import SwiftUI

/// The tray itself (§5, §6, §14, §16, §19, §76, §77).
///
/// One surface, hanging from the top edge of the display, changing shape.
/// There is no branch here that swaps one view for another when the tray
/// opens — the container's width, height, shoulder and corner radius animate,
/// and the contents cross-fade inside it. That is what makes the open and
/// close read as a single object rather than two views trading places (§16).
///
/// Open, it is laid out the way the Dynamic Island lays itself out: a 36pt
/// header with the title on the left and its buttons on the right, 18pt of
/// air, then the content, inset 28pt from the sides and 22pt from the bottom,
/// all of it starting below the camera housing.
struct TrayContentView: View {
    let store: TrayStore
    let presenter: TrayPresenter
    let selection: TraySelection
    let thumbnails: FileThumbnailProvider
    let settings: ShelfSettingsStore
    let geometry: ScreenGeometry

    let onRemove: (TrayItem) -> Void
    let onCopy: ([TrayItem]) -> Void
    let onClick: (TrayItem, NSEvent.ModifierFlags) -> Void
    let onReveal: (TrayItem) -> Void
    let onQuickLook: (TrayItem) -> Void
    let onItemDragBegan: ([TrayItem]) -> Void
    let onItemDragEnded: ([TrayItem], Bool) -> Void

    /// The two commands the island keeps in its header menu.
    var onClearAll: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    /// Reported upward so the AppKit layer can keep its hit regions exactly on
    /// the pixels the user can see (§74).
    let onShapeChange: (TrayShape) -> Void

    /// Cue's music, for the wings the closed shelf grows while it plays.
    var nowPlaying: NowPlayingSource? = nil

    /// Whether this display is the one that shows them. Only one does — see
    /// `DisplayCoordinator` — so a double click likes a song once, and one
    /// mark animates rather than one per screen (§26).
    var showsNowPlaying = false

    /// The like heart currently in flight, if any. A fresh identity per like,
    /// so a second like while one is still drifting starts it over.
    @State private var heartBurst: UUID?

    /// The viewer's motion preference, read here rather than from a static, so
    /// that switching Reduce Motion takes effect immediately (§50).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            tray
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The tray keeps its own appearance rather than following the system's
        // (§49). Which one it keeps is now the user's choice.
        .environment(\.trayPalette, palette)
        .environment(\.trayMotion, motion)
        .environment(\.colorScheme, palette.colorScheme)
        // The island tints everything in it white and leaves the accent colour
        // out: a black cutout with a blue button in it is a panel again.
        .tint(palette.primaryInk)
    }

    // MARK: - The surface

    private var tray: some View {
        ZStack {
            // Each layer is pinned to the tray's exact size. Without this the
            // ZStack takes the size of its *largest* child — the open shelf —
            // and the closed layer's `maxHeight: .infinity` then resolves
            // against that instead of against the closed height, which lands
            // the item dots below the tray entirely.
            collapsedContents
                .frame(width: shape.width, height: shape.height)
                .opacity(isOpen ? 0 : 1)
                // The faded layer stays in the hierarchy; it must not keep
                // catching clicks meant for the one on show.
                .allowsHitTesting(!isOpen)

            expandedContents
                .frame(width: shape.width, height: shape.height)
                .opacity(isOpen ? 1 : 0)
                .allowsHitTesting(isOpen)
        }
        .frame(width: shape.width, height: shape.height)
        // Nothing escapes the surface. As well as being correct at rest, this
        // is what makes the collapse read as the shelf closing over its
        // contents rather than the contents sliding out of a shrinking box.
        .clipShape(TraySurface(cornerRadius: shape.cornerRadius, shoulder: shape.shoulder))
        .traySurface(
            cornerRadius: shape.cornerRadius,
            shoulder: shape.shoulder,
            isEmphasised: presenter.state.isDropTargetActive,
            showsDropOutline: settings.showsDropOutline && isOpen,
            dropOutlineInset: settings.dropOutlineInset,
            contentTop: shape.contentTop
        )
        // On the outline, after the clip: half the line falls outside the
        // surface, which is what lets it frame the pill under the housing.
        .overlay { partyBorder }
        // After the clip, so the heart can leave the cover — leaving it is the
        // whole gesture.
        .overlay(alignment: .topLeading) { likeHeart }
        // Scaled from the top, because that is where the object is attached.
        // Scaling from the centre would lift it off the edge of the screen.
        .scaleEffect(presenter.containerScale, anchor: .top)
        .animation(containerAnimation, value: shape)
        .animation(motion.appearance, value: palette)
        .animation(motion.hover, value: presenter.state)
        // Anticipation as a drag approaches (§13), and the give as one lands
        // (§46). Both are scale changes on the same property, so they get their
        // own springs rather than borrowing the pointer's.
        .animation(motion.hover, value: presenter.isDragApproaching)
        .animation(motion.dropImpact, value: presenter.isAbsorbingDrop)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .onChange(of: shape, initial: true) { _, new in onShapeChange(new) }
    }

    /// Party mode, round the closed pill only — never the open shelf.
    @ViewBuilder
    private var partyBorder: some View {
        if arrival != nil, nowPlaying?.arrivalOutline() ?? true {
            // Headphones arriving: the outline in green, whatever the party.
            ArrivalBorder(cornerRadius: shape.cornerRadius, shoulder: shape.shoulder)
                .transition(.opacity)
        } else if let nowPlaying, let track = pillTrack, nowPlaying.party() > 0 {
            PartyBorder(
                source: nowPlaying,
                cornerRadius: shape.cornerRadius,
                shoulder: shape.shoulder,
                isPlaying: track.isPlaying,
                intensity: nowPlaying.party()
            )
            .transition(.opacity)
        }
    }

    private var palette: TrayPalette { settings.appearance.palette }

    /// How large the files are drawn and how much room they get around them.
    private var contentMetrics: TrayItemMetrics { settings.itemMetrics }

    /// Where the contents sit across the shelf, vertically centred either way.
    private var contentAlignment: Alignment {
        switch settings.contentAlignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private var motion: TrayMotion { TrayMotion(reduceMotion: reduceMotion) }

    private var isOpen: Bool { presenter.state.isOpen }

    /// The camera housing this display has, or the island's recreation of one.
    private var cutout: CGSize {
        TrayMetrics.cutout(
            notchSize: geometry.notchSize,
            menuBarHeight: geometry.menuBarHeight,
            screenWidth: geometry.frame.width
        )
    }

    private var shape: TrayShape {
        if isOpen {
            var open = TrayShape.expanded(
                screenWidth: geometry.frame.width,
                screenHeight: geometry.usableHeight,
                cutout: cutout,
                size: settings.traySize,
                customWidth: settings.customWidth,
                customHeight: settings.customHeight,
                item: contentMetrics
            )
            // While Cue plays, the header carries the cover and its buttons
            // beside the housing, so the shelf is never narrower than they
            // need — whatever size it was set to. Never past the display.
            if headerTrack != nil {
                let needed = cutout.width
                    + 2 * (settings.headerInset
                        + ShelfPlayerControls.width(band: cutout.height, buttonSize: headerButton)
                        + TrayMetrics.headerGap)
                open.width = min(max(open.width, needed), geometry.frame.width - 24)
            }
            return open
        }
        if pillTrack != nil || arrival != nil {
            return .nowPlaying(cutout: cutout)
        }
        return .collapsed(cutout: cutout, isEmpty: store.isEmpty)
    }

    /// The track the closed shelf's wings are about, when it has them.
    ///
    /// Reads the player through the source, which is a dependency SwiftUI
    /// tracks — so music starting or stopping reshapes the shelf. Only the
    /// track: the audio level is read further down, in the mark itself.
    /// The track the open shelf's header plays, on the display that shows
    /// what is playing.
    private var headerTrack: NowPlayingSource.Track? {
        guard showsNowPlaying, let nowPlaying else { return nil }
        return nowPlaying.track()
    }

    private var pillTrack: NowPlayingSource.Track? {
        guard !isOpen, showsNowPlaying, let nowPlaying else { return nil }
        return nowPlaying.track()
    }

    /// Headphones that just arrived, which the closed shelf's wings show for
    /// a few seconds — in place of the music, if any is playing.
    private var arrival: HeadphonesWatcher.Arrival? {
        guard !isOpen, showsNowPlaying, let nowPlaying else { return nil }
        return nowPlaying.arrival()
    }

    /// Opening and closing get different springs: leaving should feel calmer
    /// than arriving (§45).
    private var containerAnimation: Animation {
        isOpen ? motion.expand : motion.collapse
    }

    // MARK: - Closed

    /// Closed, the tray says only whether it is holding anything (§76, §77) —
    /// and, while Cue plays, what is playing, in a wing either side of the
    /// housing.
    @ViewBuilder
    private var collapsedContents: some View {
        Group {
            closedWings
        }
        // The hand-over between headphones and music: one set sinks into
        // the notch, the next comes out of it (`AnyTransition.wings`).
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .easeInOut(duration: 0.55), value: arrival?.id)
    }

    @ViewBuilder
    private var closedWings: some View {
        if let arrival {
            ArrivalWings(arrival: arrival, cutout: cutout) {
                itemDots
            }
            .transition(.wings(reduceMotion: reduceMotion))
        } else if let nowPlaying, let track = pillTrack {
            NowPlayingWings(
                source: nowPlaying,
                track: track,
                cutout: cutout,
                onLike: { heartBurst = UUID() }
            ) {
                itemDots
            }
            .transition(.wings(reduceMotion: reduceMotion))
        } else {
            itemDots
        }
    }

    /// Whether the shelf is holding anything, as up to three dots and a count.
    @ViewBuilder
    private var itemDots: some View {
        if !store.isEmpty {
            HStack(spacing: 4) {
                ForEach(0..<min(store.count, 3), id: \.self) { _ in
                    Circle()
                        .fill(palette.ink(0.55))
                        .frame(width: 4, height: 4)
                }
                if store.count > 3 {
                    Text("\(store.count)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.ink(0.55))
                        .padding(.leading, 1)
                }
            }
            .padding(.bottom, geometry.hasNotch ? 4 : 0)
            .frame(maxHeight: .infinity, alignment: geometry.hasNotch ? .bottom : .center)
        }
    }

    /// The heart that springs out of the cover on a like, centred on the
    /// cover and drawn over the surface rather than inside it.
    @ViewBuilder
    private var likeHeart: some View {
        if let burst = heartBurst, shape.wingWidth > 0 {
            let height = cutout.height
            LikeHeart(reduceMotion: reduceMotion) {
                // Only the heart that is still showing may clear itself; an
                // older one finishing must not take a newer one with it.
                if heartBurst == burst { heartBurst = nil }
            }
            .id(burst)
            .position(
                x: TrayMetrics.effectiveShoulder(forHeight: height)
                    + TrayMetrics.wingPadding(forHeight: height)
                    + TrayMetrics.wingArtSize(forHeight: height) / 2,
                y: height / 2
            )
        }
    }

    // MARK: - Open

    /// The header in the menu bar strip, the files under it.
    ///
    /// Two insets, not one: the header is pushed out to the walls so the name
    /// and the buttons line up with the menu bar items either side of the
    /// shelf, and the content stays on the island's 28 so the files sit inside
    /// that frame rather than queueing up alongside it.
    private var expandedContents: some View {
        VStack(spacing: 0) {
            header
                // Exactly the housing's own strip, so the header's contents
                // land on the same line as the menu bar's.
                .frame(height: cutout.height)
                .padding(.horizontal, settings.headerInset)
                .zIndex(1)

            content
                .padding(.horizontal, TrayMetrics.horizontalInset)
                .padding(.top, TrayMetrics.spacing)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.bottom, TrayMetrics.bottomInset)
    }

    /// What is playing in one corner, the way out in the other, both on the
    /// menu bar's own line.
    ///
    /// No name and no logo: the shelf is the top of the screen, and what it
    /// says first is the music — the cover and its three buttons, the closed
    /// shelf's wings opened out. With nothing playing, the corner holds only
    /// how many files there are. The chevron closes, and the gear sits
    /// outermost because Settings is the thing people go looking for there.
    private var header: some View {
        HStack(spacing: 6) {
            if let nowPlaying, let track = headerTrack {
                ShelfPlayerControls(
                    source: nowPlaying,
                    track: track,
                    band: cutout.height,
                    buttonSize: headerButton
                )
            } else if !store.isEmpty {
                Text("\(store.count)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(palette.ink(0.55))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .trayControlSurface(cornerRadius: 8)
                    .accessibilityHidden(true)
            }

            Spacer(minLength: 8)

            TrayIconButton(symbol: "chevron.up", title: "Close", size: headerButton) {
                presenter.collapseNow()
            }

            Menu {
                Button("Clear the Shelf", action: onClearAll)
                    .disabled(store.isEmpty)
                Divider()
                Button("Settings…", action: onOpenSettings)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.ink(0.55))
                    .frame(width: headerButton, height: headerButton)
                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Settings and shelf options")
            .help("Settings and shelf options")
        }
    }

    /// How big the header's buttons can be in this Mac's menu bar.
    private var headerButton: CGFloat {
        TrayMetrics.headerButtonSize(inBand: cutout.height)
    }

    @ViewBuilder
    private var content: some View {
        if store.isEmpty {
            emptyPrompt
        } else {
            shelf
        }
    }

    /// No permanent onboarding screen (§5). The prompt exists only while the
    /// tray is open and empty, and it changes to an instruction only once a
    /// drag is actually overhead.
    private var emptyPrompt: some View {
        TrayEmptyState(
            // The outline variant, not the filled one: filled, it reads as a
            // small white button sitting in the shelf, which is the plate the
            // empty state just lost.
            symbol: presenter.state.isDropTargetActive
                ? "arrow.down.circle"
                : "tray.and.arrow.down",
            isLit: presenter.state.isDropTargetActive,
            // The prompt stands where the files will, so a left-aligned shelf
            // does not point at the middle and then fill from the edge.
            alignment: contentAlignment
        )
        .animation(motion.hover, value: presenter.state)
    }

    /// A horizontal shelf, never a grid (§19).
    ///
    /// The scroll view appears only once the items stop fitting (§20). While
    /// everything fits — which is nearly always — the row is laid out plainly,
    /// so there is no scroll offset to end up in the wrong place and no chance
    /// of a stray trackpad gesture nudging the shelf sideways.
    @ViewBuilder
    private var shelf: some View {
        if fitsWithoutScrolling {
            itemRow.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: contentAlignment)
        } else {
            ScrollView(.horizontal) {
                itemRow
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: .infinity)
            // Content dissolves at the edges instead of being cut off mid-icon.
            // A hard edge reads as a rendering mistake; a fade reads as "there
            // is more this way".
            .mask(scrollEdgeMask)
        }
    }

    private var fitsWithoutScrolling: Bool {
        TrayShape.fits(
            itemCount: store.count,
            screenWidth: geometry.frame.width,
            cutoutWidth: cutout.width,
            size: settings.traySize,
            customWidth: settings.customWidth,
            item: contentMetrics
        )
    }

    private var itemRow: some View {
        HStack(spacing: TrayMetrics.itemSpacing) {
            ForEach(store.items) { item in
                TrayItemView(
                    item: item,
                    thumbnails: thumbnails,
                    metrics: contentMetrics,
                    isBeingDragged: presenter.state.draggedItemIDs.contains(item.id),
                    isSelected: selection.contains(item.id),
                    dragTargets: { selectionTargets(for: item) },
                    onDragBegan: onItemDragBegan,
                    onDragEnded: onItemDragEnded,
                    onRemove: { onRemove(item) },
                    onReveal: { onReveal(item) },
                    onQuickLook: { onQuickLook(item) },
                    onClick: { onClick(item, $0) },
                    onCopy: { onCopy(selectionTargets(for: item)) }
                )
                .transition(motion.itemTransition)
            }
        }
        .animation(motion.itemShift, value: store.items.map(\.id))
    }

    private var scrollEdgeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: TrayMetrics.scrollFade / shape.width),
                .init(color: .black, location: 1 - TrayMetrics.scrollFade / shape.width),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// Which items an action on `item` applies to.
    ///
    /// The whole selection when this item is part of it, just this one when it
    /// is not — the same rule Finder uses, so acting on an item never silently
    /// narrows or widens what you picked. Copy and drag share it: a selection
    /// of five that copies five but drags one is the kind of inconsistency
    /// nobody can predict.
    private func selectionTargets(for item: TrayItem) -> [TrayItem] {
        guard selection.contains(item.id) else { return [item] }
        return selection.items(from: store.items)
    }

    private var accessibilityLabel: String {
        store.isEmpty
            ? "Shelf, empty"
            : "Shelf containing \(store.count) item\(store.count == 1 ? "" : "s")"
    }
}
