import Foundation

/// What the mark in the corner does while music is playing.
enum PlaqueAnimation: String, Codable, CaseIterable, Sendable {
    /// Cue's wave, each shape moving with the music. The default.
    case wave
    /// A record turning, with notes drifting off it.
    case disc
    /// Level bars, the way a meter has always looked.
    case bars

    var title: String {
        switch self {
        case .wave: "Wave"
        case .disc: "Record"
        case .bars: "Bars"
        }
    }

    var summary: String {
        switch self {
        case .wave: "Cue's own mark, each shape moving with the music."
        case .disc: "A record turning, with notes drifting off it."
        case .bars: "Level bars, the way a meter has always looked."
        }
    }
}
