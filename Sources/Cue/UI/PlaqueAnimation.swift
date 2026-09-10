import Foundation

/// Which mark moves while something is playing.
enum PlaqueAnimation: String, Codable, CaseIterable, Sendable {
    /// Cue's wave, each shape moving with the music. The default.
    case wave
    /// A record turning under a tonearm.
    case disc
    /// Level bars, the way a meter has always looked.
    case bars
    /// Blobs going round a ring, merging as they pass.
    case orbit

    var title: String {
        switch self {
        case .wave: "Wave"
        case .disc: "Record"
        case .bars: "Bars"
        case .orbit: "Orbit"
        }
    }

    var summary: String {
        switch self {
        case .wave: "Cue's own mark, each shape moving with the music."
        case .disc: "A record turning under its arm."
        case .bars: "Level bars, the way a meter has always looked."
        case .orbit: "Blobs going round, running together as they pass."
        }
    }

    /// How wide the mark is. Height is fixed; only the bars and the record
    /// need more room than a square — the meter because it is a row of
    /// seventeen, the record because its arm reaches past the edge.
    var markWidth: CGFloat {
        switch self {
        case .wave, .orbit: 26
        case .disc: 30
        case .bars: 38
        }
    }
}
