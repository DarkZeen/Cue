import Foundation
import Testing

@testable import Cue

/// The renderer parser, against the shapes the real endpoints return.
///
/// These fixtures are trimmed but structurally faithful — the nesting, the key
/// names and the wrapping are what the service actually sends. That is the
/// whole value of them: this is the part of Cue with no compiler and no
/// contract behind it, so the tests are the contract.
@Suite("YouTube Music renderers")
struct YTMusicParsingTests {
    private func parse(_ text: String) throws -> JSONValue {
        try JSONValue(data: Data(text.utf8))
    }

    // MARK: - Rows

    private let songRow = """
        {"musicResponsiveListItemRenderer": {
          "thumbnail": {"musicThumbnailRenderer": {"thumbnail": {"thumbnails": [
            {"url": "https://example.invalid/small.jpg", "width": 60, "height": 60},
            {"url": "https://example.invalid/large.jpg", "width": 226, "height": 226}
          ]}}},
          "flexColumns": [
            {"musicResponsiveListItemFlexColumnRenderer": {"text": {"runs": [
              {"text": "Weightless"}
            ]}}},
            {"musicResponsiveListItemFlexColumnRenderer": {"text": {"runs": [
              {"text": "Marconi Union"}, {"text": " • "}, {"text": "Ambient"}
            ]}}}
          ],
          "overlay": {"musicItemThumbnailOverlayRenderer": {"content": {"musicPlayButtonRenderer": {
            "playNavigationEndpoint": {"watchEndpoint": {
              "videoId": "abc123", "playlistId": "OLAK5uy_album"
            }}
          }}}},
          "playlistItemData": {"videoId": "abc123"}
        }}
        """

    @Test("A song row keeps its playlist context")
    func songRowParses() throws {
        let renderer = try #require(parse(songRow)["musicResponsiveListItemRenderer"])
        let item = try #require(YTMusicInternalProvider.row(from: renderer))

        #expect(item.title == "Weightless")
        #expect(item.subtitle == "Marconi Union • Ambient")
        #expect(item.videoID == "abc123")
        // From the play button rather than `playlistItemData`: the play
        // button's endpoint is what makes the rest of the album follow on.
        #expect(item.playlistID == "OLAK5uy_album")
        #expect(item.kind == .song)
        #expect(item.source == .ytMusic)
    }

    @Test("A row falls back to playlistItemData when there is no play button")
    func rowFallsBackToPlaylistItemData() throws {
        let stripped = """
            {"flexColumns": [
              {"musicResponsiveListItemFlexColumnRenderer": {"text": {"runs": [{"text": "Orphan"}]}}}
            ],
            "playlistItemData": {"videoId": "xyz789"}}
            """
        let item = try #require(YTMusicInternalProvider.row(from: try parse(stripped)))

        #expect(item.videoID == "xyz789")
        #expect(item.playlistID == nil)
        #expect(item.kind == .song)
    }

    @Test("A row with a title and nowhere to go is dropped")
    func rowWithoutDestination() throws {
        let header = """
            {"flexColumns": [
              {"musicResponsiveListItemFlexColumnRenderer": {"text": {"runs": [{"text": "Top result"}]}}}
            ]}
            """
        #expect(YTMusicInternalProvider.row(from: try parse(header)) == nil)
    }

    // MARK: - Cards

    @Test("A playlist card loses the VL prefix")
    func playlistCard() throws {
        // The single most consequential detail in this file. A browse id is
        // `VL` + the playlist id, and handing the browse id to a `?list=` URL
        // opens nothing at all.
        let card = """
            {"title": {"runs": [{"text": "Late Night Tapes"}]},
             "subtitle": {"runs": [{"text": "Playlist"}, {"text": " • "}, {"text": "42 songs"}]},
             "navigationEndpoint": {"browseEndpoint": {
               "browseId": "VLPLabc123",
               "browseEndpointContextSupportedConfigs": {"browseEndpointContextMusicConfig": {
                 "pageType": "MUSIC_PAGE_TYPE_PLAYLIST"
               }}
             }}}
            """
        let item = try #require(YTMusicInternalProvider.card(from: try parse(card)))

        #expect(item.title == "Late Night Tapes")
        #expect(item.playlistID == "PLabc123")
        #expect(item.browseID == nil)
        #expect(item.kind == .playlist)
        #expect(item.playbackURL?.absoluteString == "https://music.youtube.com/watch?list=PLabc123")
    }

