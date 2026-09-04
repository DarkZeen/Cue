import Foundation
import Testing

@testable import Cue

@Suite("Pinned tiles")
struct SettingsStoreTests {
    /// A private defaults domain per test, so tests cannot see each other's
    /// pins and cannot leave anything behind in the real app's preferences.
    private func store() -> SettingsStore {
        let suite = "com.cue.app.tests.\(UUID().uuidString)"
        return SettingsStore(defaults: UserDefaults(suiteName: suite)!)
    }

    private func item(_ id: String) -> MusicItem {
        MusicItem(id: id, title: id, kind: .playlist, playlistID: id, source: .dataAPI)
    }

    @Test("The grid starts empty and the right size")
    func startsEmpty() {
        let settings = store()
        #expect(settings.pinnedTiles.count == SettingsStore.tileCount)
        #expect(settings.pinnedTiles.allSatisfy { $0 == nil })
    }

    @Test("Removing a tile leaves a hole rather than closing the gap")
    func unpinningKeepsPositions() {
        // The whole value of a speed dial is that the fifth thing stays fifth.
        let settings = store()
        settings.pin(item("a"), at: 0)
        settings.pin(item("b"), at: 1)
        settings.pin(item("c"), at: 2)

        settings.unpin(at: 1)

        #expect(settings.pinnedTiles[0]?.id == "a")
        #expect(settings.pinnedTiles[1] == nil)
        #expect(settings.pinnedTiles[2]?.id == "c")
    }

    @Test("Pinning something twice moves it rather than duplicating it")
    func pinningMovesRatherThanCopies() {
        let settings = store()
        settings.pin(item("a"), at: 0)
        settings.pin(item("a"), at: 4)

        #expect(settings.pinnedTiles[0] == nil)
        #expect(settings.pinnedTiles[4]?.id == "a")
        #expect(settings.pinnedTiles.compactMap { $0 }.count == 1)
    }

    @Test("An index outside the grid is ignored, not trapped")
    func outOfRangeIsIgnored() {
        let settings = store()
        settings.pin(item("a"), at: 99)
        settings.unpin(at: -1)
        #expect(settings.pinnedTiles.allSatisfy { $0 == nil })
    }

    @Test("The first free slot skips the ones in use")
    func firstFreeSlot() {
        let settings = store()
        settings.pin(item("a"), at: 0)
        settings.pin(item("b"), at: 1)
        #expect(settings.firstFreeSlot == 2)
    }

    @Test("A full grid has no free slot")
    func fullGrid() {
        let settings = store()
        for index in 0..<SettingsStore.tileCount {
            settings.pin(item("\(index)"), at: index)
        }
        #expect(settings.firstFreeSlot == nil)
    }

    @Test("Pins survive a relaunch")
    func pinsPersist() {
        let suite = "com.cue.app.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!

        let first = SettingsStore(defaults: defaults)
        first.pin(item("a"), at: 3)

        let second = SettingsStore(defaults: defaults)
        #expect(second.pinnedTiles[3]?.id == "a")
        #expect(second.pinnedTiles.count == SettingsStore.tileCount)
    }

    @Test("A stored grid of the wrong size does not break this one")
    func storedCountMismatch() {
        // A build with a different grid size wrote these. Reading them must
        // not produce an array the panel then indexes out of range while
        // drawing.
        let suite = "com.cue.app.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let oversized = [MusicItem?](repeating: item("x"), count: 20)
        defaults.set(try! JSONEncoder().encode(oversized), forKey: "pinnedTiles")

        let settings = SettingsStore(defaults: defaults)
        #expect(settings.pinnedTiles.count == SettingsStore.tileCount)
    }
}

@Suite("Panel state")
struct PresenterTests {
    @Test("Nothing is selected when the panel opens")
    func opensWithNothingSelected() {
        // Return on a freshly opened panel must not play whatever happens to
        // be in the first tile.
        let presenter = CuePresenter()
        presenter.setSelectableCount(9)
        presenter.select(4)
        presenter.dismissNow()
        presenter.present()

        #expect(presenter.selection == nil)
        #expect(presenter.state == .visible)
    }

    @Test("Arrowing down from nothing starts at the top")
    func firstMoveStartsAtTheTop() {
        let presenter = CuePresenter()
        presenter.setSelectableCount(9)
        presenter.moveSelection(by: 3)
        #expect(presenter.selection == 0)
    }

    @Test("Arrowing up from nothing starts at the bottom")
    func firstBackwardMoveStartsAtTheEnd() {
        let presenter = CuePresenter()
        presenter.setSelectableCount(9)
        presenter.moveSelection(by: -1)
        #expect(presenter.selection == 8)
    }

    @Test("Selection clamps rather than wrapping")
    func selectionClamps() {
        // Wrapping in a list this short is disorienting, and it makes "go to
        // the last one" impossible to do by feel.
        let presenter = CuePresenter()
        presenter.setSelectableCount(9)
        presenter.select(8)
        presenter.moveSelection(by: 3)
        #expect(presenter.selection == 8)

        presenter.select(0)
        presenter.moveSelection(by: -3)
        #expect(presenter.selection == 0)
    }

    @Test("A list that shrinks under the highlight keeps it in range")
    func shrinkingListClampsSelection() {
        // Typing another letter narrows the results while an arrow key is
        // still holding a position further down.
        let presenter = CuePresenter()
        presenter.setSelectableCount(20)
        presenter.select(15)
        presenter.setSelectableCount(3)
        #expect(presenter.selection == 2)
    }

    @Test("A list that empties clears the highlight")
    func emptyListClearsSelection() {
        let presenter = CuePresenter()
        presenter.setSelectableCount(5)
        presenter.select(2)
        presenter.setSelectableCount(0)
        #expect(presenter.selection == nil)
    }

    @Test("Changing mode drops a highlight that belonged to the old list")
    func modeChangeClearsSelection() {
        // Otherwise Return opens the fourth search result because the fourth
        // tile was highlighted a moment ago.
        let presenter = CuePresenter()
        presenter.setSelectableCount(9)
        presenter.select(3)
        presenter.setMode(.results)
        #expect(presenter.selection == nil)
    }

    @Test("Selecting out of range does nothing")
    func selectionIsBounded() {
        let presenter = CuePresenter()
        presenter.setSelectableCount(3)
        presenter.select(7)
        #expect(presenter.selection == nil)
    }

    @Test("A dismissed panel is no longer interactive")
    func dismissalStopsInteraction() {
        let presenter = CuePresenter()
        presenter.present()
        #expect(presenter.isInteractive)

        presenter.dismiss()
        // Still on screen, animating away, and no longer accepting anything.
        #expect(presenter.state == .dismissing)
        #expect(!presenter.isInteractive)
    }

    @Test("Dismissing something already hidden does nothing")
    func dismissingWhenHidden() {
        let presenter = CuePresenter()
        presenter.dismiss()
        #expect(presenter.state == .hidden)
    }
}
