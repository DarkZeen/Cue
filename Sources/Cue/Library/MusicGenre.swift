import Foundation

/// One of YouTube Music's moods or genres, as the service names them.
///
/// Fetched rather than listed. A hard-coded list would be a different list in
/// every country and stale by next year — the service knows what it has, and
/// what it calls it in the language the account is set to.
struct MusicGenre: Identifiable, Hashable, Codable, Sendable {
    /// The opaque `params` blob the browse endpoint wants. It is the identity
    /// as well as the address: two genres never share one, and there is nothing
    /// else stable to key on — the title is translated.
    let id: String
    let title: String
}
