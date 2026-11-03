import Testing

@testable import Cue

/// One click on the mark plays or pauses; two skip. The single has to wait to
/// find out which it is, and these pin how long and what happens at the edges.
@MainActor
struct ClickArbiterTests {
    private let window: Double = 0.3

    @Test func `a single click fires once the window has passed`() {
        var arbiter = ClickArbiter(window: window)

        #expect(arbiter.click(count: 1, at: 10) == nil)
        #expect(arbiter.tick(at: 10.1) == nil)
        #expect(arbiter.tick(at: 10.3) == .single)
        // And only once.
        #expect(arbiter.tick(at: 11) == nil)
        #expect(arbiter.deadline == nil)
    }

    @Test func `a second click inside the window cancels the single`() {
        var arbiter = ClickArbiter(window: window)

        #expect(arbiter.click(count: 1, at: 10) == nil)
        #expect(arbiter.click(count: 2, at: 10.15) == .double)
        // The play/pause that was waiting never happens.
        #expect(arbiter.tick(at: 11) == nil)
    }

    @Test func `a slow double click still skips after the single has fired`() {
        // Someone whose double click is slower than the window: the pause has
        // already happened, and undoing it would be stranger than skipping.
        var arbiter = ClickArbiter(window: window)

        #expect(arbiter.click(count: 1, at: 10) == nil)
        #expect(arbiter.tick(at: 10.31) == .single)
        #expect(arbiter.click(count: 2, at: 10.45) == .double)
        #expect(arbiter.tick(at: 11) == nil)
    }

    @Test func `a triple click skips once and does nothing more`() {
        var arbiter = ClickArbiter(window: window)

        #expect(arbiter.click(count: 1, at: 10) == nil)
        #expect(arbiter.click(count: 2, at: 10.1) == .double)
        #expect(arbiter.click(count: 3, at: 10.2) == nil)
        #expect(arbiter.tick(at: 11) == nil)
    }

    @Test func `two clicks AppKit did not pair are two singles`() {
        var arbiter = ClickArbiter(window: window)

        #expect(arbiter.click(count: 1, at: 10) == nil)
        // The first one goes now rather than being lost under the second.
        #expect(arbiter.click(count: 1, at: 10.1) == .single)
        #expect(arbiter.tick(at: 10.4) == .single)
    }

    @Test func `the cover has no single to wait for`() {
        var arbiter = ClickArbiter(window: window, handlesSingle: false)

        #expect(arbiter.click(count: 1, at: 10) == nil)
        #expect(arbiter.deadline == nil)
        #expect(arbiter.click(count: 2, at: 10.2) == .double)
        #expect(arbiter.tick(at: 11) == nil)
    }

    @Test func `the window never waits longer than three tenths of a second`() {
        #expect(ClickArbiter.systemWindow <= 0.3)
        #expect(ClickArbiter.systemWindow > 0)
    }
}
