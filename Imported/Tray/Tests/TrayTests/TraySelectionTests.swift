import AppKit
import Foundation
import Testing

@testable import Tray

/// Selection, and the keyboard commands that act on it.
@MainActor
struct TraySelectionTests {
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TraySelectionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func makeFile(_ name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data("contents".utf8).write(to: url)
        return url
    }

    private func stocked(_ names: [String]) throws -> TrayStore {
        let store = TrayStore()
        store.add(try names.map(makeFile))
        return store
    }

    // MARK: - Picking

    @Test func `clicking an item selects only that item`() throws {
        let store = try stocked(["a.txt", "b.txt"])
        let selection = TraySelection()

        selection.select(store.items[0].id)
        selection.select(store.items[1].id)

        #expect(selection.ids == [store.items[1].id])
    }

    @Test func `command clicking extends and retracts the selection`() throws {
        let store = try stocked(["a.txt", "b.txt", "c.txt"])
        let selection = TraySelection()

        selection.select(store.items[0].id)
        selection.toggle(store.items[2].id)
        #expect(selection.count == 2)

        selection.toggle(store.items[2].id)
        #expect(selection.ids == [store.items[0].id])
    }

    @Test func `selected items come back in shelf order, not set order`() throws {
        let store = try stocked(["a.txt", "b.txt", "c.txt"])
        let selection = TraySelection()
        // Picked back to front on purpose.
        selection.select(store.items[2].id)
        selection.toggle(store.items[0].id)

        #expect(selection.items(from: store.items).map(\.filename) == ["a.txt", "c.txt"])
    }

    // MARK: - Arrow keys

    @Test func `arrow keys walk the shelf`() throws {
        let store = try stocked(["a.txt", "b.txt", "c.txt"])
        let order = store.items.map(\.id)
        let selection = TraySelection()

        selection.step(by: 1, within: order)
        #expect(selection.ids == [order[0]])

        selection.step(by: 1, within: order)
        #expect(selection.ids == [order[1]])

        selection.step(by: -1, within: order)
        #expect(selection.ids == [order[0]])
    }

    @Test func `stepping stops at the ends instead of wrapping`() throws {
        let store = try stocked(["a.txt", "b.txt"])
        let order = store.items.map(\.id)
        let selection = TraySelection()

        selection.select(order[0])
        selection.step(by: -1, within: order)
        #expect(selection.ids == [order[0]])

        selection.select(order[1])
        selection.step(by: 1, within: order)
        #expect(selection.ids == [order[1]])
    }

    @Test func `stepping an empty shelf does nothing`() {
        let selection = TraySelection()
        selection.step(by: 1, within: [])
        #expect(selection.isEmpty)
    }

    // MARK: - Staying in step with the shelf

    @Test func `removing an item drops it from the selection`() throws {
        let store = try stocked(["a.txt", "b.txt", "c.txt"])
        let selection = TraySelection()
        selection.selectAll(store.items.map(\.id))

        let gone = store.items[1]
        store.remove(id: gone.id)
        selection.prune(to: store.items.map(\.id))

        #expect(selection.count == 2)
        #expect(!selection.contains(gone.id))
    }

    @Test func `pruning moves the anchor off a removed item`() throws {
        let store = try stocked(["a.txt", "b.txt"])
        let selection = TraySelection()
        selection.select(store.items[1].id)

        store.remove(id: store.items[1].id)
        selection.prune(to: store.items.map(\.id))

        #expect(selection.isEmpty)
        #expect(selection.anchor == nil)
    }

    // MARK: - Copy and paste (§38's rule, by another route)

    @Test func `copying writes file URLs a paste target can use`() throws {
        let store = try stocked(["report.pdf", "photo.jpg"])
        let pasteboard = NSPasteboard(name: .init("TrayTests-\(UUID().uuidString)"))

        #expect(TrayPasteboard.copy(store.items, to: pasteboard))
        #expect(TrayPasteboard.pasteableURLs(from: pasteboard).map(\.lastPathComponent)
            == ["report.pdf", "photo.jpg"])
    }

    @Test func `copying nothing writes nothing`() {
        let pasteboard = NSPasteboard(name: .init("TrayTests-\(UUID().uuidString)"))
        #expect(TrayPasteboard.copy([], to: pasteboard) == false)
    }

    @Test func `a missing file is left off the pasteboard`() throws {
        let store = try stocked(["here.txt", "gone.txt"])
        try FileManager.default.removeItem(at: store.items[1].url)
        store.refreshAvailability()

        let pasteboard = NSPasteboard(name: .init("TrayTests-\(UUID().uuidString)"))
        #expect(TrayPasteboard.copy(store.items, to: pasteboard))

        // A pasteboard entry pointing at a deleted file fails somewhere the
        // user cannot connect back to the copy they made.
        #expect(TrayPasteboard.pasteableURLs(from: pasteboard).map(\.lastPathComponent)
            == ["here.txt"])
    }

    @Test func `pasting reads back what a copy wrote`() throws {
        let source = try stocked(["one.txt", "two.txt"])
        let pasteboard = NSPasteboard(name: .init("TrayTests-\(UUID().uuidString)"))
        TrayPasteboard.copy(source.items, to: pasteboard)

        let destination = TrayStore()
        destination.add(TrayPasteboard.pasteableURLs(from: pasteboard))

        #expect(destination.items.map(\.filename) == ["one.txt", "two.txt"])
    }
}
