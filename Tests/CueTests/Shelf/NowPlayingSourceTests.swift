import CoreGraphics
import Testing

@testable import Cue

/// When the closed shelf grows its now-playing wings, and on which display.
@MainActor
struct NowPlayingSourceTests {
    // MARK: - Whether there is anything to show

    @Test func `a track playing in Cue is shown`() {
        #expect(NowPlayingSource.isShowable(playsInApp: true, videoID: "dQw4w9WgXcQ"))
    }

    @Test func `nothing is shown when playback goes to the browser`() {
        // Cue's own page never plays then, so whatever it last said is not
        // what is sounding.
        #expect(!NowPlayingSource.isShowable(playsInApp: false, videoID: "dQw4w9WgXcQ"))
    }

    @Test func `nothing is shown before the player has reported a track`() {
        #expect(!NowPlayingSource.isShowable(playsInApp: true, videoID: nil))
    }

    @Test func `nothing is shown when the page is not on a track`() {
        // The player keeps its last report when the page wanders off to the
        // home page; that report has no video ID.
        #expect(!NowPlayingSource.isShowable(playsInApp: true, videoID: ""))
    }

    @Test func `a fixed source hands back what it was given`() {
        let track = NowPlayingSource.Track(
            title: "Song",
            artist: "Artist",
            artworkURL: nil,
            isPlaying: true,
            videoID: "abc"
        )

        #expect(NowPlayingSource.fixed(track).track() == track)
        #expect(NowPlayingSource.fixed(nil).track() == nil)
    }

    // MARK: - Which display

    private func screen(_ id: CGDirectDisplayID, notch: Bool) -> ScreenGeometry {
        ScreenGeometry(
            id: id,
            frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
            notchSize: notch ? CGSize(width: 200, height: 32) : nil,
            topInset: notch ? 32 : 0,
            menuBarHeight: notch ? 32 : 24
        )
    }

    @Test func `the notched display shows what is playing`() {
        let displays = [screen(1, notch: false), screen(2, notch: true), screen(3, notch: false)]

        #expect(DisplayCoordinator.nowPlayingDisplay(among: displays) == 2)
    }

    @Test func `without a notch, the menu bar's display shows it`() {
        let displays = [screen(4, notch: false), screen(5, notch: false)]

        #expect(DisplayCoordinator.nowPlayingDisplay(among: displays) == 4)
    }

    @Test func `no displays, no wings`() {
        #expect(DisplayCoordinator.nowPlayingDisplay(among: []) == nil)
    }
}
