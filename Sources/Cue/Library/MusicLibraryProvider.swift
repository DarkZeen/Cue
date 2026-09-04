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
}

extension MusicLibraryProvider {
    /// Most providers have nothing timely to offer, and the ones that do
    /// override it. Saves every call site an `if provider.hasRecents`.
    func recent() async throws -> [MusicItem] { [] }
}
