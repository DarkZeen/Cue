import Foundation

/// The unofficial backend: the endpoints music.youtube.com calls itself.
///
/// This is the only way to reach what a person actually means by "my music" —
/// the Music library rather than the YouTube one, liked songs as Music
/// understands them, listening history, and the mixes on the home feed. The
/// Data API has none of those. In exchange, none of it is promised to anyone,
/// and it is entirely reasonable for Google to change the shape of a response
/// on a Tuesday.
///
/// So the whole file is written to degrade rather than break:
///
/// * Responses are walked by leaf-renderer name (`JSONValue.collect`) instead
///   of by path, so an extra wrapper changes nothing.
/// * Every field is optional. An item missing a thumbnail is an item without a
///   thumbnail, not a dropped result.
/// * A 401 or 403 invalidates the stored session and disconnects, which turns
///   the failure into "sign in again" in Settings rather than an empty grid.
///
/// The feature flag around it is the real protection: if this stops working,
/// the user turns it off and Cue is the app it was before, with everything
/// official still in place.
final class YTMusicInternalProvider: MusicLibraryProvider {
    let id = ProviderID.ytMusic

    private let session: YTMusicSessionService
    private let urlSession: URLSession
    private let logger = Diagnostics.logger("ytmusic-internal")

    private static let base = URL(string: "https://music.youtube.com/youtubei/v1/")!

    /// The web client's own public API key. Not a secret in any sense — it is
    /// served in the page source to every visitor — and it is here because the
    /// endpoint expects the parameter, not because it authorizes anything. The
    /// cookie is what authorizes.
    private static let apiKey = "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30"

    /// Browse identifiers the Music front end uses for its own pages.
    private enum BrowseID {
        static let libraryPlaylists = "FEmusic_liked_playlists"
        static let history = "FEmusic_history"
        static let home = "FEmusic_home"
        /// Liked songs. A real playlist id, so it can be opened directly.
        static let likedSongs = "LM"
        /// The liked-songs *page*, for reading its contents. A playlist's browse
        /// id is `VL` glued onto the playlist id.
        static let likedSongsPage = "VLLM"
        /// Saved albums in the library.
        static let libraryAlbums = "FEmusic_liked_albums"
    }

    init(session: YTMusicSessionService, urlSession: URLSession = .shared) {
        self.session = session
        self.urlSession = urlSession
    }

    var isConnected: Bool { session.isConnected }

    // MARK: - Queries

    func search(_ query: String) async throws -> [MusicItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let response = try await post("search", body: ["query": trimmed])
        return Self.items(in: response)
    }

    func library() async throws -> [MusicItem] {
        let response = try await post("browse", body: ["browseId": BrowseID.libraryPlaylists])

        let liked = MusicItem(
            id: "\(ProviderID.ytMusic.rawValue):playlist:\(BrowseID.likedSongs)",
            title: "Liked Music",
            subtitle: "Songs you liked in YouTube Music",
            kind: .playlist,
            playlistID: BrowseID.likedSongs,
            source: .ytMusic
        )

        return [liked] + Self.items(in: response)
    }

    /// The tracks inside Liked Music.
    ///
    /// The one thing the official API cannot see at all: YouTube Music's likes
    /// are not YouTube's likes, and an account can have hundreds of the first
    /// and none of the second.
    func likedSongs() async throws -> [MusicItem] {
        // The assumed page first, then the one the library itself points at.
        //
        // `VLLM` is what every client uses, and when it comes back empty the
        // useful move is to stop asserting it: the library listing contains a
        // Liked Music entry with its own identifier, so the second attempt asks
        // the service where its liked songs are rather than telling it.
        if let songs = try? await tracks(inPlaylistPage: BrowseID.likedSongsPage), !songs.isEmpty {
            return songs
        }

        logger.notice("\(BrowseID.likedSongsPage, privacy: .public) held no songs; trying the queue endpoint.")

        // A different mechanism, not a different guess. `next` returns the
        // *queue* for a playlist — what would play if you pressed it — as
        // `playlistPanelVideoRenderer` entries. It is how the site itself
        // builds a play queue, and it answers for the auto-playlists like Liked
        // Music that the browse endpoint is evidently not serving here.
        if let queued = try? await queue(forPlaylist: BrowseID.likedSongs), !queued.isEmpty {
            return queued
        }

        guard let liked = try? await likedPlaylistFromLibrary() else { return [] }
        return (try? await tracks(inPlaylistPage: liked)) ?? []
    }

