import SwiftUI
import Testing

@testable import Tray

/// The tray's motion (§13, §45, §46, §50).
@MainActor
struct TrayMotionTests {
    // MARK: - Container scale

    private func presenter() -> TrayPresenter {
        let tray = TrayPresenter()
        tray.collapseDelay = { 1 }
        return tray
    }

    @Test func `a resting tray is not scaled`() {
        #expect(presenter().containerScale == TrayScale.resting)
    }

    @Test func `the shelf leans toward an approaching drag`() {
        // §13's anticipation step. It had a value and no call site until now:
        // the tray gave no feedback at all until a drag was already on target.
        let tray = presenter()
        tray.dragApproached()

        #expect(tray.containerScale == TrayScale.dragApproaching)
        #expect(tray.containerScale > TrayScale.resting)
    }

    @Test func `a drag over the target lights it further`() {
        let tray = presenter()
        tray.dragEntered()

        #expect(tray.containerScale == TrayScale.dropTargetActive)
        // Anticipation has to be the smaller of the two, or arriving on target
        // would read as a step backwards.
        #expect(tray.containerScale > TrayScale.dragApproaching)
    }

    @Test func `the shelf gives as something lands`() {
        let tray = presenter()
        tray.dragEntered()

        tray.dropCompleted()

        #expect(tray.isAbsorbingDrop)
        #expect(tray.containerScale == TrayScale.dropImpact)
        #expect(tray.containerScale < TrayScale.resting)
    }

    @Test func `closing the tray cancels a drop it was still absorbing`() {
        let tray = presenter()
        tray.dropCompleted()

        tray.collapseNow()

        #expect(!tray.isAbsorbingDrop)
        #expect(tray.containerScale == TrayScale.resting)
    }

    // MARK: - Amplitudes

    @Test func `every amplitude stays small`() {
        // §46: "keep amplitude extremely small". Anything past a few percent
        // reads as a pop rather than as feedback.
        let deviations = [
            TrayScale.dragApproaching,
            TrayScale.dropTargetActive,
            TrayScale.itemHover,
            TrayScale.itemLifted,
            TrayScale.dropImpact,
        ].map { abs($0 - TrayScale.resting) }

        #expect(deviations.allSatisfy { $0 <= 0.05 })
    }

    @Test func `closing is quicker than opening`() {
        // An exit is the part the user has already stopped caring about. It
        // used to be the slowest motion in the app, sitting on the most-seen
        // element, with nothing before it to absorb the wait.
        #expect(TrayAnimation.collapseResponse < TrayAnimation.expandResponse)
    }

    @Test func `nothing overshoots except the two things that should`() {
        // Under 1.0 means the spring overshoots. Only an item arriving and a
        // drop landing carry momentum worth showing (§45).
        #expect(TrayAnimation.expandDamping > 0.8)
        #expect(TrayAnimation.collapseDamping > 0.9)
        #expect(TrayAnimation.hoverDamping > 0.8)
        #expect(TrayAnimation.itemEntranceDamping < 0.8)
        #expect(TrayAnimation.dropImpactDamping < 0.8)
    }

    // MARK: - Reduced motion (§50)

    @Test func `reduced motion replaces every spring with the same short fade`() {
        let reduced = TrayMotion(reduceMotion: true)

        // Same animation everywhere is the tell that each one took the
        // substitute rather than its spring.
        #expect(reduced.expand == reduced.collapse)
        #expect(reduced.expand == reduced.hover)
        #expect(reduced.expand == reduced.itemEntrance)
        #expect(reduced.expand == reduced.dropImpact)
    }

    @Test func `ordinary motion keeps its springs distinct`() {
        let standard = TrayMotion.standard

        #expect(standard.expand != standard.collapse)
        #expect(standard.hover != standard.itemEntrance)
    }

    @Test func `reduced motion is a gentler animation, not none`() {
        // Removing all feedback loses information; §50 asks for a
        // non-vestibular equivalent, not for nothing.
        #expect(TrayMotion(reduceMotion: true).expand != TrayMotion.standard.expand)
    }
}
