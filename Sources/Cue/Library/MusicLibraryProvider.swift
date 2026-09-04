import Foundation

/// What can go wrong on the way to a list of songs.
///
/// Every case is one the UI has to say something different about: "sign in"
/// is not "you are out of quota" is not "Google changed the shape of the
/// response". The last one exists because half of this app talks to endpoints
/// nobody promised would stay the same.
enum MusicLibraryError: Error, LocalizedError {
    /// No credentials at all. The provider has never been connected.
    case notAuthorized
    /// Credentials exist but are no longer good — revoked, expired past
    /// refresh, or a signed-out cookie jar.
    case authenticationExpired
    /// The Data API's daily quota. Search costs a hundred units a call, so
    /// this is reachable by an enthusiastic afternoon, not just by abuse.
    case quotaExceeded
    /// Anything the transport failed at.
    case transport(any Error)
    /// A 200 that did not contain what it should have. Almost always the
    /// internal provider, and almost always Google having moved something.
    case unexpectedResponse(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            "Not signed in."
        case .authenticationExpired:
            "The connection expired — sign in again in Settings."
        case .quotaExceeded:
            "YouTube's daily API quota is used up. It resets at midnight Pacific."
        case .transport(let error):
            error.localizedDescription
        case .unexpectedResponse(let detail):
            "YouTube returned something unexpected (\(detail))."
        }
    }
}

/// One source of music, official or otherwise.
///
/// The whole point of the protocol is that `YTMusicInternalProvider` — which
/// is a pile of undocumented JSON and a cookie — can be swapped in, merged
/// with, or dropped entirely without anything above this line noticing. If
/// Google breaks it, `isConnected` goes false and the app carries on with the
/// official one.
protocol MusicLibraryProvider: AnyObject {
    var id: ProviderID { get }

    /// Whether this provider has usable credentials *right now*. Cheap and
    /// synchronous: it is read while drawing.
    var isConnected: Bool { get }

    /// Free-text search.
    func search(_ query: String) async throws -> [MusicItem]

    /// The user's own things — playlists, liked songs, saved albums. What
    /// fills the grid when nothing has been pinned.
    func library() async throws -> [MusicItem]

    /// Recently played, mixes, and anything else the provider considers
    /// timely. Allowed to return nothing; the Data API has no history at all.
    func recent() async throws -> [MusicItem]

    /// The user's liked songs, as individual tracks rather than as the
    /// playlist that holds them.
    ///
    /// Separate from `library()` because the two answer different questions. A
    /// library listing is containers you open; this is songs you play, and the
    /// grid's second page is made of songs.
    func likedSongs() async throws -> [MusicItem]

    /// What the service is recommending, for the Explore grid's first page.
    func recommendations() async throws -> [MusicItem]
    /// Recently released albums and singles.
    func newReleases() async throws -> [MusicItem]
    /// What is rising.
    func charts() async throws -> [MusicItem]

    /// Turns something that merely navigates into something that plays.
    ///
    /// An album's address is a *page* — `/browse/MPREb_…` — so opening one
    /// navigates and stops. Behind every album is a real playlist id, and
    /// resolving it is the difference between a tile that looks at an album and
    /// a tile that plays it. Returns the item unchanged when there is nothing
    /// to resolve.
    func playable(_ item: MusicItem) async -> MusicItem

    /// Saved albums, as containers.
    ///
    /// Deliberately not flattened into tracks: an album is a thing you put on,
    /// and nine albums say more in nine tiles than nine tracks from one of them.
    func albums() async throws -> [MusicItem]
}

extension MusicLibraryProvider {
    /// Most providers have nothing timely to offer, and the ones that do
    /// override it. Saves every call site an `if provider.hasRecents`.
    func recent() async throws -> [MusicItem] { [] }

    /// Nothing, unless a provider can do better. A page that comes back empty
    /// says so; it does not become an error.
    func likedSongs() async throws -> [MusicItem] { [] }
    func albums() async throws -> [MusicItem] { [] }

    func recommendations() async throws -> [MusicItem] { [] }
    func newReleases() async throws -> [MusicItem] { [] }
    func charts() async throws -> [MusicItem] { [] }

    /// Most items already play. Only the internal provider can resolve an
    /// album page, and only it overrides this.
    func playable(_ item: MusicItem) async -> MusicItem { item }
}