    /// The tracks that would play, for a playlist id.
    private func queue(forPlaylist playlistID: String) async throws -> [MusicItem] {
        let response = try await post("next", body: [
            "playlistId": playlistID,
            // Without this the queue comes back as the single first track and
            // its radio, rather than the playlist's own contents.
            "isAudioOnly": true,
        ])

        let entries = response.collect("playlistPanelVideoRenderer")
        let songs = Self.deduplicated(entries.compactMap(Self.queueEntry(from:)))

        logger.notice(
            "next(\(playlistID, privacy: .public)): \(entries.count, privacy: .public) entries, \(songs.count, privacy: .public) usable."
        )
        return songs
    }

    /// One row of a play queue.
    ///
    /// A simpler shape than the list renderers: the title and the byline are
    /// plain runs, and the video id is on the renderer itself rather than
    /// buried in an overlay.
    static func queueEntry(from renderer: JSONValue) -> MusicItem? {
        guard let title = renderer["title"]?.runsText, !title.isEmpty,
              let videoID = renderer["videoId"]?.string
        else { return nil }

        return MusicItem(
            id: "\(ProviderID.ytMusic.rawValue):song:\(videoID)",
            title: title,
            subtitle: renderer["shortBylineText"]?.runsText
                ?? renderer["longBylineText"]?.runsText,
            kind: .song,
            videoID: videoID,
            thumbnailURL: thumbnailURL(in: renderer),
            source: .ytMusic
        )
    }

    /// The tracks on a playlist page, given its browse id.
    private func tracks(inPlaylistPage browseID: String) async throws -> [MusicItem] {
        let response = try await post("browse", body: ["browseId": browseID])

        let rows = response.collect("musicResponsiveListItemRenderer")
        let parsed = rows.compactMap(Self.row(from:))
        let songs = Self.deduplicated(parsed)

        // Three numbers, because they fail in different places: rows that never
        // arrived, rows the parser refused, and rows that collapsed into each
        // other during de-duplication. One number cannot tell them apart.
        logger.notice(
            "\(browseID, privacy: .public): \(rows.count, privacy: .public) rows, \(parsed.count, privacy: .public) parsed, \(songs.count, privacy: .public) distinct."
        )
        return songs
    }

    /// Finds the liked-songs playlist in the library listing.
    ///
    /// Matched on its identifier rather than its title, which is translated —
    /// this account's library would say "Liked Music" in English and something
    /// else entirely in another locale.
    private func likedPlaylistFromLibrary() async throws -> String? {
        let response = try await post("browse", body: ["browseId": BrowseID.libraryPlaylists])

        for card in response.collect("musicTwoRowItemRenderer") {
            guard let item = Self.card(from: card) else { continue }
            if item.playlistID == BrowseID.likedSongs || item.playlistID == "LM" {
                return "VL" + BrowseID.likedSongs
            }
        }

        // Nothing matched; the first browse endpoint that looks like a playlist
        // page is better than giving up entirely.
        return response.collect("browseEndpoint")
            .compactMap { $0["browseId"]?.string }
            .first { $0.hasPrefix("VL") }
    }

