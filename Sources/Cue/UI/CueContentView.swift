import SwiftUI

/// Everything inside the panel.
///
/// The panel is one of two things at any moment — a speed dial, or a list of
/// search results — and which one is decided by whether the search field has
/// anything in it. There is no mode switch and no tab bar, because there is no
/// third possibility and typing is already the gesture that means "not the
/// grid".
struct CueContentView: View {
    @Bindable var coordinator: LibraryCoordinator
    let presenter: CuePresenter
    let thumbnails: ThumbnailProvider
    let settings: SettingsStore
    let player: PlayerService

    let onOpen: (MusicItem) -> Void
    let onShowSettings: () -> Void
    /// Raised by the disc: bring the player window up on what is playing.
    let onOpenPlayer: () -> Void
    /// The window has to be resized in AppKit, and only this view knows how
    /// many results there are to be resized around.
    let onHeightChange: (CGFloat) -> Void

    /// Arranging state: the panel is being positioned and sized rather than
    /// used, so it takes drags instead of clicks.
    let isEditing: Bool
    /// Told only that a drag moved or ended. Where the pointer is comes from
    /// the screen, not from the gesture — a translation measured relative to a
    /// window that is itself being moved oscillates.
    let onDragMove: (Bool) -> Void
    let onDragResize: (Bool, Bool) -> Void

    @FocusState private var isSearchFocused: Bool

    /// Read from settings rather than from `CueLayout`'s stored value, so the
    /// size slider re-renders everything that depends on it. A static is
    /// invisible to SwiftUI, which is why moving the slider used to resize the
    /// window and leave the contents at their old size.
    private var panelWidth: CGFloat { CGFloat(settings.panelWidth) }

    var body: some View {
        VStack(spacing: CueLayout.sectionGap) {
            SearchBarView(
                text: $coordinator.query,
                isSearching: coordinator.isSearching,
                isFocused: $isSearchFocused,
                onClear: { coordinator.clearSearch() },
                onSettings: onShowSettings,
                nowPlaying: player.nowPlaying,
                onOpenPlayer: onOpenPlayer
            )

            content
        }
        .padding(CueLayout.outerPadding)
        .frame(width: panelWidth, height: height, alignment: .top)
        .background(surface)
        .clipShape(.rect(cornerRadius: CueLayout.cornerRadius))
        .overlay(
            // A hairline, not a border: on a translucent surface the edge is
            // what stops the panel dissolving into a bright desktop behind it.
            RoundedRectangle(cornerRadius: CueLayout.cornerRadius)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .overlay { if isEditing { editChrome } }
        .scaleEffect(isPresented ? 1 : CueAnimation.startScale)
        .offset(y: isPresented ? 0 : CueAnimation.startOffset)
        .opacity(isPresented ? 1 : 0)
        .animation(isPresented ? CueAnimation.present : CueAnimation.dismiss, value: isPresented)
        .animation(CueAnimation.resize, value: height)
        .onAppear {
            isSearchFocused = true
            sync()
        }
        .onChange(of: presenter.state) { _, state in
            // Re-presenting reuses the same hosting view, so focus has to be
            // asked for again — the panel was ordered out, and the field's
            // first responder status went with it.
            guard state == .visible else { return }
            isSearchFocused = true
            sync()
        }
        .onChange(of: coordinator.query) { _, _ in sync() }
        .onChange(of: coordinator.results.count) { _, _ in sync() }
        .onChange(of: height) { _, height in onHeightChange(height) }
        // Belt and braces for the arrow keys.
        //
        // `CueWindowController`'s event monitor should get these first and
        // consume them, in which case nothing here ever runs. It reportedly
        // does not, and rather than guess a fourth time at why, this handles
        // them through SwiftUI's own focus system as well — which only sees a
        // key the monitor declined to take.
        .onKeyPress(.leftArrow) { horizontal(-1) }
        .onKeyPress(.rightArrow) { horizontal(1) }
    }

    /// Left and Right: pages in the gallery, selection in the compact grid.
    ///
    /// Here rather than in the window controller's event monitor, which never
    /// received these keys at all — the arrows did nothing until this existed.
    private func horizontal(_ offset: Int) -> KeyPress.Result {
        guard presenter.mode == .grid, !isEditing else { return .ignored }

        if settings.panelDesign == .gallery {
            presenter.movePage(by: offset)
        } else {
            presenter.moveSelection(by: offset)
        }
        return .handled
    }

    /// Brings the presenter in line with what is actually in the search field.
    ///
    /// Called on appearance as well as on change, deliberately. Mode is a
    /// *function* of the query, not a running total of the times it changed —
    /// and a query that was already set before this view appeared (restored
    /// state, a debug switch, anything set from outside) would otherwise leave
    /// the panel showing a grid while the field says something else.
    private func sync() {
        presenter.setMode(
            coordinator.query.trimmingCharacters(in: .whitespaces).isEmpty ? .grid : .results
        )
        presenter.setSelectableCount(
            presenter.mode == .grid ? SettingsStore.tileCount : coordinator.results.count
        )
        onHeightChange(height)
    }

    private var isPresented: Bool { presenter.state == .visible }

    /// What the panel wears while it is being arranged.
    ///
    /// A layer over the whole surface, deliberately: in this mode the panel is
    /// the thing being moved rather than a thing being used, and leaving the
    /// tiles clickable underneath would mean a mis-aimed drag starts a song.
    @ViewBuilder
    private var editChrome: some View {
        ZStack(alignment: .trailing) {
            Color.white.opacity(0.001)
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { _ in onDragMove(false) }
                        .onEnded { _ in onDragMove(true) }
                )

            // The grabber sits on the edge it resizes, which is the only place
            // it can be without needing a label to explain itself.
            Capsule()
                .fill(CuePalette.accent)
                .frame(width: 5, height: 56)
                .padding(.trailing, 4)
                // Inside a wider transparent strip, because the hit area of a
                // five-point capsule at the very edge would be clipped by the
                // panel it sits in — leaving a control that can be seen and not
                // grabbed.
                .frame(width: 26, height: 80)
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { _ in
                            onDragResize(NSEvent.modifierFlags.contains(.shift), false)
                        }
                        .onEnded { _ in
                            onDragResize(NSEvent.modifierFlags.contains(.shift), true)
                        }
                )
                .help("Drag to resize · hold ⇧ for steps")
        }
        .overlay(
            RoundedRectangle(cornerRadius: CueLayout.cornerRadius)
                .strokeBorder(CuePalette.accent.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        )
    }

