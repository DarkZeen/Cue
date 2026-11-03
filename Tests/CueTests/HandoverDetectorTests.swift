import CoreAudio
import Foundation
import Testing

@testable import Cue

/// AirPods coming back from a phone, replayed from a real handover.
///
/// Recorded on a MacBook Air with AirPods Pro: device 86 is their output.
/// Seconds are from the start of the recording. They were playing on the Mac,
/// moved to the iPhone (the re-announcements at 70–76, with the audio still
/// flowing), sat quiet from 83, and came back at 98.
@MainActor
struct HandoverDetectorTests {
    private let airPods: AudioObjectID = 86
    private let origin = ContinuousClock.now

    private enum Event {
        case running(Bool)
        /// The output re-announced; the detector is asked 0.6 s later.
        case reasserted
    }

    /// Plays the events and returns the seconds at which an arrival fired.
    private func replay(_ events: [(Double, Event)]) -> [Double] {
        var detector = HandoverDetector()
        var fired: [Double] = []
        var running = false
        detector.running(airPods, false, at: origin)

        var pending: [Double] = []
        for (second, event) in events {
            // Any question due before this event is asked first.
            while let due = pending.first, due <= second {
                pending.removeFirst()
                detector.running(airPods, running, at: origin + .milliseconds(Int(due * 1000)))
                if detector.arrived(airPods, at: origin + .milliseconds(Int(due * 1000))) {
                    fired.append(due)
                }
            }
            let at = origin + .milliseconds(Int(second * 1000))
            switch event {
            case .running(let isRunning):
                running = isRunning
                detector.running(airPods, isRunning, at: at)
            case .reasserted:
                pending.append(second + 0.6)
            }
        }
        for due in pending {
            detector.running(airPods, running, at: origin + .milliseconds(Int(due * 1000)))
            if detector.arrived(airPods, at: origin + .milliseconds(Int(due * 1000))) { fired.append(due) }
        }
        return fired
    }

    private let recorded: [(Double, Event)] = [
        (57, .running(true)),
        (70.00, .running(false)), (70.01, .reasserted), (70.02, .running(true)), (70.03, .running(false)),
        (72, .running(true)),
        (73.00, .running(false)), (73.01, .reasserted), (73.02, .running(true)),
        (76.00, .running(false)), (76.01, .reasserted), (76.02, .running(true)),
        (83, .running(false)),
        (98.00, .running(true)), (98.01, .running(false)), (98.02, .reasserted), (98.03, .running(true)),
    ]

    @Test func `the real handover arrives once, when they come back`() {
        let fired = replay(recorded)
        #expect(fired.count == 1)
        #expect(fired.first.map { $0 > 98 && $0 < 99 } == true)
    }

    @Test func `playing music after a pause is not an arrival`() {
        // Quiet for a minute, then music — no re-announcement.
        #expect(replay([(60, .running(true))]).isEmpty)
    }

    @Test func `leaving while the music still flows is not an arrival`() {
        let leaving: [(Double, Event)] = [
            (10, .running(true)),
            (30.00, .running(false)), (30.01, .reasserted), (30.02, .running(true)),
        ]
        #expect(replay(leaving).isEmpty)
    }
}
