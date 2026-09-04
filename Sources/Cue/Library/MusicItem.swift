import Foundation

/// Which backend an item came from.
///
/// Kept on the item rather than inferred, because merged results have to be
/// de-duplicated across providers and, when the same track arrives twice, the
/// richer one has to win.
enum ProviderID: String, Hashable, Codable, Sendable {
    /// The official YouTube Data API. OAuth, documented, stable.
    case dataAPI
    /// The internal YouTube Music endpoints. Real library, no guarantees.
    case ytMusic
}

/// What a result is, which decides how it is opened and how it is drawn.
enum MusicItemKind: String, Hashable, Codable, Sendable {
    case song
    case video
    case album
    case playlist
    case artist
    /// A generated radio or mix. Behaves like a playlist but never appears in
    /// a library listing, so it is worth telling apart.
    case mix

    var symbolName: String {
        switch self {
        case .song: "music.note"
        case .video: "play.rectangle"
        case .album: "square.stack"
        case .playlist: "music.note.list"
        case .artist: "person.wave.2"
        case .mix: "shuffle"
        }
    }
}

/// One thing you can play or pin.
///
/// Deliberately flat and provider-agnostic: the two backends return wildly
/// different JSON and the UI should never learn the difference. Everything
/// below `kind` is optional because YouTube's own data is — a library playlist
/// has no video id, an album has neither, and a search result may be missing a
/// thumbnail entirely.
/// `Codable` because pinned tiles are stored whole rather than by id.
/// A tile has to draw the instant the panel opens — before any provider has
/// been asked anything, and correctly when the network is down — so the title,
/// the subtitle and the thumbnail address are saved alongside the identifier.
struct MusicItem: Identifiable, Hashable, Codable, Sendable {
    /// Stable across launches, and unique across providers: the provider's own
    /// identifier namespaced by which provider it is. Pinned tiles are stored
    /// by this, so it may not be derived from anything that changes — a title,
    /// a position in a list.
    let id: String

    var title: String
    var subtitle: String?
    var kind: MusicItemKind

    /// A single track. Present for songs and videos.
    var videoID: String?
    /// A playlist, an album's playlist, or a radio. `PL…`, `RD…`, `OLAK5uy_…`.
    var playlistID: String?
    /// YouTube Music's internal identifier for a page that is neither — an
    /// album (`MPREb_…`) or an artist (`UC…`). Only the internal provider
    /// produces these, and only it can resolve them.
    var browseID: String?

    var thumbnailURL: URL?
    var source: ProviderID

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        kind: MusicItemKind,
        videoID: String? = nil,
        playlistID: String? = nil,
        browseID: String? = nil,
        thumbnailURL: URL? = nil,
        source: ProviderID
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.videoID = videoID
        self.playlistID = playlistID
        self.browseID = browseID
        self.thumbnailURL = thumbnailURL
        self.source = source
    }

    /// Where this item lives on the web.
    ///
    /// Everything hands off to YouTube Music rather than youtube.com, even for
    /// results the Data API returned, because that is where the queue, the
    /// radio and the rest of the listening experience are. A video id plus a
    /// playlist id is the good case: it starts the track *within* its list, so
    /// what plays afterwards is the rest of the album rather than whatever
    /// autoplay invents.
    var playbackURL: URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "music.youtube.com"

        switch (videoID, playlistID, browseID) {
        case (let video?, let list?, _):
            components.path = "/watch"
            components.queryItems = [
                URLQueryItem(name: "v", value: video),
                URLQueryItem(name: "list", value: list),
            ]
        case (let video?, nil, _):
            components.path = "/watch"
            components.queryItems = [URLQueryItem(name: "v", value: video)]
        case (nil, let list?, _):
            components.path = "/playlist"
            components.queryItems = [URLQueryItem(name: "list", value: list)]
        case (nil, nil, let browse?):
            // An artist is a channel and lives at a different path. `/browse/`
            // is where albums and everything else Music-internal lives, and
            // the two are not interchangeable — a `UC…` id under `/browse/`
            // lands on an error page.
            components.path = browse.hasPrefix("UC") ? "/channel/\(browse)" : "/browse/\(browse)"
        default:
            return nil
        }

        return components.url
    }

    /// Whether two items are the same thing seen through different providers.
    ///
    /// Not `==`: identity includes the provider, deliberately, so that a set of
    /// items keeps both copies until something actively chooses between them.
    /// This is that choice, and it is made on the only identifiers both
    /// backends agree on.
    func isSameContent(as other: MusicItem) -> Bool {
        if let a = videoID, let b = other.videoID { return a == b }
        if let a = playlistID, let b = other.playlistID { return a == b }
        if let a = browseID, let b = other.browseID { return a == b }
        return false
    }
}
