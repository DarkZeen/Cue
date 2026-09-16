import Foundation
import Testing

@testable import Cue

@Suite("Merging results")
struct MergeTests {
    private func song(_ videoID: String, _ title: String, from source: ProviderID) -> MusicItem {
        MusicItem(id: "\(source.rawValue):\(videoID)", title: title, kind: .song, videoID: videoID, source: source)
    }

    @Test("The same track from two backends appears once")
    func duplicatesAcrossProviders() {
        // The most visible possible symptom of a merged search: the same song
        // twice, once with the artist's name and once without.
        let first = [song("v1", "Weightless", from: .ytMusic)]
        let second = [song("v1", "Weightless - Marconi Union", from: .dataAPI)]

        let merged = LibraryCoordinator.merge(first, with: second)

        #expect(merged.count == 1)
        #expect(merged.first?.source == .ytMusic)
    }

    @Test("The better backend's ordering is preserved")
    func orderIsPreserved() {
        let first = [song("a", "A", from: .ytMusic), song("b", "B", from: .ytMusic)]
        let second = [song("c", "C", from: .dataAPI)]

        let merged = LibraryCoordinator.merge(first, with: second)

        #expect(merged.map(\.videoID) == ["a", "b", "c"])
    }

    @Test("Different tracks with the same title both survive")
    func distinctItemsAreKept() {
        let merged = LibraryCoordinator.merge(
            [song("a", "Intro", from: .ytMusic)],
            with: [song("b", "Intro", from: .dataAPI)]
        )
        #expect(merged.count == 2)
    }
}

@Suite("Session cookies")
struct SessionTests {
    @Test("A cookie value containing = is not truncated")
    func cookieValuesKeepTheirPadding() {
        // Base64 padding in a cookie value is routine, and splitting on every
        // `=` silently produces a session that authenticates as nobody.
        let jar = YTMusicSessionService.parse(cookieHeader: "SAPISID=abc; SID=x==; HSID=y")

        #expect(jar["SAPISID"] == "abc")
        #expect(jar["SID"] == "x==")
        #expect(jar["HSID"] == "y")
    }

    @Test("Whitespace around the separators is ignored")
    func cookieWhitespace() {
        let jar = YTMusicSessionService.parse(cookieHeader: "  A=1;B=2 ;  C=3")
        #expect(jar == ["A": "1", "B": "2", "C": "3"])
    }

    @Test("A malformed pair is skipped rather than stored empty")
    func malformedCookie() {
        let jar = YTMusicSessionService.parse(cookieHeader: "A=1; broken; B=2")
        #expect(jar.count == 2)
    }
}

@Suite("Title decoding")
struct HTMLEntityTests {
    @Test("Entities the Data API returns are decoded")
    func decodesEntities() {
        #expect("Rock &amp; Roll".decodingHTMLEntities() == "Rock & Roll")
        #expect("It&#39;s Fine".decodingHTMLEntities() == "It's Fine")
        #expect("&quot;Live&quot;".decodingHTMLEntities() == "\"Live\"")
    }

    @Test("A title with no entities is returned untouched")
    func leavesPlainTitlesAlone() {
        #expect("Weightless".decodingHTMLEntities() == "Weightless")
    }
}

@Suite("Panel geometry")
struct LayoutTests {
    @Test("The window is tall enough for either layout")
    func windowFitsBothModes() {
        // The window's frame never changes, so it has to be built at the
        // tallest the contents can be. If this fails, the grid is clipped.
        #expect(CueLayout.panelHeight >= CueLayout.gridModeHeight)
        #expect(CueLayout.panelHeight >= CueLayout.resultsModeHeight(count: 99))
    }

    @Test("A long results list stops growing at the visible maximum")
    func resultsHeightIsBounded() {
        let seven = CueLayout.resultsModeHeight(count: CueLayout.maximumVisibleResults)
        #expect(CueLayout.resultsModeHeight(count: 500) == seven)
    }

    @Test("An empty results list still has a row's worth of height")
    func emptyResultsHaveHeight() {
        // Somewhere to draw "No results", rather than a panel that collapses
        // to the search field and leaves the message nowhere to go.
        #expect(CueLayout.resultsModeHeight(count: 0) == CueLayout.resultsModeHeight(count: 1))
    }

    @Test("Three tiles and their gaps fill the panel exactly")
    func gridFillsTheWidth() {
        let used = CueLayout.tileWidth * 3
            + CueLayout.tileSpacing * 2
            + CueLayout.outerPadding * 2
        #expect(abs(used - CueLayout.panelWidth) < 0.001)
    }
}

@Suite("Explore pages")
struct ExploreFilterTests {
    private func item(
        _ id: String,
        kind: MusicItemKind,
        videoID: String? = nil,
        browseID: String? = nil
    ) -> MusicItem {
        MusicItem(
            id: id,
            title: id,
            kind: kind,
            videoID: videoID,
            browseID: browseID,
            source: .ytMusic
        )
    }

    @Test("The first page keeps only what plays when clicked")
    func songsOnly() {
        // The home feed's actual shape: a couple of tracks buried in shelves of
        // playlists, mixes and artist pages. All of those are containers you go
        // into, which is the one thing a speed dial must never be.
        let feed = [
            item("mix", kind: .mix),
            item("song", kind: .song, videoID: "v1"),
            item("playlist", kind: .playlist),
            item("artist", kind: .artist, browseID: "UC1"),
            item("album", kind: .album, browseID: "MPREb_1"),
            item("video", kind: .video, videoID: "v2")
        ]

        let songs = LibraryCoordinator.songs(in: feed)

        #expect(songs.map(\.id) == ["song", "video"])
    }

    @Test("A song with no video id is not a song")
    func songsMustBePlayable() {
        // Kind alone is not enough. A row parsed from a shelf can claim to be a
        // song and carry only a playlist context, and putting that on the grid
        // is a tile that opens a page instead of playing.
        let claimed = [item("claims", kind: .song)]

        #expect(LibraryCoordinator.songs(in: claimed).isEmpty)
    }

    @Test("The third page keeps only albums")
    func albumsOnly() {
        let feed = [
            item("song", kind: .song, videoID: "v1"),
            item("album", kind: .album, browseID: "MPREb_1"),
            item("playlist", kind: .playlist)
        ]

        #expect(LibraryCoordinator.albums(in: feed).map(\.id) == ["album"])
    }
}

@Suite("Outside the catalogue")
struct CatalogueBadgeTests {
    /// The rule, without the coordinator around it: an item is marked when the
    /// Music backend was asked and did not return it.
    private func isOutside(_ source: ProviderID, videoID: String?, musicConnected: Bool) -> Bool {
        guard musicConnected else { return false }
        return source == .dataAPI && videoID != nil
    }

    @Test("A video only the official API knew about is marked")
    func officialOnlyIsMarked() {
        #expect(isOutside(.dataAPI, videoID: "abc", musicConnected: true))
    }

    @Test("Anything YouTube Music returned is not")
    func musicResultsAreNotMarked() {
        #expect(!isOutside(.ytMusic, videoID: "abc", musicConnected: true))
    }

    @Test("With no Music session, nothing is marked")
    func nothingIsMarkedWithoutTheComparison() {
        // Everything arrives from the official API then, so the mark would be
        // on every row — which says nothing, and would be wrong besides: none
        // of it has been ruled out by anybody.
        #expect(!isOutside(.dataAPI, videoID: "abc", musicConnected: false))
    }

    @Test("A playlist is not marked, having no video to play elsewhere")
    func containersAreNotMarked() {
        #expect(!isOutside(.dataAPI, videoID: nil, musicConnected: true))
    }
}
