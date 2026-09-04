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

    let onOpen: (MusicItem) -> Void
    let onShowSettings: () -> Void
    /// The window has to be resized in AppKit, and only this view knows how
    /// many results there are to be resized around.
    let onHeightChange: (CGFloat) -> Void

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: CueLayout.sectionGap) {
            SearchBarView(
                text: $coordinator.query,
                isSearching: coordinator.isSearching,
                isFocused: $isSearchFocused,
                onClear: { coordinator.clearSearch() },
                onSettings: onShowSettings
            )

            content
        }
        .padding(CueLayout.outerPadding)
        .frame(width: CueLayout.panelWidth, height: height, alignment: .top)
        .background(surface)
        .clipShape(.rect(cornerRadius: CueLayout.cornerRadius))
        .overlay(
            // A hairline, not a border: on a translucent surface the edge is
            // what stops the panel dissolving into a bright desktop behind it.
            RoundedRectangle(cornerRadius: CueLayout.cornerRadius)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
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

    private var height: CGFloat {
        switch presenter.mode {
        case .grid: CueLayout.gridModeHeight
        case .results: CueLayout.resultsModeHeight(count: coordinator.results.count)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch presenter.mode {
        case .grid:
            if coordinator.isConnectedToAnything || settings.pinnedTiles.contains(where: { $0 != nil }) {
                SpeedDialGridView(
                    coordinator: coordinator,
                    presenter: presenter,
                    thumbnails: thumbnails,
                    onOpen: onOpen
                )
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
