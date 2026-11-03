import Foundation
import Testing

@testable import Cue

/// The beat mode's kick detector: a rise in the bass, not a lot of it.
@MainActor
struct BeatFollowerTests {
    private let start = Date(timeIntervalSinceReferenceDate: 10_000)

    private func bands(bass: Double) -> [Double] {
        [bass, bass] + Array(repeating: 0.3, count: 7)
    }

    /// Feeds `frames` frames of a sixtieth of a second each, returning the
    /// envelope after the last.
    private func feed(
        _ follower: BeatFollower,
        bass: Double,
        frames: Int,
        from offset: inout Double
    ) -> Double {
        var value = 0.0
        for _ in 0..<frames {
            offset += 1.0 / 60
            value = follower.update(level: 0.5, bands: bands(bass: bass), at: start.addingTimeInterval(offset))
        }
        return value
    }

    @Test func `a kick after quiet bass fires`() {
        let follower = BeatFollower()
        var t = 0.0
        _ = feed(follower, bass: 0.2, frames: 60, from: &t)

        #expect(feed(follower, bass: 0.8, frames: 1, from: &t) > 0.5)
    }

    @Test func `a bass line that stays loud stops counting as a kick`() {
        let follower = BeatFollower()
        var t = 0.0
        _ = feed(follower, bass: 0.2, frames: 60, from: &t)
        _ = feed(follower, bass: 0.8, frames: 1, from: &t)

        // Two seconds of the same loud bass: the average catches up.
        #expect(feed(follower, bass: 0.8, frames: 120, from: &t) < 0.05)
    }

    @Test func `the kick dies away`() {
        let follower = BeatFollower()
        var t = 0.0
        _ = feed(follower, bass: 0.2, frames: 60, from: &t)
        let hit = feed(follower, bass: 0.8, frames: 1, from: &t)

        // Back to quiet: a fifth of a second later, little left.
        let later = feed(follower, bass: 0.2, frames: 12, from: &t)
        #expect(later < hit * 0.4)
    }

    @Test func `with nothing listening it passes on the invented beat`() {
        let follower = BeatFollower()
        let at = start.addingTimeInterval(1.234)

        #expect(follower.update(level: 0, bands: [], at: at)
            == ProceduralMotion.beat([], at: at.timeIntervalSinceReferenceDate))
    }

    @Test func `the reaction mode is remembered, frequencies by default`() {
        let defaults = UserDefaults(suiteName: "BeatFollowerTests-\(UUID().uuidString)")!
        #expect(SettingsStore(defaults: defaults).markReaction == .frequencies)

        SettingsStore(defaults: defaults).markReaction = .beat
        #expect(SettingsStore(defaults: defaults).markReaction == .beat)
    }
}