    /// Saved albums, as containers rather than flattened into tracks.
    func albums() async throws -> [MusicItem] {
        let response = try await post("browse", body: ["browseId": BrowseID.libraryAlbums])

        // Both renderers, because the library page follows the display mode the
        // account last chose: as a grid it returns cards, as a list it returns
        // rows. Collecting only cards is why this page came back empty for an
        // account whose library happens to be set to list view.
        let cards = response.collect("musicTwoRowItemRenderer").compactMap(Self.card(from:))
        let rows = response.collect("musicResponsiveListItemRenderer").compactMap(Self.row(from:))

        return Self.deduplicated(cards + rows)
    }

    /// Resolves an album page to the playlist behind it.
    ///
    /// The album page carries an `audioPlaylistId` — the `OLAK5uy_…` list of
    /// its tracks — and a `/playlist?list=…` URL built from it plays, which the
    /// `/browse/…` address never did. Costs one request, and only when an album
    /// is actually clicked rather than for all nine on the page.
    func playable(_ item: MusicItem) async -> MusicItem {
        guard item.kind == .album, item.playlistID == nil, let browseID = item.browseID else {
            return item
        }

        guard let response = try? await post("browse", body: ["browseId": browseID]) else {
            logger.notice("Could not resolve an album to its playlist.")
            return item
        }

        // The named field first, then any list id in a watch endpoint. Albums
        // whose page shape has moved still tend to carry one of the two.
        let playlistID = response.firstValue(forKey: "audioPlaylistId")?.string
            ?? response.collect("watchEndpoint")
                .compactMap { $0["playlistId"]?.string }
                .first { $0.hasPrefix("OLAK5uy_") }

        guard let playlistID else {
            logger.notice("An album page carried no playlist id.")
            return item
        }

        var resolved = item
        resolved.playlistID = playlistID
        resolved.browseID = nil
        return resolved
    }

    /// History first, then the home feed's mixes.
    ///
    /// Both are best-effort: a new account has no history, and the home feed
    /// is heavily personalised and occasionally returns nothing but shelves of
    /// promotional content. Either failing is not a reason to fail the other,
    /// which is why they are gathered rather than awaited in sequence.
    func recent() async throws -> [MusicItem] {
        async let history = try? post("browse", body: ["browseId": BrowseID.history])
        async let home = try? post("browse", body: ["browseId": BrowseID.home])

        var items = await history.map(Self.items(in:)) ?? []
        items += await home.map(Self.items(in:)) ?? []

        return Self.deduplicated(items)
    }

    // MARK: - Transport

    private func post(_ endpoint: String, body: [String: Any]) async throws -> JSONValue {
        guard let headers = await session.authorizationHeaders() else {
            throw MusicLibraryError.notAuthorized
        }

        var components = URLComponents(
            url: Self.base.appending(path: endpoint),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "alt", value: "json"),
            URLQueryItem(name: "key", value: Self.apiKey),
            // Strips the indentation from a response that is already several
            // hundred kilobytes. Free, and it is what the site itself sends.
            URLQueryItem(name: "prettyPrint", value: "false"),
        ]

        guard let url = components.url else {
            throw MusicLibraryError.unexpectedResponse("could not build a request URL")
        }