    @Test("An album card stays a browse page")
    func albumCard() throws {
        let card = """
            {"title": {"runs": [{"text": "Selected Ambient Works"}]},
             "navigationEndpoint": {"browseEndpoint": {
               "browseId": "MPREb_abc",
               "browseEndpointContextSupportedConfigs": {"browseEndpointContextMusicConfig": {
                 "pageType": "MUSIC_PAGE_TYPE_ALBUM"
               }}
             }}}
            """
        let item = try #require(YTMusicInternalProvider.card(from: try parse(card)))

        #expect(item.kind == .album)
        #expect(item.browseID == "MPREb_abc")
        #expect(item.playlistID == nil)
    }

    @Test("An artist card becomes a channel")
    func artistCard() throws {
        let card = """
            {"title": {"runs": [{"text": "Marconi Union"}]},
             "navigationEndpoint": {"browseEndpoint": {
               "browseId": "UCabc",
               "browseEndpointContextSupportedConfigs": {"browseEndpointContextMusicConfig": {
                 "pageType": "MUSIC_PAGE_TYPE_ARTIST"
               }}
             }}}
            """
        let item = try #require(YTMusicInternalProvider.card(from: try parse(card)))

        #expect(item.kind == .artist)
        #expect(item.playbackURL?.absoluteString == "https://music.youtube.com/channel/UCabc")
    }

    @Test("A radio is told apart from a saved playlist")
    func radioIsAMix() throws {
        let card = """
            {"title": {"runs": [{"text": "Ambient Radio"}]},
             "navigationEndpoint": {"watchEndpoint": {"videoId": "v1", "playlistId": "RDAMVMv1"}}}
            """
        let item = try #require(YTMusicInternalProvider.card(from: try parse(card)))
        #expect(item.kind == .mix)
    }

    @Test("The New Playlist button is not a playlist")
    func newPlaylistButtonIsDropped() throws {
        // It arrives wearing the same renderer as a real playlist, in the same
        // grid, and the only thing that tells it apart is having nowhere to go.
        let button = #"{"title": {"runs": [{"text": "New playlist"}]}}"#
        #expect(YTMusicInternalProvider.card(from: try parse(button)) == nil)
    }

    // MARK: - Whole responses

    @Test("Items are found however deeply the response wraps them")
    func itemsSurviveWrapping() throws {
        // The point of walking by renderer name rather than by path: this is
        // four levels deeper than a search response, and it changes nothing.
        let response = """
            {"contents": {"tabbedSearchResultsRenderer": {"tabs": [{"tabRenderer": {"content": {
              "sectionListRenderer": {"contents": [{"musicShelfRenderer": {"contents": [
                \(songRow)
              ]}}]}
            }}}]}}}
            """
        let items = YTMusicInternalProvider.items(in: try parse(response))

        #expect(items.count == 1)
        #expect(items.first?.title == "Weightless")
    }

    @Test("A response that repeats itself yields each thing once")
    func duplicatesAreCollapsed() throws {
        let response = """
            {"a": {"shelf": [\(songRow)]}, "b": {"carousel": [\(songRow)]}}
            """
        #expect(YTMusicInternalProvider.items(in: try parse(response)).count == 1)
    }

    @Test("An unrecognisable response yields nothing rather than throwing")
    func garbageIsSurvivable() throws {
        // The failure mode that matters: Google changes something, and Cue
        // shows an empty list instead of crashing on a force-unwrap.
        let response = #"{"responseContext": {}, "contents": {"somethingNew": [1, 2, 3]}}"#
        #expect(YTMusicInternalProvider.items(in: try parse(response)).isEmpty)
    }

    // MARK: - Thumbnails

    @Test("The thumbnail chosen is the smallest one that is still sharp")
    func thumbnailPicksTheRightRung() throws {
        let renderer = try #require(parse(songRow)["musicResponsiveListItemRenderer"])
        let url = try #require(YTMusicInternalProvider.thumbnailURL(in: renderer))
        #expect(url.absoluteString == "https://example.invalid/large.jpg")
    }

    @Test("When nothing is big enough, the biggest available is used")
    func thumbnailFallsBackToLargest() throws {
        let renderer = try parse("""
            {"thumbnail": {"thumbnails": [
              {"url": "https://example.invalid/a.jpg", "width": 60},
              {"url": "https://example.invalid/b.jpg", "width": 120}
            ]}}
            """)
        let url = try #require(YTMusicInternalProvider.thumbnailURL(in: renderer))
        #expect(url.absoluteString == "https://example.invalid/b.jpg")
    }

    @Test("No thumbnail is not an error")
    func noThumbnail() throws {
        #expect(YTMusicInternalProvider.thumbnailURL(in: try parse("{}")) == nil)
    }
}
