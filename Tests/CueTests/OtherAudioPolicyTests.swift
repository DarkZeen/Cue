import Testing

@testable import Cue

@Suite("Making way for other audio")
struct OtherAudioPolicyTests {
    /// One reading of the world: whether another app is sounding, whether Cue
    /// says it is playing, and when.
    private typealias Tick = (other: Bool, cue: Bool, at: Double)

    /// Feeds readings in order and collects every action, with its time.
    private func run(
        _ ticks: [Tick],
        policy: inout OtherAudioPolicy
    ) -> [(OtherAudioPolicy.Action, Double)] {
        ticks.compactMap { tick in
            policy.update(otherAudio: tick.other, cuePlaying: tick.cue, at: tick.at)
                .map { ($0, tick.at) }
        }
    }

    private func run(_ ticks: [Tick]) -> [(OtherAudioPolicy.Action, Double)] {
        var policy = OtherAudioPolicy()
        return run(ticks, policy: &policy)
    }

    @Test("Pauses once another app has been sounding for a second")
    func pausesAfterSustainedAudio() {
        let actions = run([
            (false, true, 0),
            (true, true, 0.5),
            (true, true, 1.0),
            (true, true, 1.5),
        ])
        #expect(actions.map(\.0) == [.pause])
        #expect(actions.first?.1 == 1.5)
    }

    @Test("A notification ping is not media")
    func ignoresBlips() {
        let actions = run([
            (false, true, 0),
            (true, true, 0.5),
            (false, true, 1.0),
            (true, true, 1.5),
            (false, true, 2.0),
            (false, true, 5.0),
        ])
        #expect(actions.isEmpty)
    }

    @Test("Resumes once the other app has been quiet for two seconds")
    func resumesWhenQuiet() {
        let actions = run([
            (true, true, 0),
            (true, true, 1.0),   // pause
            (true, false, 1.5),  // Cue confirms it stopped
            (true, false, 3.0),
            (false, false, 3.5), // the video ends
            (false, false, 5.0),
            (false, false, 5.5), // two seconds quiet
            (false, true, 6.0),  // Cue confirms it started
        ])
        #expect(actions.map(\.0) == [.pause, .resume])
        #expect(actions.last?.1 == 5.5)
    }

    @Test("A pause the user made is never undone")
    func manualPauseNeverResumes() {
        let actions = run([
            (false, true, 0),
            (false, false, 1),   // paused by hand
            (true, false, 2),
            (true, false, 4),
            (false, false, 5),
            (false, false, 9),
        ])
        #expect(actions.isEmpty)
    }

    @Test("Pressing play over the other audio sticks until it stops")
    func manualPlayWhileHeldSticks() {
        var policy = OtherAudioPolicy()
        let held = run([
            (true, true, 0),
            (true, true, 1),     // pause
            (true, false, 1.5),
            (true, true, 3),     // the user presses play anyway
            (true, true, 5),
            (true, true, 10),
        ], policy: &policy)
        #expect(held.map(\.0) == [.pause])

        // Once the other app has gone quiet and starts again, that is new
        // media, and Cue makes way for it again.
        let later = run([
            (false, true, 11),
            (false, true, 13.5),
            (true, true, 14),
            (true, true, 15),
        ], policy: &policy)
        #expect(later.map(\.0) == [.pause])
    }

    @Test("Starting Cue over something already playing does not pause it")
    func startingOverAudioDoesNotPause() {
        let actions = run([
            (true, false, 0),
            (true, false, 1),
            (true, true, 2),     // the user picks something in Cue
            (true, true, 4),
            (true, true, 8),
        ])
        #expect(actions.isEmpty)
    }

    @Test("The page reporting late is not mistaken for the user pressing play")
    func reportLagAfterPause() {
        let actions = run([
            (true, true, 0),
            (true, true, 1),     // pause
            (true, true, 1.5),   // still says playing: the report is a second behind
            (true, false, 2),
            (false, false, 3),
            (false, false, 5),   // resume
            (false, false, 5.5), // still says paused, for the same reason
            (false, true, 6),
        ])
        #expect(actions.map(\.0) == [.pause, .resume])
    }

    @Test("A pause that never takes is asked for once, not every half second")
    func pauseThatFailsIsNotRepeated() {
        let actions = run([
            (true, true, 0),
            (true, true, 1),     // pause
            (true, true, 2),
            (true, true, 4),
            (true, true, 6),
            (true, true, 8),
        ])
        #expect(actions.map(\.0) == [.pause])
    }

    @Test("Turning the setting off gives back what it took")
    func resetResumesOnlyWhatItPaused() {
        var holding = OtherAudioPolicy()
        _ = run([(true, true, 0), (true, true, 1), (true, false, 1.5)], policy: &holding)
        #expect(holding.reset() == .resume)

        var idle = OtherAudioPolicy()
        _ = run([(false, true, 0), (false, false, 1)], policy: &idle)
        #expect(idle.reset() == nil)
    }
}
