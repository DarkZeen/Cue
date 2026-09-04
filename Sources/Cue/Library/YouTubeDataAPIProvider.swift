import Foundation

/// The official backend: YouTube Data API v3, over OAuth.
///
/// This is the one that ships on by default and the one that is allowed to be
/// boring. It cannot see a YouTube Music library as such — there is no
/// endpoint for "liked songs" as Music understands them, no listening history
/// since 2016, and no mixes — but it can see the account's playlists and its
/// liked videos, which for most people is most of what the grid should hold.
///
/// Everything it returns is still handed off to music.youtube.com, so the
/// difference the user notices is which things are *findable*, not where they
/// play.
final class YouTubeDataAPIProvider: MusicLibraryProvider {
    let id = ProviderID.dataAPI

    private let auth: GoogleOAuthService
    private let session: URLSession
    private let logger = Diagnostics.logger("youtube-data-api")

    private static let base = URL(string: "https://www.googleapis.com/youtube/v3/")!

    /// The account's "liked videos" playlist id, which has to be asked for
    /// once before it can be listed. Cached because it never changes for an
    /// account and the lookup costs a request.
    private var likedPlaylistID: String?

    init(auth: GoogleOAuthService, session: URLSession = .shared) {
        self.auth = auth
        self.session = session
    }

    var isConnected: Bool { auth.isConnected }

    // MARK: - Search

    func search(_ query: String) async throws -> [MusicItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // `search.list` costs 100 quota units against a default budget of
        // 10,000 a day — a hundred searches. That is the single reason the
        // search field is debounced rather than fired on every keystroke, and
        // why `maxResults` is 20 rather than 50: the cost is per call, but a
        // shorter list is a faster one to draw and to read.
        let response: SearchResponse = try await get(
            "search",
            query: [
                "part": "snippet",
                "type": "video,playlist",
                "maxResults": "20",
                "q": trimmed,
            ]
        )

        return response.items.compactMap(Self.item(from:))
    }

    // MARK: - Library

    func library() async throws -> [MusicItem] {
        async let playlists = ownPlaylists()
        async let liked = likedVideosPlaylist()

        // Liked songs first: it is the one row in this list that is not
        // something the user had to build, and it is the one they reach for.
        return try await [liked].compactMap(\.self) + playlists
    }

    private func ownPlaylists() async throws -> [MusicItem] {
        let response: PlaylistListResponse = try await get(
            "playlists",
            query: [
                "part": "snippet,contentDetails",
                "mine": "true",
                "maxResults": "50",
            ]
        )

        return response.items.map { playlist in
            MusicItem(
                id: "\(ProviderID.dataAPI.rawValue):playlist:\(playlist.id)",
                title: playlist.snippet.title,
                subtitle: playlist.contentDetails.map { Self.trackCount($0.itemCount) },
                kind: .playlist,
                playlistID: playlist.id,
                thumbnailURL: playlist.snippet.thumbnails?.best,
                source: .dataAPI
            )
        }
    }

    /// The account's liked videos, as a single pinnable playlist.
    ///
    /// `LL…` is a real playlist id that music.youtube.com will open, which is
    /// why this can be one tile rather than a list of individual tracks.
    private func likedVideosPlaylist() async throws -> MusicItem? {
        let playlistID: String
        if let likedPlaylistID {
            playlistID = likedPlaylistID
        } else {
            let response: ChannelListResponse = try await get(
                "channels",
                query: ["part": "contentDetails", "mine": "true"]
            )
            guard let likes = response.items.first?.contentDetails.relatedPlaylists.likes,
                  !likes.isEmpty
            else {
                // Some accounts genuinely have no likes playlist exposed — a
                // brand account, mostly. Not an error; there is simply no tile.
                logger.notice("This account exposes no liked-videos playlist.")
                return nil
            }
            likedPlaylistID = likes
            playlistID = likes
        }

        return MusicItem(
            id: "\(ProviderID.dataAPI.rawValue):playlist:\(playlistID)",
            title: "Liked",
            subtitle: "Your liked videos",
            kind: .playlist,
            playlistID: playlistID,
            source: .dataAPI
        )
    }

    // MARK: - Requests

    private func get<Response: Decodable>(
        _ path: String,
        query: [String: String]
    ) async throws -> Response {
        guard auth.isConnected else { throw MusicLibraryError.notAuthorized }

        let token = try await auth.currentAccessToken()

        var components = URLComponents(
            url: Self.base.appending(path: path),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }

        guard let url = components.url else {
            throw MusicLibraryError.unexpectedResponse("could not build a request URL")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            if Diagnostics.logsNetwork {
                logger.debug("GET \(path, privacy: .public) → \(status, privacy: .public), \(data.count, privacy: .public) bytes")
            }

            guard (200..<300).contains(status) else {
                throw Self.error(for: status, body: data)
            }

            return try JSONDecoder().decode(Response.self, from: data)
        } catch let error as MusicLibraryError {
            throw error
        } catch let error as DecodingError {
            throw MusicLibraryError.unexpectedResponse(String(describing: error))
        } catch {
            throw MusicLibraryError.transport(error)
        }
    }

