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
    /// A few thick rounded bars, the way the iPhone's Dynamic Island shows
    /// music.
    case island

    var title: String {
        switch self {
        case .wave: "Wave"
        case .disc: "Record"
        case .bars: "Bars"
        case .orbit: "Orbit"
        case .island: "Island"
        }
    }

    var summary: String {
        switch self {
        case .wave: "Cue's own mark, each shape moving with the music."
        case .disc: "A record turning under its arm."
        case .bars: "Level bars, the way a meter has always looked."
        case .orbit: "Blobs going round, running together as they pass."
        case .island: "Five thick bars, the way an iPhone shows music."
        }
    }

    /// Whether "Reacts to" changes this mark. The Wave and Island are built
    /// to answer to it; the others have their own idea of the music.
    var reacts: Bool { self == .wave || self == .island }

    /// How wide the mark is. Height is fixed; only the bars and the record
    /// need more room than a square — the meter because it is a row of
    /// seventeen, the record because its arm reaches past the edge.
    var markWidth: CGFloat {
        switch self {
        case .wave, .orbit, .island: 26
        case .disc: 30
        case .bars: 38
        }
    }
}

/// What the moving mark answers to.
enum MarkReaction: String, Codable, CaseIterable, Sendable {
    /// Each part follows its own slice of the spectrum: busy, detailed.
    case frequencies
    /// The whole mark jumps on each kick and settles between them.
    case beat
    /// How loud it is, slowly: a calm swell rather than a meter.
    case smooth

    var title: String {
        switch self {
        case .frequencies: "Frequencies"
        case .beat: "Beat"
        case .smooth: "Smooth"
        }
    }

    var summary: String {
        switch self {
        case .frequencies: "Each line follows its own part of the sound — bass in the middle, highs at the edges."
        case .beat: "The lines jump together on every kick and fall back between them."
        case .smooth: "A slow swell with the volume. Calm enough to leave on all day."
        }
    }
}

