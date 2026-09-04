import Foundation
import Testing

@testable import Cue

/// Where an item sends you.
///
/// Worth testing properly because every one of these is a URL a user clicks
/// and a wrong one fails silently — the browser opens, YouTube Music shows
/// something, and it is simply not the thing that was clicked.
@Suite("Playback URLs")
struct MusicItemTests {
    @Test("A track inside a playlist keeps its context")
    func trackInPlaylist() {
        let item = MusicItem(
            id: "x", title: "Weightless", kind: .song,
            videoID: "abc123", playlistID: "OLAK5uy_x", source: .ytMusic
        )

        let url = try! #require(item.playbackURL)
        #expect(url.absoluteString == "https://music.youtube.com/watch?v=abc123&list=OLAK5uy_x")
    }

    @Test("A bare track opens on its own")
    func bareTrack() {
        let item = MusicItem(id: "x", title: "A", kind: .video, videoID: "abc123", source: .dataAPI)
        #expect(item.playbackURL?.absoluteString == "https://music.youtube.com/watch?v=abc123")
    }

    @Test("A playlist opens on a watch page, so it plays")
    func playlist() {
        // Not `/playlist?list=`, which is the playlist's *page*: it opens,
        // lists the tracks and plays nothing. Clicking a playlist tile
        // appeared to do nothing at all for exactly this reason.
        let item = MusicItem(id: "x", title: "A", kind: .playlist, playlistID: "PL123", source: .dataAPI)
        #expect(item.playbackURL?.absoluteString == "https://music.youtube.com/watch?list=PL123")
    }

    @Test("An album goes to a browse page")
    func album() {
        let item = MusicItem(id: "x", title: "A", kind: .album, browseID: "MPREb_9", source: .ytMusic)
        #expect(item.playbackURL?.absoluteString == "https://music.youtube.com/browse/MPREb_9")
    }

    @Test("An artist goes to a channel page, not a browse page")
    func artist() {
        // The distinction that is easy to get wrong: a `UC…` id under
        // `/browse/` lands on an error page rather than the artist.
        let item = MusicItem(id: "x", title: "A", kind: .artist, browseID: "UCabc", source: .ytMusic)
        #expect(item.playbackURL?.absoluteString == "https://music.youtube.com/channel/UCabc")
    }

    @Test("An item with nowhere to go has no URL")
    func nothingToOpen() {
        let item = MusicItem(id: "x", title: "A", kind: .song, source: .dataAPI)
        #expect(item.playbackURL == nil)
    }

    @Test("The same track from two providers is recognised as one thing")
    func sameContentAcrossProviders() {
        let official = MusicItem(id: "dataAPI:video:v1", title: "A", kind: .video, videoID: "v1", source: .dataAPI)
        let internalOne = MusicItem(id: "ytMusic:song:v1", title: "A", kind: .song, videoID: "v1", source: .ytMusic)

        #expect(official.isSameContent(as: internalOne))
        // …but they are still distinct values, so a set keeps both until
        // something actively chooses.
        #expect(official != internalOne)
    }

    @Test("Two items with no identifiers in common are not the same thing")
    func differentContent() {
        let a = MusicItem(id: "1", title: "Same Title", kind: .playlist, playlistID: "PL1", source: .dataAPI)
        let b = MusicItem(id: "2", title: "Same Title", kind: .album, browseID: "MPREb_1", source: .ytMusic)
        #expect(!a.isSameContent(as: b))
    }

    @Test("A pinned tile survives being written down and read back")
    func codableRoundTrip() throws {
        let item = MusicItem(
            id: "ytMusic:playlist:PL1", title: "Late Night", subtitle: "42 songs",
            kind: .playlist, playlistID: "PL1",
            thumbnailURL: URL(string: "https://example.invalid/a.jpg"), source: .ytMusic
        )

        let data = try JSONEncoder().encode([MusicItem?.some(item), nil])
        let restored = try JSONDecoder().decode([MusicItem?].self, from: data)

        #expect(restored.count == 2)
        #expect(restored[0] == item)
        #expect(restored[1] == nil)
    }
}
