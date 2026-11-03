import Testing

@testable import Cue

/// The pill's return after a Space switch: under the notch while hidden,
/// back out once visible.
@MainActor
struct SpaceReturnTests {
    @Test func `hidden drops it under the notch, visible brings it back`() async {
        let presenter = TrayPresenter()
        #expect(!presenter.isReturningFromSpace)

        presenter.windowHidden()
        #expect(presenter.isReturningFromSpace)

        presenter.windowShown(reduceMotion: true)
        // The grow-back is scheduled; give it room to run, polling rather
        // than guessing how busy the main actor is.
        for _ in 0..<40 where presenter.isReturningFromSpace {
            try? await Task.sleep(for: .milliseconds(25))
        }
        #expect(!presenter.isReturningFromSpace)
    }

    @Test func `shown without having been hidden does nothing`() async {
        let presenter = TrayPresenter()
        presenter.windowShown(reduceMotion: true)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(!presenter.isReturningFromSpace)
    }

    @Test func `hidden again before it grows keeps it under`() async {
        let presenter = TrayPresenter()
        presenter.windowHidden()
        presenter.windowShown(reduceMotion: true)
        presenter.windowHidden()
        try? await Task.sleep(for: .milliseconds(150))
        #expect(presenter.isReturningFromSpace)
    }
}
