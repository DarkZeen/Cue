import AppKit
import SwiftUI

/// What the shelf knows about Cue's music: read through closures so the shelf
/// never imports the player, and so tests and previews can hand it fixed
/// values.
///
/// `ShelfState` is the only door into the shelf, and the player is on the
/// other side of it. Handing the shelf `PlayerService` itself would make every
/// tray depend on a web view; handing it this makes it depend on four questions
/// and four commands, which is all the closed shelf's wings ever ask.
///
/// Closures that read `@Observable` properties are still tracked when they are
/// called from a view body, so the wings redraw when the track changes without
/// anything here having to be observable itself. Two of them change sixty
/// times a second — `level` and `bands` — and are read only in the leaf view
/// that draws the mark, never in the shelf's own body, which would otherwise
/// lay the notch out again on every frame of audio.
struct NowPlayingSource {
    /// The one track the wings are about. Cue's own `NowPlaying`, less the
    /// parts the shelf has no use for.
    struct Track: Equatable {
        var title: String
        var artist: String?
        var artworkURL: URL?
        var isPlaying: Bool
        var videoID: String
    }

    /// `nil` means no wings.
    var track: @MainActor () -> Track?
    /// 0 to 1. Read only in the leaf wave view.
    var level: @MainActor () -> Double
    /// Low to high, or empty when nothing is listening. Read only in the leaf
    /// wave view.
    var bands: @MainActor () -> [Double]
    /// The cover, if it has arrived. Also reads the provider's `version`, so a
    /// cover landing redraws whoever asked.
    var artwork: @MainActor (URL?) -> NSImage?
    var prefetchArtwork: @MainActor (URL) -> Void
    var togglePlayPause: @MainActor () -> Void
    var next: @MainActor () -> Void
    var previous: @MainActor () -> Void = {}
    /// Video ID in, whether the page took it out.
    var like: @MainActor (String) async -> Bool
    /// Which mark the right wing draws — the one chosen in Settings.
    var markStyle: @MainActor () -> PlaqueAnimation = { .wave }
    /// What the mark answers to — the spectrum, the beat, or the volume.
    var markReaction: @MainActor () -> MarkReaction = { .frequencies }
    /// Party mode's strength, 0 (off) to 1.
    var party: @MainActor () -> Double = { 0 }
    /// The covers' colours, kept for as long as the source is: the wings are
    /// rebuilt every time the shelf opens and closes, and a colour that had
    /// to be worked out again each time would flash white first.
    var tints = ArtworkTintMemory()

    /// Whether Cue's player has anything the wings should be about.
    ///
    /// Only Cue's own player, and only while it is the one playing: with
    /// playback handed to the browser Cue's page never plays, so whatever it
    /// last reported is not what is sounding. And only a real track — the
    /// player keeps its last report when the page wanders off to a home or a
    /// browse page, and that report carries no video ID. `videoID` is `nil`
    /// when there has been no report at all.
    static func isShowable(playsInApp: Bool, videoID: String?) -> Bool {
        guard playsInApp, let videoID else { return false }
        return !videoID.isEmpty
    }

    /// A source that never changes, for previews and render tests.
    static func fixed(_ track: Track?, artwork image: NSImage? = nil) -> NowPlayingSource {
        NowPlayingSource(
            track: { track },
            level: { 0 },
            bands: { [] },
            artwork: { _ in image },
            prefetchArtwork: { _ in },
            togglePlayPause: {},
            next: {},
            like: { _ in true }
        )
    }
}

/// The colours the wings have worked out, and the one they are showing.
///
/// Outlives the wings, which come and go with the shelf: rebuilt, they start
/// from the colour they were showing rather than from white. Keyed by the
/// cover and the ground it was made legible against, and kept small — a
/// session plays a few hundred tracks at most, and a colour is three numbers.
///
/// Observable, because party mode's border is drawn by the shelf rather than
/// the wings and has to change colour when they do.
@MainActor
@Observable
final class ArtworkTintMemory {
    struct Key: Hashable {
        var artworkURL: URL
        var groundLuminance: Double
    }

    /// A cover's two colours: the one the mark wears, and the one party mode
    /// paints beside it. Both `nil` for a cover with no colour worth taking.
    struct CoverColours: Equatable {
        var primary: Color?
        var secondary: Color?

        static let none = CoverColours(primary: nil, secondary: nil)
    }

    /// The colours last put on the mark, held while the next cover loads.
    var current: CoverColours = .none

    @ObservationIgnored private var known: [Key: CoverColours] = [:]
    @ObservationIgnored private var order: [Key] = []
    @ObservationIgnored private let capacity = 64

    func colours(for key: Key) -> CoverColours? {
        known[key]
    }

    func remember(_ colours: CoverColours, for key: Key) {
        if known.updateValue(colours, forKey: key) == nil {
            order.append(key)
        }
        if order.count > capacity {
            known.removeValue(forKey: order.removeFirst())
        }
    }
}
