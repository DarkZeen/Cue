import AppKit
import Foundation
import Observation

/// The one thing the interface talks to.
///
/// Two backends go in, one list comes out. Everything above this line — the
/// search field, the grid, the results — is written as though there were a
/// single source of music, which is what makes the unofficial provider
/// something that can be switched off without a redesign.
@Observable
final class LibraryCoordinator {
    /// Long enough that typing a word is one request rather than five, short
    /// enough that it still feels like the results are keeping up. It matters
    /// more here than in most search fields: a Data API `search.list` call
    /// costs a hundredth of the day's quota, so a request per keystroke would
    /// exhaust an account in a couple of minutes of typing.
    private static let searchDebounce = Duration.milliseconds(280)

    let google: GoogleOAuthService
    let ytSession: YTMusicSessionService

    private let settings: SettingsStore
    private let dataAPI: YouTubeDataAPIProvider
    private let ytMusic: YTMusicInternalProvider
    private let logger = Diagnostics.logger("library")

    /// What is in the search field. Assigning it schedules a search.
    var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            scheduleSearch()
        }
    }

    private(set) var results: [MusicItem] = []
    private(set) var isSearching = false
    /// Set when something the user should know about went wrong. Deliberately
    /// one string: the panel has room for one line, and a list of per-provider
    /// failures is a diagnostic, not a message.
    private(set) var message: String?

    /// Library and recents, kept for filling empty tiles. Refreshed when the
    /// panel opens rather than on a timer — the panel is open for seconds at a
    /// time, and a background poll would spend quota on nobody.
    private(set) var suggestions: [MusicItem] = []

    /// The grid's second page: liked songs, as individual tracks.
    private(set) var likedSongs: [MusicItem] = []
    /// The grid's third page: saved albums, as containers.
    private(set) var albums: [MusicItem] = []

    private(set) var isRefreshing = false

    private var searchTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var lastRefresh: Date?

    init(settings: SettingsStore) {
        self.settings = settings

        let google = GoogleOAuthService()
        let ytSession = YTMusicSessionService()

        self.google = google
        self.ytSession = ytSession
        self.dataAPI = YouTubeDataAPIProvider(auth: google)
        self.ytMusic = YTMusicInternalProvider(session: ytSession)

        ytSession.onSessionChange = { [weak self] in
            self?.refresh(force: true)
        }
    }

    // MARK: - Providers

    /// Whichever backends are both switched on and usable, in the order their
    /// results should be trusted.
    ///
    /// The internal provider comes first when it is available because its
    /// answers are simply better for this app's purpose: it knows a song from
    /// a video, it has the artist and the album, and its library is the Music
    /// library rather than the YouTube one. The official provider is the floor,
    /// not the ceiling.
    private var activeProviders: [any MusicLibraryProvider] {
        var providers: [any MusicLibraryProvider] = []
        if settings.unofficialProviderEnabled, ytMusic.isConnected { providers.append(ytMusic) }
        if dataAPI.isConnected { providers.append(dataAPI) }
        return providers
    }

    var isConnectedToAnything: Bool { !activeProviders.isEmpty }

    /// What Settings needs to explain the current state, and what the empty
    /// panel needs to say instead of nothing.
    var connectionSummary: String {
        switch (dataAPI.isConnected, settings.unofficialProviderEnabled && ytMusic.isConnected) {
        case (true, true): "YouTube account and YouTube Music session"
        case (true, false): "YouTube account"
        case (false, true): "YouTube Music session"
        case (false, false): "Not connected"
        }
    }

    // MARK: - Search

    private func scheduleSearch() {
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // Clearing the field goes back to the grid immediately. Waiting
            // out a debounce to show something the user already asked to stop
            // seeing is the wrong way round.
            results = []
            isSearching = false
            message = nil
            return
        }

        isSearching = true

        searchTask = Task { [weak self] in
            try? await Task.sleep(for: Self.searchDebounce)
            guard !Task.isCancelled, let self else { return }
            await self.performSearch(trimmed)
        }
    }

    private func performSearch(_ query: String) async {
        let providers = activeProviders
        guard !providers.isEmpty else {
            results = []
            isSearching = false
            message = "Connect an account in Settings to search."
            return
        }

        var merged: [MusicItem] = []
        var failures: [MusicLibraryError] = []

        // Sequential rather than concurrent, deliberately. The providers are
        // ordered by how much their answers are worth, and merging preserves
        // that order; running them in parallel would save a few hundred
        // milliseconds and then need the order restored anyway.
        for provider in providers {
            guard !Task.isCancelled else { return }
            do {
                merged = Self.merge(merged, with: try await provider.search(query))
            } catch let error as MusicLibraryError {
                logger.notice("\(provider.id.rawValue, privacy: .public) search failed: \(error.localizedDescription, privacy: .public)")
                failures.append(error)
            } catch {
                failures.append(.transport(error))
            }
        }

        guard !Task.isCancelled else { return }

        results = merged
        isSearching = false
        // A failure only becomes a message when it left the user with nothing.
        // One backend being down while the other answers is not something to
        // interrupt a search with.
        message = merged.isEmpty ? failures.first?.localizedDescription : nil
    }

    /// Adds the second list to the first, dropping anything already there.
    ///
    /// De-duplication is by content rather than by id, because the same song
    /// found through both backends has two different ids by construction —
    /// and showing it twice, once with the artist's name and once without, is
    /// the most obvious possible symptom of a merged search.
    static func merge(_ existing: [MusicItem], with incoming: [MusicItem]) -> [MusicItem] {
        var output = existing
        for item in incoming {
            guard !output.contains(where: { $0.isSameContent(as: item) }) else { continue }
            output.append(item)
        }
        return output
    }

    // MARK: - Library

    /// Reloads the library and recents behind the grid.
    ///
    /// Rate-limited to once a minute unless forced: the panel is opened often
    /// and briefly, and refetching a playlist list on every keystroke-sized
    /// visit is how an app becomes the reason someone's quota ran out.
    func refresh(force: Bool = false) {
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < 60 { return }
        guard !activeProviders.isEmpty else {
            suggestions = []
            return
        }

        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.performRefresh()
        }
    }

    private func performRefresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        var gathered: [MusicItem] = []
        var liked: [MusicItem] = []
        var saved: [MusicItem] = []

        for provider in activeProviders {
            guard !Task.isCancelled else { return }
            do {
                // Recents first within a provider: what someone played this
                // morning is a better guess at what they want now than the
                // playlist they made in 2019 and never opened.
                let recent = try await provider.recent()
                let library = try await provider.library()
                gathered = Self.merge(gathered, with: recent + library)
            } catch let error as MusicLibraryError {
                logger.notice("\(provider.id.rawValue, privacy: .public) refresh failed: \(error.localizedDescription, privacy: .public)")
            } catch {
                logger.notice("\(provider.id.rawValue, privacy: .public) refresh failed.")
            }

            // Gathered separately and forgivingly: the grid's pages are three
            // independent surfaces, and one of them failing must leave the
            // other two full rather than emptying the panel.
            liked = Self.merge(liked, with: (try? await provider.likedSongs()) ?? [])
            saved = Self.merge(saved, with: (try? await provider.albums()) ?? [])
        }

        guard !Task.isCancelled else { return }

        suggestions = gathered
        likedSongs = liked
        albums = saved
        lastRefresh = Date()
        logger.debug(
            "Refreshed: \(gathered.count, privacy: .public) suggestion(s), \(liked.count, privacy: .public) liked, \(saved.count, privacy: .public) album(s)."
        )
    }

    // MARK: - Gallery pages

    /// Which nine things the grid is showing.
    ///
    /// Three pages rather than one, because the three answer different
    /// questions — what I keep, what I like, what I own — and flattening them
    /// into one ranked list would make the first page stop being a speed dial.
    enum Page: Int, CaseIterable, Hashable {
        case pinned
        case liked
        case albums

        var title: String {
            switch self {
            case .pinned: "Speed dial"
            case .liked: "Liked songs"
            case .albums: "Albums"
            }
        }

        /// Whether Randomize applies.
        ///
        /// Never to the speed dial. Its whole value is that the fourth thing is
        /// still fourth tomorrow; a shuffle would be the one change that
        /// destroys the reason the page exists.
        var canReshuffle: Bool { self != .pinned }

        var emptyMessage: String {
            switch self {
            case .pinned: "Search for something, then keep it here."
            case .liked: "Songs you like in YouTube Music will appear here."
            case .albums: "Albums saved to your library will appear here."
            }
        }
    }

    /// Which slice of each pool is on show. Empty means "the first nine".
    private var deal: [Page: [Int]] = [:]

    func pool(for page: Page) -> [MusicItem] {
        switch page {
        case .pinned: []
        case .liked: likedSongs
        case .albums: albums
        }
    }

    /// The nine tiles of a page, in reading order.
    func tiles(for page: Page) -> [MusicItem?] {
        guard page != .pinned else { return tiles }

        let pool = pool(for: page)
        guard !pool.isEmpty else {
            return [MusicItem?](repeating: nil, count: SettingsStore.tileCount)
        }

        let indices = deal[page] ?? Array(0..<min(SettingsStore.tileCount, pool.count))
        var slots = [MusicItem?](repeating: nil, count: SettingsStore.tileCount)
        for (slot, index) in indices.prefix(SettingsStore.tileCount).enumerated()
        where pool.indices.contains(index) {
            slots[slot] = pool[index]
        }
        return slots
    }

    /// Deals a different nine from the same pool.
    ///
    /// It reshuffles what is *shown*, and plays nothing. A randomize button
    /// that started music would be a different verb wearing the same word, and
    /// this one is for looking.
    func reshuffle(_ page: Page) {
        guard page.canReshuffle else { return }

        let pool = pool(for: page)
        guard pool.count > SettingsStore.tileCount else {
            // Everything already fits, so there is no other nine to deal. Say
            // nothing and change nothing rather than reordering the same items
            // and calling it a shuffle.
            return
        }

        deal[page] = Array(pool.indices.shuffled().prefix(SettingsStore.tileCount))
    }

    /// Whether a page has more than it can show, and so has something to deal.
    func canReshuffle(_ page: Page) -> Bool {
        page.canReshuffle && pool(for: page).count > SettingsStore.tileCount
    }

    // MARK: - Tiles

    /// The nine things the grid draws: what was pinned, with the gaps filled
    /// in from the library if the user asked for that.
    var tiles: [MusicItem?] {
        var tiles = settings.pinnedTiles

        guard settings.autoFillsEmptyTiles else { return tiles }

        let pinned = Set(tiles.compactMap { $0?.id })
        var candidates = suggestions.filter { !pinned.contains($0.id) }.makeIterator()

        for index in tiles.indices where tiles[index] == nil {
            tiles[index] = candidates.next()
        }

        return tiles
    }

    /// Whether the tile at this position is a real pin or a guess. Guesses are
    /// drawn slightly back, and the context menu offers to make one permanent.
    func isPinned(at index: Int) -> Bool {
        settings.pinnedTiles.indices.contains(index) && settings.pinnedTiles[index] != nil
    }

    func pin(_ item: MusicItem, at index: Int) { settings.pin(item, at: index) }
    func unpin(at index: Int) { settings.unpin(at: index) }

    /// Pins something the user found in search, wherever there is room.
    /// Returns false when the grid is full, so the caller can say so.
    @discardableResult
    func pinToFirstFreeSlot(_ item: MusicItem) -> Bool {
        guard let slot = settings.firstFreeSlot else { return false }
        settings.pin(item, at: slot)
        return true
    }

    // MARK: - Search field

    func clearSearch() {
        query = ""
    }
}