    /// Turns an HTTP failure into something the UI can say out loud.
    ///
    /// The distinction that matters is 403-because-quota from
    /// 403-because-token: they look identical in the status line and mean
    /// completely different things to the person reading the message. The
    /// reason string in the body is the only thing that tells them apart.
    private static func error(for status: Int, body: Data) -> MusicLibraryError {
        let failure = try? JSONDecoder().decode(APIErrorResponse.self, from: body)
        let reason = failure?.error.errors?.first?.reason ?? ""

        switch status {
        case 401:
            return .authenticationExpired
        case 403 where reason == "quotaExceeded" || reason == "rateLimitExceeded":
            return .quotaExceeded
        case 403:
            return .authenticationExpired
        default:
            return .unexpectedResponse(failure?.error.message ?? "HTTP \(status)")
        }
    }

    // MARK: - Mapping

    private static func item(from result: SearchResult) -> MusicItem? {
        let snippet = result.snippet

        if let videoID = result.id.videoId {
            return MusicItem(
                id: "\(ProviderID.dataAPI.rawValue):video:\(videoID)",
                title: snippet.title.decodingHTMLEntities(),
                subtitle: snippet.channelTitle?.decodingHTMLEntities(),
                // The Data API does not distinguish a song from a video, and
                // guessing from the title is how you end up calling a live set
                // a single. Everything from here is a video; the internal
                // provider is the one that knows better.
                kind: .video,
                videoID: videoID,
                thumbnailURL: snippet.thumbnails?.best,
                source: .dataAPI
            )
        }

        if let playlistID = result.id.playlistId {
            return MusicItem(
                id: "\(ProviderID.dataAPI.rawValue):playlist:\(playlistID)",
                title: snippet.title.decodingHTMLEntities(),
                subtitle: snippet.channelTitle?.decodingHTMLEntities(),
                kind: .playlist,
                playlistID: playlistID,
                thumbnailURL: snippet.thumbnails?.best,
                source: .dataAPI
            )
        }

        // A channel result. Cue has nowhere to send one — music.youtube.com
        // does not take a YouTube channel id — so it is dropped rather than
        // shown as a row that does nothing when clicked.
        return nil
    }

    private static func trackCount(_ count: Int) -> String {
        count == 1 ? "1 track" : "\(count) tracks"
    }

    // MARK: - Wire types

    private struct Thumbnails: Decodable {
        struct Thumbnail: Decodable { let url: String }
        let `default`: Thumbnail?
        let medium: Thumbnail?
        let high: Thumbnail?

        /// Medium is 320×180, which is the smallest that does not look soft on
        /// a Retina tile. `high` is 480 and rarely worth the bytes for a row.
        var best: URL? {
            [medium, high, `default`].compactMap(\.self).first.flatMap { URL(string: $0.url) }
        }
    }

    private struct Snippet: Decodable {
        let title: String
        let channelTitle: String?
        let thumbnails: Thumbnails?
    }

    private struct SearchResult: Decodable {
        struct Identifier: Decodable {
            let videoId: String?
            let playlistId: String?
        }
        let id: Identifier
        let snippet: Snippet
    }

    private struct SearchResponse: Decodable {
        let items: [SearchResult]
    }

    private struct Playlist: Decodable {
        struct ContentDetails: Decodable { let itemCount: Int }
        let id: String
        let snippet: Snippet
        let contentDetails: ContentDetails?
    }

    private struct PlaylistListResponse: Decodable {
        let items: [Playlist]
    }

    private struct ChannelListResponse: Decodable {
        struct Channel: Decodable {
            struct ContentDetails: Decodable {
                struct RelatedPlaylists: Decodable { let likes: String? }
                let relatedPlaylists: RelatedPlaylists
            }
            let contentDetails: ContentDetails
        }
        let items: [Channel]
    }

    private struct APIErrorResponse: Decodable {
        struct Failure: Decodable {
            struct Detail: Decodable { let reason: String? }
            let message: String?
            let errors: [Detail]?
        }
        let error: Failure
    }
}

extension String {
    /// The Data API returns titles with HTML entities in them — `&amp;`,
    /// `&#39;` — because the field was always meant for a web page. Drawing
    /// them raw in a native list is the single most obvious sign that nobody
    /// looked at the results.
    func decodingHTMLEntities() -> String {
        guard contains("&") else { return self }

        var output = self
        let named = [
            "&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
            "&lt;": "<", "&gt;": ">", "&nbsp;": "\u{00A0}",
        ]
        for (entity, character) in named {
            output = output.replacingOccurrences(of: entity, with: character)
        }
        return output
    }
}
