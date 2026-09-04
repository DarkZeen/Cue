import Foundation
import Observation

/// Whether the panel is on screen, and what it is in the middle of.
///
/// Four cases rather than an `isVisible` flag, because the two transitional
/// ones are real: a panel part-way through its dismissal is still on screen and
/// must not accept a click, and a shortcut pressed during that dismissal has to
/// re-present rather than queue up behind it.
enum CuePresentationState: Equatable {
    /// Not on screen. The window is ordered out.
    case hidden
    /// On screen and interactive.
    case visible
    /// On screen, animating away, no longer interactive.
    case dismissing
}

/// What the panel is showing below the search field.
enum CueMode: Equatable {
    case grid
    case results
}

/// The panel's own state: presentation, mode, and what the keyboard is
/// pointing at.
///
/// Kept apart from `LibraryCoordinator` on purpose. This has no idea what a
/// playlist is; it knows that there are `n` things and one of them is
/// highlighted. That separation is what lets the keyboard code be written once
/// and work for both the grid and the results list.
@Observable
final class CuePresenter {
    private(set) var state: CuePresentationState = .hidden
    private(set) var mode: CueMode = .grid

    /// The highlighted position, or `nil` when nothing is.
    ///
    /// Nothing highlighted is the correct state on opening: the panel appears
    /// with the caret in an empty field, and pre-selecting the first tile would
    /// mean Return plays something the user never looked at.
    private(set) var selection: Int?

    /// How many things are currently selectable. Set by the view as the
    /// contents change, because only the view knows how many rows survived a
    /// search.
    private(set) var selectableCount: Int = 0

    /// Which of the gallery's three pages is showing.
    private(set) var page: LibraryCoordinator.Page = .pinned

    private var dismissTask: Task<Void, Never>?

    /// Raised when the panel has finished animating out and the window can be
    /// ordered off screen.
    var onDismissed: (() -> Void)?

    var isInteractive: Bool { state == .visible }

    // MARK: - Presentation

    func present() {
        dismissTask?.cancel()
        dismissTask = nil
        selection = nil
        // Back to the speed dial every time. The panel is opened to reach one
        // of nine things kept in known positions, and arriving on whichever
        // page was last browsed would cost that certainty for no gain.
        page = .pinned
        state = .visible
    }

    /// Starts the dismissal. `onDismissed` follows once the animation is done.
    func dismiss() {
        guard state == .visible else { return }
        state = .dismissing

        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: CueAnimation.dismissDuration)
            guard !Task.isCancelled, let self else { return }
            self.state = .hidden
            self.onDismissed?()
        }
    }

    /// Ends the dismissal immediately, without waiting for the animation.
    /// Used when the panel is being torn down rather than closed.
    func dismissNow() {
        dismissTask?.cancel()
        dismissTask = nil
        state = .hidden
        onDismissed?()
    }

    // MARK: - Mode

    func setMode(_ mode: CueMode) {
        guard mode != self.mode else { return }
        self.mode = mode
        // The highlight belongs to a list that no longer exists. Carrying an
        // index across the change is how Return ends up opening the fourth
        // search result because the fourth tile was highlighted a moment ago.
        selection = nil
    }

    // MARK: - Pages

    func setPage(_ page: LibraryCoordinator.Page) {
        guard page != self.page else { return }
        self.page = page
        // The highlight belonged to nine other things. Carrying the index
        // across is how Return opens the fourth album because the fourth liked
        // song was highlighted a moment ago.
        selection = nil
    }

    /// Moves by whole pages, clamped.
    ///
    /// Not wrapped: three pages held under an arrow key would cycle forever,
    /// and "go to the last page" stops being something you can do by feel.
    func movePage(by offset: Int) {
        let pages = LibraryCoordinator.Page.allCases
        let target = min(max(page.rawValue + offset, 0), pages.count - 1)
        setPage(pages[target])
    }

    // MARK: - Selection

    func setSelectableCount(_ count: Int) {
        selectableCount = count
        if let selection, selection >= count {
            // The list shrank underneath the highlight — another keystroke
            // narrowed the search. Clamping rather than clearing keeps the
            // arrow keys usable while typing.
            self.selection = count > 0 ? count - 1 : nil
        }
    }

    func select(_ index: Int?) {
        guard let index else {
            selection = nil
            return
        }
        guard (0..<selectableCount).contains(index) else { return }
        selection = index
    }

    /// Moves the highlight by `offset`, starting it if nothing is highlighted.
    ///
    /// Deliberately clamped rather than wrapped. Wrapping means holding Down
    /// takes you back to the top, which in a list this short is disorienting
    /// and makes "go to the last one" impossible to do by feel.
    func moveSelection(by offset: Int) {
        guard selectableCount > 0 else { return }

        guard let current = selection else {
            selection = offset > 0 ? 0 : selectableCount - 1
            return
        }

        selection = min(max(current + offset, 0), selectableCount - 1)
    }
}