        var payload = body
        payload["context"] = Self.context

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        do {
            let (data, response) = try await urlSession.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            if Diagnostics.logsNetwork {
                logger.debug("POST \(endpoint, privacy: .public) → \(status, privacy: .public), \(data.count, privacy: .public) bytes")
            }

            switch status {
            case 200..<300:
                return try JSONValue(data: data)
            case 401, 403:
                // The session died: signed out elsewhere, password changed, or
                // Google decided this one looked automated. Nothing to retry.
                session.invalidate(reason: "YouTube Music rejected the saved session.")
                throw MusicLibraryError.authenticationExpired
            default:
                throw MusicLibraryError.unexpectedResponse("HTTP \(status)")
            }
        } catch let error as MusicLibraryError {
            throw error
        } catch {
            throw MusicLibraryError.transport(error)
        }
    }

    /// The client description every InnerTube request carries.
    ///
    /// `WEB_REMIX` is YouTube Music's own client name; sending `WEB` gets
    /// YouTube results with no Music library in them. The version is a date,
    /// and a stale one is the most common way this kind of client stops
    /// working — so it is generated from yesterday rather than typed in, which
    /// is the same thing the Python libraries settled on.
    private static var context: [String: Any] {
        let yesterday = Date().addingTimeInterval(-86_400)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd"

        return [
            "client": [
                "clientName": "WEB_REMIX",
                "clientVersion": "1.\(formatter.string(from: yesterday)).01.00",
                "hl": Locale.current.language.languageCode?.identifier ?? "en",
                "gl": Locale.current.region?.identifier ?? "US",
            ],
            "user": [:],
        ]
    }

    // MARK: - Parsing

    /// Everything item-shaped in a response, in the order it appeared.
    ///
    /// Two renderers cover essentially the whole service: a
    /// `musicResponsiveListItemRenderer` is a row in a list (search results,
    /// playlist contents), and a `musicTwoRowItemRenderer` is a card in a grid
    /// or a carousel (library playlists, albums, the home feed). Finding those
    /// by name anywhere in the tree is what makes one parser work for search,
    /// library and history alike.
    static func items(in response: JSONValue) -> [MusicItem] {
        let rows = response.collect("musicResponsiveListItemRenderer").compactMap(row(from:))
        let cards = response.collect("musicTwoRowItemRenderer").compactMap(card(from:))
        return deduplicated(rows + cards)
    }

    /// A row: search results and track listings.
    static func row(from renderer: JSONValue) -> MusicItem? {
        let columns = renderer["flexColumns"]?.array ?? []
        let texts = columns.compactMap {
            $0["musicResponsiveListItemFlexColumnRenderer", "text"]?.runsText
        }

        guard let title = texts.first, !title.isEmpty else { return nil }

        // The second column is "Song • Artist • Album • 3:14" — everything the
        // row knows about itself, already formatted, already localised. Better
        // to show it than to take it apart and put it back together worse.
        let subtitle = texts.dropFirst().first { !$0.isEmpty }

        // The play button's endpoint is the authoritative one: it is what the
        // row does when clicked, including the playlist context that makes the
        // rest of the album follow on. The title's own endpoint is the
        // fallback, and `playlistItemData` the last resort.
        let endpoint = renderer.firstValue(forKey: "playNavigationEndpoint")
            ?? columns.first?["musicResponsiveListItemFlexColumnRenderer", "text", "runs", "0", "navigationEndpoint"]
            ?? renderer["navigationEndpoint"]

        var destination = endpoint.flatMap(Destination.init(endpoint:)) ?? Destination()
        if destination.isEmpty, let videoID = renderer["playlistItemData", "videoId"]?.string {
            destination.videoID = videoID
            destination.kind = .song
        }

        guard !destination.isEmpty else { return nil }

        return item(
            title: title,
            subtitle: subtitle,
            destination: destination,
            thumbnailURL: thumbnailURL(in: renderer),
            defaultKind: .song
        )
    }

    /// A card: library grids, carousels, the home feed.
    static func card(from renderer: JSONValue) -> MusicItem? {
        guard let title = renderer["title"]?.runsText, !title.isEmpty else { return nil }

        // The library grid's first tile is a "New playlist" button wearing the
        // same renderer as a real playlist. It has no destination, which is
        // what tells it apart.
        let endpoint = renderer["navigationEndpoint"]
            ?? renderer["title", "runs", "0", "navigationEndpoint"]
        guard let destination = endpoint.flatMap(Destination.init(endpoint:)), !destination.isEmpty else {
            return nil
        }

        return item(
            title: title,
            subtitle: renderer["subtitle"]?.runsText,
            destination: destination,
            thumbnailURL: thumbnailURL(in: renderer),
            defaultKind: .playlist
        )
    }

    private static func item(
        title: String,
        subtitle: String?,
        destination: Destination,
        thumbnailURL: URL?,
        defaultKind: MusicItemKind
    ) -> MusicItem {
        let kind = destination.kind ?? defaultKind
        // The video first, and the order matters more than it looks. Every row
        // on a playlist page carries the *same* playlist id as its context, so
        // identifying a song by that collapsed a hundred liked songs into one
        // during de-duplication. A track is identified by its track; a playlist
        // id only identifies a container.
        let identity = destination.videoID ?? destination.browseID ?? destination.playlistID ?? title

        return MusicItem(
            id: "\(ProviderID.ytMusic.rawValue):\(kind.rawValue):\(identity)",
            title: title,
            subtitle: subtitle,
            kind: kind,
            videoID: destination.videoID,
            playlistID: destination.playlistID,
            browseID: destination.browseID,
            thumbnailURL: thumbnailURL,
            source: .ytMusic
        )
    }

    /// Where a renderer points, flattened out of the three endpoint shapes.
    struct Destination {
        var videoID: String?
        var playlistID: String?
        var browseID: String?
        var kind: MusicItemKind?

        var isEmpty: Bool { videoID == nil && playlistID == nil && browseID == nil }

        init() {}

        init?(endpoint: JSONValue) {
            if let watch = endpoint["watchEndpoint"] ?? endpoint["watchPlaylistEndpoint"] {
                videoID = watch["videoId"]?.string
                playlistID = watch["playlistId"]?.string
                // `RD…` is a generated radio rather than a saved list, and
                // saying so is the difference between a tile that means
                // something and a tile called "Mix".
                kind = playlistID?.hasPrefix("RD") == true
                    ? .mix
                    : (videoID != nil ? .song : .playlist)
            }

            if let browse = endpoint["browseEndpoint"], let id = browse["browseId"]?.string {
                let pageType = browse[
                    "browseEndpointContextSupportedConfigs",
                    "browseEndpointContextMusicConfig",
                    "pageType"
                ]?.string

                switch pageType {
                case "MUSIC_PAGE_TYPE_ALBUM":
                    browseID = id
                    kind = .album
                case "MUSIC_PAGE_TYPE_ARTIST", "MUSIC_PAGE_TYPE_USER_CHANNEL":
                    browseID = id
                    kind = .artist
                case "MUSIC_PAGE_TYPE_PLAYLIST":
                    // A playlist arrives as its id with `VL` glued on the
                    // front — the browse-page identifier, not the playlist
                    // identifier. Handing that to a `?list=` URL opens
                    // nothing.
                    playlistID = id.hasPrefix("VL") ? String(id.dropFirst(2)) : id
                    kind = .playlist
                default:
                    // An unknown page type is still navigable — Cue just does
                    // not know what to call it.
                    browseID = id
                }
            }

            if isEmpty { return nil }
        }
    }

    /// The smallest thumbnail that still looks sharp on a Retina tile.
    ///
    /// These arrive as an ascending ladder from 60px to 1000-odd. A grid tile
    /// is around 110 points, so 226 is the right rung; taking the last one
    /// downloads a megabyte to draw a thumbnail.
    static func thumbnailURL(in renderer: JSONValue) -> URL? {
        guard let thumbnails = renderer.firstValue(forKey: "thumbnails")?.array else { return nil }

        let candidates = thumbnails.compactMap { entry -> (url: String, width: Int)? in
            guard let url = entry["url"]?.string else { return nil }
            return (url, entry["width"]?.int ?? 0)
        }

        let sharp = candidates.first { $0.width >= 226 } ?? candidates.last
        return sharp.flatMap { URL(string: $0.url) }
    }

    /// Keeps the first occurrence of each destination.
    ///
    /// A single response repeats itself constantly — the same album in a
    /// carousel and again in a shelf below it — and the home feed is mostly
    /// repetition by design.
    static func deduplicated(_ items: [MusicItem]) -> [MusicItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }
}
