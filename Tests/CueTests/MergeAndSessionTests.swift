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
