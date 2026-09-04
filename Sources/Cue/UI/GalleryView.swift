import SwiftUI

/// The redesigned grid: three pages of artwork, one at a time.
///
/// Paged rather than scrolled. A scroll has no positions — the thing you want
/// is wherever you last left the scroller — and positions are the entire reason
/// the speed dial is fast. Three pages of nine keep ⌘1 to ⌘9 meaning something,
/// and the dots say which nine you are looking at.
struct GalleryView: View {
    let coordinator: LibraryCoordinator
    let presenter: CuePresenter
    let thumbnails: ThumbnailProvider
    /// Everything in here is sized from this, so a change to it re-lays the
    /// whole gallery out.
    let panelWidth: CGFloat
    let onOpen: (MusicItem) -> Void

    private var side: CGFloat { CueLayout.Gallery.tileSide(for: panelWidth) }
    private var pageWidth: CGFloat { CueLayout.Gallery.pageWidth(for: panelWidth) }
    private var gridHeight: CGFloat { CueLayout.Gallery.gridHeight(for: panelWidth) }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: CueLayout.Gallery.headerHeight)

            Spacer(minLength: 6)

            pages
                .frame(height: gridHeight)

            Spacer(minLength: 8)

            dots
                .frame(height: CueLayout.Gallery.dotsHeight)
        }
        .onAppear {
            presenter.setSelectableCount(SettingsStore.tileCount)
            coordinator.refresh()
            prefetchNeighbours()
        }
        .onChange(of: presenter.page) { _, _ in prefetchNeighbours() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text(presenter.page.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                // Keyed on the page so the title crossfades with the slide
                // rather than surviving it unchanged, which would read as the
                // grid moving underneath a label that did not.
                .id(presenter.page)
                .transition(.opacity)

            Spacer()

            if presenter.page.canReshuffle {
                Button {
                    coordinator.reshuffle(presenter.page)
                    presenter.select(nil)
                } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                // Shown but disabled when the page holds nine or fewer: a
                // control that vanishes leaves you wondering whether the
                // feature exists, and one that is visibly unavailable tells you
                // there is simply nothing else to deal.
                .disabled(!coordinator.canReshuffle(presenter.page))
                .opacity(coordinator.canReshuffle(presenter.page) ? 1 : 0.35)
                .help(
                    coordinator.canReshuffle(presenter.page)
                        ? "Show a different nine  ⌘R"
                        : "Everything on this page already fits"
                )
                .accessibilityLabel("Show a different nine")
            }
        }
        .animation(.easeOut(duration: 0.16), value: presenter.page)
    }

    // MARK: - Pages

    /// All three pages side by side, slid into place.
    ///
    /// A real strip rather than a swapped view, so the movement between pages
    /// is the pages moving. A crossfade would say the content changed; a slide
    /// says you went somewhere, which is what the dots are already promising.
    private var pages: some View {
        HStack(spacing: 0) {
            ForEach(LibraryCoordinator.Page.allCases, id: \.self) { page in
                grid(for: page)
                    .frame(width: pageWidth)
            }
        }
        .offset(x: -CGFloat(presenter.page.rawValue) * pageWidth)
        .frame(width: pageWidth, alignment: .leading)
        .clipped()
        .animation(CueAnimation.page, value: presenter.page)
    }

    private func grid(for page: LibraryCoordinator.Page) -> some View {
        let tiles = coordinator.tiles(for: page)
        let isEmpty = tiles.allSatisfy { $0 == nil }

        return ZStack {
            VStack(spacing: CueLayout.Gallery.tileSpacing) {
                ForEach(0..<CueLayout.gridRows, id: \.self) { row in
                    HStack(spacing: CueLayout.Gallery.tileSpacing) {
                        ForEach(0..<CueLayout.gridColumns, id: \.self) { column in
                            let index = row * CueLayout.gridColumns + column
                            ArtworkTileView(
                                item: tiles.indices.contains(index) ? tiles[index] : nil,
                                index: index,
                                isSelected: presenter.page == page && presenter.selection == index,
                                isPinned: page == .pinned && coordinator.isPinned(at: index),
                                // Numbered outlines belong to the speed dial,
                                // where an empty slot is a place you can fill.
                                // On a page Cue fills for you, nine dashed
                                // rectangles would just be nine absences.
                                showsEmptySlots: page == .pinned,
                                side: side,
                                thumbnails: thumbnails,
                                onOpen: {
                                    guard let item = tiles[index] else { return }
                                    onOpen(item)
                                },
                                onPin: {
                                    guard let item = tiles[index] else { return }
                                    coordinator.pinToFirstFreeSlot(item)
                                },
                                onUnpin: { coordinator.unpin(at: index) }
                            )
                        }
                    }
                }
            }
            .opacity(isEmpty && page != .pinned ? 0 : 1)

            if isEmpty && page != .pinned {
                Text(page.emptyMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
        }
    }

    // MARK: - Dots

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(LibraryCoordinator.Page.allCases, id: \.self) { page in
                let isCurrent = presenter.page == page

                Capsule()
                    .fill(isCurrent ? AnyShapeStyle(CuePalette.accent) : AnyShapeStyle(.quaternary))
                    // The current page's dot stretches rather than merely
                    // brightening, so which page you are on survives being seen
                    // out of the corner of the eye.
                    .frame(width: isCurrent ? 16 : 6, height: 6)
                    .contentShape(.rect.inset(by: -6))
                    .onTapGesture { presenter.setPage(page) }
                    .accessibilityLabel(page.title)
                    .accessibilityAddTraits(isCurrent ? [.isSelected, .isButton] : .isButton)
            }
        }
        .animation(CueAnimation.page, value: presenter.page)
        .help("← and → move between pages")
    }

    /// Warms the artwork on the pages either side of this one.
    ///
    /// Paging is the fastest interaction in the panel — a keypress — and a page
    /// that arrives as nine grey rectangles and fills in afterwards feels
    /// slower than the keypress was.
    private func prefetchNeighbours() {
        for page in LibraryCoordinator.Page.allCases {
            for tile in coordinator.tiles(for: page) {
                thumbnails.prefetch(tile?.thumbnailURL)
            }

            // And the rest of the pool, because Shuffle deals from all of it.
            // Fetching only what is on screen means every redeal starts with
            // nine grey rectangles — the one interaction that should feel
            // instant, waiting on the network.
            for item in coordinator.pool(for: page).prefix(48) {
                thumbnails.prefetch(item.thumbnailURL)
            }
        }
    }
}
