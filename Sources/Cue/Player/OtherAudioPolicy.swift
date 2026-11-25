import Foundation

/// When to pause Cue for another app's sound, and when to give the music back.
///
/// Kept apart from anything that reads Core Audio or talks to the page, so the
/// rules can be tested by feeding it readings — and the rules are the part
/// worth testing, because every one of them exists to stop a specific wrong
/// thing happening to someone's music.
///
/// The one fact the whole thing turns on: Cue only ever resumes a pause it made
/// itself. Anything else — the plaque, a media key, the player window — is the
/// user, and the user's pause is left alone.
struct OtherAudioPolicy {
    enum Action: Equatable {
        case pause
        case resume
    }

    /// How long another app has to keep sounding before it counts as media.
    /// Long enough that a notification ping or the volume click does not stop
    /// the music; short enough that a video does not play over it for long.
    var pauseAfter: TimeInterval = 1

    /// How long everything else has to be quiet before the music comes back.
    /// A browser holds its audio open for a moment after its video is paused,
    /// and a video buffering for half a second is not a video that ended.
    var resumeAfter: TimeInterval = 2

    /// How long to wait for the page to confirm a pause or a resume before
    /// deciding it is not going to. The page reports once a second, so this
    /// is several reports.
    var settleTimeout: TimeInterval = 4

    private enum Phase: Equatable {
        /// Nothing paused by Cue.
        case idle
        /// Pause asked for; waiting for the page to say it stopped.
        case pausing(since: TimeInterval)
        /// Paused by Cue, waiting for the other app to finish.
        case holding
        /// Resume asked for; waiting for the page to say it started.
        case resuming(since: TimeInterval)
    }

    private var phase: Phase = .idle
    private var otherSince: TimeInterval?
    private var quietSince: TimeInterval?
    /// `nil` until the first reading, which is a starting point rather than a
    /// change: Cue already playing when the setting is turned on was playing
    /// alongside whatever else was sounding then, so those apps are tolerated.
    private var wasCuePlaying: Bool?

    /// The apps Cue was chosen over — sounding when the user started Cue, or
    /// when they pressed play while Cue was holding — which therefore do not
    /// count. Each is forgotten once it has been quiet for `resumeAfter`, so
    /// the *next* video from the same browser is still made way for.
    ///
    /// Per app rather than one flag, because some apps never go quiet. Haptyk
    /// holds an output stream open whether or not it is making a sound, and
    /// Core Audio reports it as playing on every reading. As a single flag,
    /// choosing Cue over it was an override nothing could ever clear, and Cue
    /// stopped making way for anything at all.
    private var tolerated: Set<String> = []

    /// When each app was last heard, for forgetting the tolerated ones.
    private var lastHeard: [String: TimeInterval] = [:]

    /// The sounding apps that count, as of the last reading. For the log: who
    /// Cue made way for, without the apps that were never the reason.
    private(set) var intruding: Set<String> = []

    /// Whether Cue's music is currently stopped, or stopping, on this policy's
    /// account — which is to say whether there is anything to give back.
    var isEngaged: Bool { phase != .idle }

    /// Takes one reading — which apps other than Cue are sounding — and says
    /// what, if anything, to do about it.
    mutating func update(sounding: Set<String>, cuePlaying: Bool, at now: TimeInterval) -> Action? {
        for app in sounding { lastHeard[app] = now }
        tolerated = tolerated.filter { app in
            lastHeard[app].map { now - $0 < resumeAfter } ?? false
        }

        // Cue starting while something else is already sounding is the user
        // choosing Cue over it. Pausing it a second later would be arguing.
        // The first reading counts as a start for the same reason.
        if phase == .idle, cuePlaying, wasCuePlaying != true { tolerated.formUnion(sounding) }

        intruding = sounding.subtracting(tolerated)
        let otherAudio = !intruding.isEmpty

        if otherAudio {
            quietSince = nil
            if otherSince == nil { otherSince = now }
        } else {
            otherSince = nil
            if quietSince == nil { quietSince = now }
        }

        let otherIsSustained = otherSince.map { now - $0 >= pauseAfter } ?? false
        let otherIsQuiet = quietSince.map { now - $0 >= resumeAfter } ?? false

        defer { wasCuePlaying = cuePlaying }

        switch phase {
        case .idle:
            guard cuePlaying, otherIsSustained else { return nil }
            phase = .pausing(since: now)
            return .pause

        case .pausing(let since):
            // Still playing is not the user pressing play: the page reports a
            // second behind, so the first readings after a pause say what was
            // true before it.
            if !cuePlaying {
                phase = .holding
            } else if now - since >= settleTimeout {
                // The pause did not take. Asking again every half second would
                // be a fight with whatever stopped it; give up until the other
                // app goes quiet and something new starts.
                phase = .idle
                tolerated.formUnion(sounding)
            }
            return nil

        case .holding:
            if cuePlaying {
                // Started while Cue was holding it: the user wants the music,
                // other app or not.
                phase = .idle
                tolerated.formUnion(sounding)
                return nil
            }
            guard otherIsQuiet else { return nil }
            phase = .resuming(since: now)
            return .resume

        case .resuming(let since):
            // Still paused is the same report lag as above, and not the user
            // pausing.
            if cuePlaying || now - since >= settleTimeout { phase = .idle }
            return nil
        }
    }

    /// Forgets everything, and says whether Cue's music needs giving back.
    ///
    /// For when the setting is turned off: music Cue stopped should not stay
    /// stopped because the thing that would have restarted it went away.
    mutating func reset() -> Action? {
        let tookTheMusic = phase == .holding || {
            if case .pausing = phase { return true }
            return false
        }()
        self = OtherAudioPolicy(
            pauseAfter: pauseAfter,
            resumeAfter: resumeAfter,
            settleTimeout: settleTimeout
        )
        return tookTheMusic ? .resume : nil
    }
}
