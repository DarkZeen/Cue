import Foundation
import Observation

/// The tray's contents.
///
/// In-memory for the session, by design (§3, §40): quitting Tray empties the
/// shelf and leaves every original file untouched. Nothing here reaches the
/// filesystem except to ask whether a URL still resolves.
///
/// The API is deliberately the one §40 asks for, so that a persistent backing
/// store could be slid underneath later without the UI noticing.
@Observable
final class TrayStore {
    private(set) var items: [TrayItem] = []

    /// Above this, new drops are refused rather than silently dropped on the
    /// floor. A shelf is not an inbox.
    static let capacity = 64

    var isEmpty: Bool { items.isEmpty }
    var count: Int { items.count }

    /// No more will fit. A drop has to be refused rather than accepted and
    /// quietly dropped on the floor.
    var isFull: Bool { items.count >= Self.capacity }

    // MARK: - Adding

    enum AddOutcome: Equatable {
        /// Items that actually joined the shelf, in the order they landed.
        case added([TrayItem.ID])
        /// Every URL was already here — the tray should acknowledge without
        /// growing (§52).
        case allDuplicates
        case rejectedAtCapacity
        case nothingUsable
    }

    /// Adds URLs to the end of the shelf — newest on the right (§53).
    ///
    /// Duplicate URLs collapse onto the existing entry instead of stacking up.
    @discardableResult
    func add(_ urls: [URL]) -> AddOutcome {
        let usable = urls.filter { $0.isFileURL }
        guard !usable.isEmpty else { return .nothingUsable }

        var existing = Set(items.map(\.identity))
        var landed: [TrayItem] = []

        for url in usable {
            let item = TrayItem(url: url)
            guard !existing.contains(item.identity) else { continue }
            guard items.count + landed.count < Self.capacity else {
                guard landed.isEmpty else { break }
                return .rejectedAtCapacity
            }
            existing.insert(item.identity)
            landed.append(item)
        }

        guard !landed.isEmpty else { return .allDuplicates }

        items.append(contentsOf: landed)
        return .added(landed.map(\.id))
    }

    @discardableResult
    func add(_ url: URL) -> AddOutcome {
        add([url])
    }

    // MARK: - Removing

    func remove(id: TrayItem.ID) {
        items.removeAll { $0.id == id }
    }

    func removeAll() {
        items.removeAll()
    }

    // MARK: - Reordering

    /// Moves an item to a new index, clamped into range.
    func move(id: TrayItem.ID, to destination: Int) {
        guard let current = items.firstIndex(where: { $0.id == id }) else { return }
        let target = min(max(destination, 0), items.count - 1)
        guard current != target else { return }
        let item = items.remove(at: current)
        items.insert(item, at: target)
    }

    // MARK: - Queries

    func contains(url: URL) -> Bool {
        let identity = url.standardizedFileURL.resolvingSymlinksInPath().path
        return items.contains { $0.identity == identity }
    }

    func item(id: TrayItem.ID) -> TrayItem? {
        items.first { $0.id == id }
    }

    // MARK: - Availability

    /// Re-checks whether each referenced file is still on disk.
    ///
    /// Called at moments the user is about to look at the tray, not on a timer.
    /// A file deleted behind our back turns into a visibly unavailable item
    /// rather than a crash or a lie (§52, §80).
    func refreshAvailability() {
        let manager = FileManager.default
        for index in items.indices {
            let exists = manager.fileExists(atPath: items[index].identity)
            let resolved: TrayItem.Availability = exists ? .present : .missing
            if items[index].availability != resolved {
                items[index].availability = resolved
            }
        }
    }
}
