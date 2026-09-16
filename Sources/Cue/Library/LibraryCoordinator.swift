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
    private static let searchDebounce = Duration.milliseconds(400)

    let google: GoogleOAuthService
    let ytSession: YTMusicSessionService

    /// Set by `AppState`. Read by Settings, which needs to report whether the
    /// player — the only session that matters — is signed in.
    weak var player: PlayerService?

    private let settings: SettingsStore
    private let dataAPI: YouTubeDataAPIProvider
    private let ytMusic: YTMusicInternalProvider
    private let logger = Diagnostics.logger("library")

    /// What is in the search field.
    ///
    /// Plain, with no `didSet`. It had one, and searches stopped re-running
    /// after the first — typing more letters switched the panel to its results
    /// mode but never fetched anything new. Property observers and the
    /// `@Observable` macro do not reliably coexist, and the view's own
    /// `onChange` demonstrably fires on every keystroke, so the search is
    /// driven from there instead of from here.
    var query: String = ""

    private(set) var results: [MusicItem] = []

    /// Bumped whenever `results` is replaced.
    ///
    /// Read by the results list so that a settled search actually redraws it.
    /// The log showed searches landing with fifty results while the screen kept
    /// the first search's answer, and an explicit counter is a more honest
    /// dependency than trusting an array read through a shared object to be
    /// noticed.
    private(set) var resultsVersion = 0
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

    private(set) var isRefreshing = false

    /// Explore's three pages: songs to hear, records just out, albums to open.
    private(set) var recommendations: [MusicItem] = []
    private(set) var newReleases: [MusicItem] = []
    private(set) var exploreAlbums: [MusicItem] = []
    private var exploreTask: Task<Void, Never>?

    /// Everything the account already knows about, for filtering Explore.
    ///
    /// Built from likes, library and history. Without it Explore is a second
    /// copy of the front page, and the whole request was for music you have not
    /// heard.
    private var knownIdentifiers: Set<String> {
        var known: Set<String> = []
        for item in likedSongs + suggestions + settings.albumCollection {
            if let video = item.videoID { known.insert("v:" + video) }
            if let list = item.playlistID { known.insert("p:" + list) }
            if let browse = item.browseID { known.insert("b:" + browse) }
        }
        return known
    }

    private func unfamiliar(_ items: [MusicItem]) -> [MusicItem] {
        let known = knownIdentifiers
        return items.filter { item in
            if let video = item.videoID, known.contains("v:" + video) { return false }
            if let list = item.playlistID, known.contains("p:" + list) { return false }
            if let browse = item.browseID, known.contains("b:" + browse) { return false }
            return true
        }
    }

    /// Every mood and genre the service offers, once anything has asked.
    private(set) var genres: [MusicGenre] = []
    private(set) var isLoadingGenres = false
    private var genresTask: Task<Void, Never>?

    /// Fetches the genre list, once per launch.
    ///
    /// Settings calls this when its pane appears. The list is long, translated,
    /// and different in every country, so it is worth a request — but it is the
    /// same answer all day, and asking again on every visit to a settings pane
    /// is exactly the kind of over-frequent call these endpoints punish.
    func loadGenres() {
        guard genres.isEmpty, genresTask == nil, !activeProviders.isEmpty else { return }

        isLoadingGenres = true
        genresTask = Task { [weak self] in
            guard let self else { return }
            var found: [MusicGenre] = []
            for provider in self.activeProviders where found.isEmpty {
                found = (try? await provider.genres()) ?? []
            }
            self.genres = found
            self.isLoadingGenres = false
            // Left non-nil on success so it never asks twice; cleared on
            // failure so a signed-out first attempt is not permanent.
            if found.isEmpty { self.genresTask = nil }
        }
    }

    private var lastExploreRefresh: Date?

    /// Fetches the three Explore pages.
    ///
    /// Throttled like the library, and for a sharper reason: the gallery calls
    /// this every time the panel opens in Explore, and a refresh now costs
    /// three requests plus one per record it opens. Nine requests every time
    /// somebody presses ⌥Space is how an account stops being answered — and
    /// the punishment is an empty page, which looks exactly like a bug in this
    /// code rather than a rate limit. ⌘R deals a different nine from what is
    /// already here and costs nothing.
    func refreshExplore(force: Bool = false) {
        guard !activeProviders.isEmpty else { return }
        if isRefreshingExplore, !force { return }
        if !force,
           let lastExploreRefresh,
           Date().timeIntervalSince(lastExploreRefresh) < Self.refreshInterval,
           !recommendations.isEmpty {
            return
        }

        exploreTask?.cancel()
        exploreTask = Task { [weak self] in await self?.performExploreRefresh() }
    }

    private var isRefreshingExplore = false

    private func performExploreRefresh() async {
        isRefreshingExplore = true
        defer { isRefreshingExplore = false }

        let chosen = settings.exploreGenre

        var suggested: [MusicItem] = []
        var released: [MusicItem] = []
        var trending: [MusicItem] = []

        for provider in activeProviders {
            guard !Task.isCancelled else { return }

            // A genre replaces the home feed rather than filtering it. There is
            // no filter to apply — what comes back from the home feed carries
            // no genre on it — so the only honest way to honour a choice is to
            // ask a different question.
            if let chosen {
                suggested = Self.merge(suggested, with: (try? await provider.genre(chosen)) ?? [])
            } else {
                suggested = Self.merge(suggested, with: (try? await provider.recommendations()) ?? [])
            }

            released = Self.merge(released, with: (try? await provider.newReleases()) ?? [])
            trending = Self.merge(trending, with: (try? await provider.charts()) ?? [])
        }

        guard !Task.isCancelled else { return }

        // Nothing at all is an answer these endpoints give freely — to a caller
        // who asked too often, to a signed-out session, to a region they have
        // no shelves for. It is never a reason to throw away three pages that
        // were working a minute ago.
        guard !(suggested.isEmpty && released.isEmpty && trending.isEmpty) else {
            logger.notice("Explore came back empty; keeping what was already there.")
            return
        }

        let offered = Self.merge(suggested, with: trending)

        // Not filtered against what you know. New releases are new by
        // definition, so there is nothing to filter out.
        newReleases = released

        // New records first, then anything else on offer that is an album.
        exploreAlbums = Self.merge(Self.albums(in: released), with: Self.albums(in: offered))

        // Songs, and only songs. A tile you have to go *into* is the opposite
        // of what this grid is for — the same rule the speed dial has always
        // had.
        var forYou = unfamiliar(Self.songs(in: offered))
        let fromFeed = forYou.count

        // Which is sometimes none, and the reason is worth knowing: on a cold
        // session — the first refresh after launch, before the player has a
        // live cookie to lend — the home feed answers in promotional shelves
        // and the charts in records, and sixty-five items between them contain
        // no track you can click and hear. Warm, the same feed returns fifty.
        //
        // So this is not the normal path, it is the path for a page that would
        // otherwise be empty. An album is a dozen songs behind one more
        // request, and declining to make that request is the difference between
        // a grid with plenty to show and nine dashed squares.
        if forYou.count < Self.songsWorthDealing {
            // Playlists count as somewhere to dig, not only albums. A genre's
            // page is curated shelves almost end to end, so under a chosen
            // genre the playlists are very nearly all there is to open — and
            // what is on offer comes first, because that is the part the choice
            // was about.
            let containers = Self.merge(
                Self.containers(in: offered),
                with: Self.albums(in: released)
            )
            let extracted = await songsFromAlbums(
                containers,
                until: Self.songsWorthDealing - forYou.count
            )
            forYou = Self.merge(forYou, with: unfamiliar(extracted))
        }

        guard !Task.isCancelled else { return }
        recommendations = forYou
        lastExploreRefresh = Date()

        // While we are already here. Settings needs this list to draw its
        // picker, and fetching it on the way past means the picker is populated
        // the first time it is opened rather than a second after. Once per
        // launch, and only for someone who actually uses Explore.
        loadGenres()

        logger.notice(
            """
            Explore, \(chosen == nil ? "home feed" : "one genre", privacy: .public): \
            \(self.recommendations.count, privacy: .public) songs for you \
            (\(fromFeed, privacy: .public) from the feed), \
            \(released.count, privacy: .public) new, \
            \(self.exploreAlbums.count, privacy: .public) albums.
            """
        )
    }

    /// Enough songs to deal a page and still have something else to deal.
    ///
    /// Three pages' worth. Exactly nine would mean ⌘R does nothing, which reads
    /// as a broken button rather than as a short list.
    private static let songsWorthDealing = SettingsStore.tileCount * 3

    /// How many records to open. Each one is a request, and these endpoints
    /// answer a caller who asks too often with an empty page rather than an
    /// error — so the ceiling is low, and reached only when the feed came back
    /// thin. A typical album covers most of the shortfall on its own.
    private static let albumsOpenedForSongs = 6

    /// Opens albums, one at a time, until there are enough songs.
    ///
    /// Sequential on purpose. Firing six requests at once is the fastest way to
    /// be told, politely and with a 200, that this account has no music.
    private func songsFromAlbums(_ albums: [MusicItem], until wanted: Int) async -> [MusicItem] {
        var found: [MusicItem] = []

        for album in albums.prefix(Self.albumsOpenedForSongs) {
            guard !Task.isCancelled else { break }

            for provider in activeProviders {
                let tracks = (try? await provider.tracks(of: album)) ?? []
                found = Self.merge(found, with: Self.songs(in: tracks))
            }

            if found.count >= wanted { break }
        }

        return found
    }

    /// The things on this list that play when you click them.
    ///
    /// A video counts. YouTube Music serves plenty of tracks that are formally
    /// videos, and refusing them would drop real songs on a technicality.
    static func songs(in items: [MusicItem]) -> [MusicItem] {
        items.filter { $0.videoID != nil && ($0.kind == .song || $0.kind == .video) }
    }

    static func albums(in items: [MusicItem]) -> [MusicItem] {
        items.filter { $0.kind == .album }
    }

    /// Anything with songs inside it. A generated radio is excluded: it has no
    /// contents until something plays it, so there is nothing there to take.
    static func containers(in items: [MusicItem]) -> [MusicItem] {
        items.filter { $0.kind == .album || $0.kind == .playlist }
    }

    private var searchTask: Task<Void, Never>?

    /// Which search the results on screen belong to.
    ///
    /// `Task.isCancelled` alone was not enough: a cancelled search returned
    /// without clearing `isSearching`, so the spinner ran forever, and a slow
    /// provider answering after a newer query had already been typed could
    /// still write its stale list. Every search takes a number, and only the
    /// current number may touch the results.
    private var searchGeneration = 0
    private var refreshTask: Task<Void, Never>?
    private var lastRefresh: Date?

    /// How long a fetched library is trusted before asking again.
    ///
    /// Fifteen minutes, not one. These endpoints are undocumented and
    /// rate-limited, and the punishment for asking too often is not an error —
    /// it is an empty answer that looks exactly like an empty library. A
    /// playlist you made last week does not need re-fetching every time the
    /// panel opens.
    private static let refreshInterval: TimeInterval = 15 * 60

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

        // Shown immediately, from the last time it was fetched successfully.
        // The grid should be there the instant the panel opens, and it should
        // still be there when the network is not.
        suggestions = Self.loadCache(Key.suggestions, from: settings.defaults)
        likedSongs = Self.loadCache(Key.likedSongs, from: settings.defaults)
    }

    private enum Key {
        static let suggestions = "cache.suggestions"
        static let likedSongs = "cache.likedSongs"
    }

    private static func loadCache(_ key: String, from defaults: UserDefaults) -> [MusicItem] {
        guard let data = defaults.data(forKey: key),
              let items = try? JSONDecoder().decode([MusicItem].self, from: data)
        else { return [] }
        return items
    }

    private func saveCache(_ items: [MusicItem], to key: String) {
        // Capped: a library of thousands is not worth writing on every refresh,
        // and the grid deals from a few dozen.
        guard let data = try? JSONEncoder().encode(Array(items.prefix(120))) else { return }
        settings.defaults.set(data, forKey: key)
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

    /// Whether this is a YouTube video rather than a YouTube Music track.
    ///
    /// Everything Cue plays is addressed at music.youtube.com, and for a video
    /// the catalogue does not carry, that address quietly becomes youtube.com —
    /// a different player, different controls, and adverts a Premium
    /// subscription has already paid to be rid of. It still plays, so this is a
    /// mark rather than a refusal.
    ///
    /// The test is which backend knew about it. Both are asked and their
    /// answers merged, so an item that only ever came from the official API is
    /// one YouTube Music was asked about and did not return. That reasoning
    /// only holds while there is something to compare against: with the Music
    /// session off, everything arrives from the official API and none of it has
    /// been ruled out by anybody.
    func isOutsideMusicCatalogue(_ item: MusicItem) -> Bool {
        guard settings.unofficialProviderEnabled, ytMusic.isConnected else { return false }
        return item.source == .dataAPI && item.videoID != nil
    }

    /// Whether the real YouTube Music library is reachable.
    var hasMusicSession: Bool {
        settings.unofficialProviderEnabled && ytMusic.isConnected
    }

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

    /// Called by the panel whenever the field changes.
    func queryChanged() {
        // Debug rather than notice: this fires on every keystroke, and a log
        // that records everything anyone types is not one to leave switched on.
        logger.debug("Field now holds \(self.query, privacy: .private).")
        scheduleSearch()
    }

    private func scheduleSearch() {
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // Clearing the field goes back to the grid immediately. Waiting
            // out a debounce to show something the user already asked to stop
            // seeing is the wrong way round.
            results = []
            resultsVersion &+= 1
            isSearching = false
            message = nil
            return
        }

        isSearching = true
        searchGeneration += 1
        let generation = searchGeneration

        searchTask = Task { [weak self] in
            try? await Task.sleep(for: Self.searchDebounce)
            guard !Task.isCancelled, let self else { return }
            await self.performSearch(trimmed, generation: generation)
        }
    }

    private func performSearch(_ query: String, generation: Int) async {
        let providers = activeProviders
        guard !providers.isEmpty else {
            results = []
            resultsVersion &+= 1
            isSearching = false
            message = "Connect an account in Settings to search."
            return
        }

        logger.notice("Search #\(generation, privacy: .public) running for \(query, privacy: .private).")

        var merged: [MusicItem] = []
        var failures: [MusicLibraryError] = []

        // Sequential rather than concurrent, deliberately. The providers are
        // ordered by how much their answers are worth, and merging preserves
        // that order; running them in parallel would save a few hundred
        // milliseconds and then need the order restored anyway.
        for provider in providers {
            guard generation == searchGeneration else {
                logger.notice("Search #\(generation, privacy: .public) abandoned; #\(self.searchGeneration, privacy: .public) is newer.")
                return
            }
            do {
                merged = Self.merge(merged, with: try await provider.search(query))
            } catch let error as MusicLibraryError {
                logger.notice("\(provider.id.rawValue, privacy: .public) search failed: \(error.localizedDescription, privacy: .public)")
                failures.append(error)
            } catch {
                failures.append(.transport(error))
            }
        }

        // Only the newest search writes. An older one that finished late must
        // leave the screen alone rather than replacing newer results with the
        // answer to a question nobody is asking any more.
        guard generation == searchGeneration else {
            logger.notice("Search #\(generation, privacy: .public) finished late; discarded.")
            return
        }

        results = merged
        resultsVersion &+= 1
        isSearching = false

        logger.notice(
            "Search #\(generation, privacy: .public) settled for \(query, privacy: .private): \(merged.count, privacy: .public) result(s), first \(merged.first?.title ?? "—", privacy: .private)."
        )
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
    /// Refreshes regardless of the rate limit or anything already running.
    ///
    /// For the one case that genuinely invalidates a previous answer: the
    /// credentials changed, so whatever the last refresh returned was fetched
    /// as somebody else.
    func refreshNow() {
        refreshTask?.cancel()
        lastRefresh = nil
        refreshTask = Task { [weak self] in await self?.performRefresh() }
    }

    func refresh(force: Bool = false) {
        // A refresh already running is left alone. Cancelling it to start
        // another achieves nothing except losing the first one's answers, and
        // the logs showed exactly that: "albums failed: cancelled".
        if isRefreshing, !force { return }
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < Self.refreshInterval { return }
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
            //
            // Liked songs come from YouTube Music alone when it is available.
            // The official API's "likes" are YouTube's — every video you ever
            // thumbed up — which is a different list wearing the same word, and
            // mixing the two makes the page unrecognisable as your music.
            if provider.id == .ytMusic || !hasMusicSession {
                do {
                    let songs = try await provider.likedSongs()
                    liked = Self.merge(liked, with: songs)
                    logger.notice("\(provider.id.rawValue, privacy: .public) liked songs: \(songs.count, privacy: .public)")
                } catch {
                    logger.error("\(provider.id.rawValue, privacy: .public) liked songs failed: \(error.localizedDescription, privacy: .public)")
                }
            }

            // Albums are not fetched any more: the third page is the shelf you
            // fill by hand, so asking the service for a list nothing reads is
            // two requests per refresh spent on nothing.
        }

        guard !Task.isCancelled else { return }

        // A page that already has something keeps it when a refresh comes back
        // empty. A request that failed, was cancelled, or was answered as
        // logged-out all return nothing, and none of them are grounds for
        // wiping a page that was working a minute ago.
        // A page that already has something keeps it when a refresh comes back
        // empty — and it now stays kept across launches, because being
        // rate-limited at the wrong moment should not cost you your grid.
        if !gathered.isEmpty {
            suggestions = gathered
            saveCache(gathered, to: Key.suggestions)
        }
        if !liked.isEmpty {
            likedSongs = liked
            saveCache(liked, to: Key.likedSongs)
        }

        lastRefresh = Date()
        logger.debug(
            "Refreshed: \(gathered.count, privacy: .public) suggestion(s), \(liked.count, privacy: .public) liked."
        )
    }

    // MARK: - Playing

    /// Asks whichever provider can turn this into something that plays.
    func playable(for item: MusicItem) async -> MusicItem {
        for provider in activeProviders where provider.id == item.source {
            return await provider.playable(item)
        }
        // Nothing from this provider is connected any more; try whoever is.
        for provider in activeProviders {
            let resolved = await provider.playable(item)
            if resolved.playlistID != nil { return resolved }
        }
        return item
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

        /// What this page is called, which depends on which world the grid is
        /// showing. The three positions are the same; what fills them is not.
        func title(exploring: Bool) -> String {
            guard exploring else {
                switch self {
                case .pinned: return "Speed dial"
                case .liked: return "Liked songs"
                case .albums: return "Albums"
                }
            }
            switch self {
            case .pinned: return "For you"
            case .liked: return "New releases"
            case .albums: return "Albums"
            }
        }

        /// Every page can be redealt, including the speed dial — but on that
        /// page it only ever touches the slots Cue filled in for you. Anything
        /// you kept stays exactly where you put it, because the fourth thing
        /// still being fourth tomorrow is the reason the page works.
        var canReshuffle: Bool { true }

        func emptyMessage(exploring: Bool) -> String {
            guard exploring else {
                switch self {
                case .pinned: return "Search for something, then keep it here."
                case .liked: return "Songs you like in YouTube Music will appear here."
                case .albums: return "Right-click anything and choose Add to Albums."
                }
            }
            return "Nothing here yet — Cue is still looking."
        }
    }

    /// Which slice of each pool is on show. Empty means "the first nine".
    private var deal: [Page: [Int]] = [:]

    /// Whether the grid is showing Explore.
    var isExploring: Bool { settings.isExploring }

    /// Swaps the world the grid is drawn from, and fetches it if need be.
    func toggleExplore() {
        settings.isExploring.toggle()
        if settings.isExploring { refreshExplore() }
    }

    func pool(for page: Page) -> [MusicItem] {
        if settings.isExploring {
            switch page {
            case .pinned: return recommendations
            case .liked: return newReleases
            case .albums:
                // New releases are mostly albums, so without this the last two
                // pages show the same records and one of them is a wasted
                // swipe. Excluding what is *on screen* rather than the whole
                // pool keeps this page full: reshuffle page two and this one
                // re-fills from what page two just let go of.
                let showing = Set(tiles(for: .liked).compactMap { $0?.id })
                return exploreAlbums.filter { !showing.contains($0.id) }
            }
        }

        switch page {
        case .pinned: return []
        case .liked: return likedSongs
        // Curated, not fetched. What the library reports as your albums and
        // what you would actually want on a speed dial turned out to be
        // different lists.
        case .albums: return settings.albumCollection
        }
    }

    /// The nine tiles of a page, in reading order.
    func tiles(for page: Page) -> [MusicItem?] {
        // In Explore every page is dealt from a pool, including the first —
        // there is nothing pinned in a world you are visiting.
        guard settings.isExploring || page != .pinned else { return tiles }

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
        guard settings.isExploring || page != .pinned else {
            reshuffleSuggestions()
            return
        }

        let pool = pool(for: page)
        guard pool.count > SettingsStore.tileCount else {
            // Everything already fits, so there is no other nine to deal. Say
            // nothing and change nothing rather than reordering the same items
            // and calling it a shuffle.
            return
        }

        deal[page] = Array(pool.indices.shuffled().prefix(SettingsStore.tileCount))
    }

    /// Redeals the speed dial's auto-filled slots, leaving every pin alone.
    private func reshuffleSuggestions() {
        guard autoFillCandidates.count > 1 else { return }
        // Both pools are shuffled, since the speed dial now deals from either.
        suggestions = suggestions.shuffled()
        likedSongs = likedSongs.shuffled()
    }

    /// Whether a page has something else to deal.
    func canReshuffle(_ page: Page) -> Bool {
        if settings.isExploring {
            return pool(for: page).count > SettingsStore.tileCount
        }

        switch page {
        case .pinned:
            // Only worth offering when there is at least one slot Cue filled in
            // and something else it could have put there.
            let pinnedCount = settings.pinnedTiles.compactMap { $0 }.count
            return settings.autoFillsEmptyTiles
                && pinnedCount < SettingsStore.tileCount
                && autoFillCandidates.count > SettingsStore.tileCount - pinnedCount
        case .liked, .albums:
            return pool(for: page).count > SettingsStore.tileCount
        }
    }

    // MARK: - Tiles

    /// The nine things the grid draws: what was pinned, with the gaps filled
    /// in from the library if the user asked for that.
    var tiles: [MusicItem?] {
        var tiles = settings.pinnedTiles

        guard settings.autoFillsEmptyTiles else { return tiles }

        let pinned = Set(tiles.compactMap { $0?.id })

        // Songs only. A speed dial is for the thing you want to hear right now,
        // and a playlist in one of those nine positions is a container you have
        // to go into — which is the opposite of what the grid is for. Anything
        // pinned by hand stays whatever it is; this governs only what Cue fills
        // the gaps with.
        var candidates = autoFillCandidates
            .filter { !pinned.contains($0.id) }
            .makeIterator()

        for index in tiles.indices where tiles[index] == nil {
            tiles[index] = candidates.next()
        }

        return tiles
    }

    /// What Cue puts in the speed dial's empty slots.
    ///
    /// What you played recently first, then what you have liked. History alone
    /// left the grid empty: once playlists are excluded — and they are, because
    /// a container in a speed-dial slot is something you have to go *into* —
    /// history on its own is thin, and after a cold start it is nothing at all.
    /// Ninety-nine liked songs are a better answer than nine dashed rectangles.
    private var autoFillCandidates: [MusicItem] {
        let recent = suggestions.filter { $0.videoID != nil }

        // Liked songs are page two's whole reason for existing, so anything
        // showing there is off limits here. Filling the speed dial from the
        // same nine made the two pages identical, which is worse than a short
        // first page: two pages that say the same thing are one page and a
        // wasted swipe.
        let showing = Set(tiles(for: .liked).compactMap { $0?.id })
        let rest = likedSongs.filter { $0.videoID != nil && !showing.contains($0.id) }

        return Self.merge(recent, with: rest)
    }

    /// Whether the tile at this position is a real pin or a guess. Guesses are
    /// drawn slightly back, and the context menu offers to make one permanent.
    func isPinned(at index: Int) -> Bool {
        settings.pinnedTiles.indices.contains(index) && settings.pinnedTiles[index] != nil
    }

    func addToAlbums(_ item: MusicItem) { settings.addToAlbums(item) }
    func removeFromAlbums(_ item: MusicItem) { settings.removeFromAlbums(item) }
    func isInAlbums(_ item: MusicItem) -> Bool { settings.isInAlbums(item) }

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