    private var height: CGFloat {
        switch presenter.mode {
        case .grid:
            settings.panelDesign == .gallery
                ? CueLayout.galleryModeHeight(for: panelWidth)
                : CueLayout.gridModeHeight
        case .results:
            CueLayout.resultsModeHeight(count: coordinator.results.count)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch presenter.mode {
        case .grid:
            if coordinator.isConnectedToAnything || settings.pinnedTiles.contains(where: { $0 != nil }) {
                switch settings.panelDesign {
                case .gallery:
                    GalleryView(
                        coordinator: coordinator,
                        presenter: presenter,
                        thumbnails: thumbnails,
                        panelWidth: panelWidth,
                        onOpen: onOpen
                    )
                case .classic:
                    SpeedDialGridView(
                        coordinator: coordinator,
                        presenter: presenter,
                        thumbnails: thumbnails,
                        onOpen: onOpen
                    )
                }
            } else {
                DisconnectedView(onShowSettings: onShowSettings)
            }

        case .results:
            ResultsListView(
                coordinator: coordinator,
                presenter: presenter,
                thumbnails: thumbnails,
                onOpen: onOpen
            )
        }
    }

    /// The panel's surface.
    ///
    /// `.ultraThinMaterial` rather than a colour, so the panel takes its
    /// character from whatever is behind it — which over an album cover or a
    /// bright document is the difference between an overlay and a grey box.
    private var surface: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
    }
}

/// What the grid shows before anything is connected.
///
/// This is the whole of the first run, so it says the one thing that has to be
/// said and offers the one action that can be taken. No feature tour.
private struct DisconnectedView: View {
    let onShowSettings: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note.list")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)

            Text("Connect your YouTube account")
                .font(.system(size: 14, weight: .medium))

            Text("Cue needs a Google OAuth client ID to search and to see your playlists.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            Button("Open Settings", action: onShowSettings)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
