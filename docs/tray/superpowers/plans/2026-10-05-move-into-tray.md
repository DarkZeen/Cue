# Move Files Into the Tray: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A file dropped on the tray moves into a storage folder and lives only there. Dragging it into a Finder folder moves it out and takes it off the shelf.

**Architecture:** `ShelfStorage` is a new value type that runs off the main actor. It owns the storage folder and is the only code that moves, copies or trashes files. `TrayStore` becomes an `@Observable` view of that folder: the folder is the truth, transfers run in the background with an "arriving" placeholder, a `FolderWatcher` reloads the shelf when the folder changes, and an in-session arrival order keeps drops in the order they landed. The drop side decides between move and copy the way Finder does (`DropTransfer`). The drag-out side offers `.move/.copy/.delete` and afterwards lets the folder decide what is still on the shelf.

**Tech Stack:** Swift 6.2 (language mode 6, default isolation `MainActor`), AppKit + SwiftUI, Swift Testing, SwiftPM, macOS 26.

**Spec:** `docs/superpowers/specs/2026-10-05-move-into-tray-design.md`

## Global Constraints

- Platform floor is `.macOS("26.0")`, Swift language mode 6, and `.defaultIsolation(MainActor.self)`. Every type is `MainActor` unless it is marked `nonisolated`.
- The app is **not sandboxed** (§39). Add no entitlements and require no permissions. Full Disk Access is optional and is never requested.
- No polling (§26). Use only event-driven mechanisms: `DispatchSource` and AppKit events.
- Default storage folder: `~/Library/Application Support/Tray/Shelf`. Never `/tmp`.
- Drop-in follows Finder. Same volume moves, a different volume copies, ⌥ forces copy, and ⌘ (`.generic`) forces move.
- Drag-out mask outside the app is `[.move, .copy, .delete]`. Inside the app it stays `[]`.
- Removing an item (× or "Move All to Trash") sends the file to the Trash.
- Capacity stays at 64 for drops.
- **Tests never touch real user folders or the real Trash.** Every store or storage used in tests comes from `Scratch` (Task 2), which uses a scratch shelf and a scratch "Trash" directory.
- Run tests with `./Scripts/test.sh` and never with plain `swift test`, which silently runs nothing on Command Line Tools-only machines. Build the app with `./Scripts/build.sh`.
- Code style: explanatory `///` doc comments that say *why*, British spelling ("behaviour", "colour"), and section references like `(§38)`, matching the surrounding files.
- **Commits:** none unless the user asks. `main` carries unrelated uncommitted work. The "Checkpoint" steps below run the suite in place of commits.

## Review Focus

These failure modes are implied by the spec but not exercised by any task's main-path tests. Each one has a test in the task that owns the code.

1. **Dropping a file that is already in the shelf folder**, for example from the "Show in Finder" window. Expected: no-op, reported as a duplicate, no "name 2" copy. Owned by Task 2, test `a file already on the shelf is a duplicate, not a second copy`.
2. **Name clashes for packages and folders.** Expected: `Tool 2.app` (extension kept) and `Assets 2` (no fake extension split). Owned by Task 1.
3. **Removing an item while its copy is still arriving.** Expected: the removal is skipped and the file lands normally, not lost half-copied. Owned by Task 2.
4. **The storage folder deleted while the app runs.** Expected: the shelf goes empty, `isFolderAvailable == false`, drops are refused, and nothing crashes. Owned by Task 2.
5. **A source file that cannot be read** (permission denied). Expected: the original stays, nothing partial lands, and a one-line notice appears. Owned by Task 1 (storage) and Task 2 (notice).

---

### Task 1: `ShelfStorage`, the folder and every file operation on it

**Files:**
- Create: `Sources/Tray/Files/ShelfStorage.swift`
- Test: `Tests/TrayTests/ShelfStorageTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces (all `nonisolated`, `Sendable`):
  - `ShelfStorage.Transfer` with cases `.move` and `.copy`.
  - `ShelfStorage.Failure`, a `LocalizedError` with cases `.folderUnavailable(path:)`, `.transferFailed(name:transfer:reason:)` and `.trashFailed(name:reason:)`.
  - `ShelfStorage.Move { from: URL; to: URL }` and `ShelfStorage.Relocation { storage: ShelfStorage; moves: [Move] }`.
  - `init(folder:trash:sameVolume:)`, `folder: URL`, `isAvailable: Bool`, `createIfMissing() throws`.
  - `contents() throws -> [URL]`, `holds(_:) -> Bool`, `isSameVolume(as:) -> Bool`.
  - `availableDestination(for:) -> URL`, `bringIn(_:transfer:) throws -> URL`, `discard(_:) throws`, `relocate(to:) throws -> Relocation`.
  - Static members: `defaultFolder: URL`, `shelfOrder(_:) -> [URL]`, `problem(withFolder:home:) -> String?`, `key(_:) -> String`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/TrayTests/ShelfStorageTests.swift`:

```swift
import Foundation
import Testing

@testable import Tray

/// The folder the shelf lives in (§3, §40).
///
/// Every test gets its own source folder, shelf folder and stand-in Trash
/// under the temporary directory. Nothing here touches a real user folder or
/// the real Trash.
@MainActor
struct ShelfStorageTests {
    private let source: URL
    private let shelf: URL
    private let trashBin: URL

    init() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShelfStorageTests-\(UUID().uuidString)", isDirectory: true)
        source = root.appendingPathComponent("Source", isDirectory: true)
        shelf = root.appendingPathComponent("Shelf", isDirectory: true)
        trashBin = root.appendingPathComponent("Trash", isDirectory: true)
        for directory in [source, shelf, trashBin] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func storage(sameVolume: Bool = true) -> ShelfStorage {
        let bin = trashBin
        return ShelfStorage(
            folder: shelf,
            trash: { url in
                try FileManager.default.moveItem(
                    at: url,
                    to: bin.appendingPathComponent(url.lastPathComponent)
                )
            },
            sameVolume: { _, _ in sameVolume }
        )
    }

    @discardableResult
    private func file(_ name: String, in directory: URL? = nil) throws -> URL {
        let url = (directory ?? source).appendingPathComponent(name)
        try Data("contents of \(name)".utf8).write(to: url)
        return url
    }

    private func folder(_ name: String, in directory: URL? = nil) throws -> URL {
        let url = (directory ?? source).appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func names(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { !$0.hasPrefix(".") }
            .sorted()
    }

    // MARK: - Bringing files in

    @Test func `moving in takes the file out of its folder`() throws {
        let photo = try file("photo.jpg")

        let landed = try storage().bringIn(photo, transfer: .move)

        #expect(!FileManager.default.fileExists(atPath: photo.path))
        #expect(FileManager.default.fileExists(atPath: landed.path))
        #expect(try names(in: shelf) == ["photo.jpg"])
    }

    @Test func `copying in leaves the original where it was`() throws {
        let photo = try file("photo.jpg")

        try storage().bringIn(photo, transfer: .copy)

        #expect(FileManager.default.fileExists(atPath: photo.path))
        #expect(try names(in: shelf) == ["photo.jpg"])
    }

    @Test func `a whole folder moves in with its contents`() throws {
        let assets = try folder("Assets")
        try file("logo.png", in: assets)

        let landed = try storage().bringIn(assets, transfer: .move)

        #expect(try names(in: landed) == ["logo.png"])
        #expect(!FileManager.default.fileExists(atPath: assets.path))
    }

    @Test func `a name already on the shelf is numbered the way Finder numbers it`() throws {
        try file("report.pdf", in: shelf)
        let storage = storage()

        let second = try storage.bringIn(try file("report.pdf"), transfer: .move)
        let third = try storage.bringIn(
            try file("report.pdf", in: try folder("Elsewhere")),
            transfer: .move
        )

        #expect(second.lastPathComponent == "report 2.pdf")
        #expect(third.lastPathComponent == "report 3.pdf")
    }

    @Test func `a clashing folder gets a number without a fake extension`() throws {
        _ = try folder("Assets.v1", in: shelf)

        let landed = try storage().bringIn(try folder("Assets.v1"), transfer: .move)

        #expect(landed.lastPathComponent == "Assets.v1 2")
    }

    @Test func `a clashing package keeps its extension`() throws {
        _ = try folder("Tool.app", in: shelf)

        let landed = try storage().bringIn(try folder("Tool.app"), transfer: .move)

        #expect(landed.lastPathComponent == "Tool 2.app")
    }

    @Test func `bringing in something already on the shelf does nothing`() throws {
        let resident = try file("notes.txt", in: shelf)

        let landed = try storage().bringIn(resident, transfer: .move)

        #expect(landed == resident)
        #expect(try names(in: shelf) == ["notes.txt"])
    }

    @Test func `a file that cannot be read stays put and leaves nothing behind`() throws {
        let locked = try file("locked.txt")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path)
        }

        #expect(throws: ShelfStorage.Failure.self) {
            try storage().bringIn(locked, transfer: .copy)
        }
        #expect(FileManager.default.fileExists(atPath: locked.path))
        #expect(try names(in: shelf).isEmpty)
    }

    @Test func `a file that is not there is reported, not invented`() throws {
        let ghost = source.appendingPathComponent("ghost.txt")

        #expect(throws: ShelfStorage.Failure.self) {
            try storage().bringIn(ghost, transfer: .move)
        }
        #expect(try names(in: shelf).isEmpty)
    }

    // MARK: - What is on the shelf

    @Test func `hidden files are not shelf items`() throws {
        try file(".DS_Store", in: shelf)
        try file("visible.txt", in: shelf)

        #expect(try storage().contents().map(\.lastPathComponent) == ["visible.txt"])
    }

    @Test func `shelf order is arrival first, then name`() {
        let early = Date(timeIntervalSince1970: 100)
        let late = Date(timeIntervalSince1970: 200)
        let order = ShelfStorage.shelfOrder([
            (url: URL(fileURLWithPath: "/s/late.txt"), arrived: late),
            (url: URL(fileURLWithPath: "/s/b.txt"), arrived: early),
            (url: URL(fileURLWithPath: "/s/a.txt"), arrived: early),
        ])

        #expect(order.map(\.lastPathComponent) == ["a.txt", "b.txt", "late.txt"])
    }

    @Test func `holds answers only for things directly in the folder`() throws {
        let storage = storage()

        #expect(storage.holds(try file("in.txt", in: shelf)))
        #expect(!storage.holds(try file("out.txt")))
        #expect(!storage.holds(try file("deep.txt", in: try folder("Nested", in: shelf))))
    }

    // MARK: - Leaving

    @Test func `discarding sends the file to the Trash`() throws {
        let doomed = try file("old.txt", in: shelf)

        try storage().discard(doomed)

        #expect(try names(in: shelf).isEmpty)
        #expect(try names(in: trashBin) == ["old.txt"])
    }

    @Test func `discard never trashes something that is not on the shelf`() throws {
        let bystander = try file("bystander.txt")

        try storage().discard(bystander)

        #expect(FileManager.default.fileExists(atPath: bystander.path))
        #expect(try names(in: trashBin).isEmpty)
    }

    // MARK: - Availability

    @Test func `a missing folder is unavailable and refuses everything`() throws {
        let gone = ShelfStorage(folder: source.appendingPathComponent("Nope", isDirectory: true))

        #expect(!gone.isAvailable)
        #expect(throws: ShelfStorage.Failure.self) { try gone.contents() }
        #expect(throws: ShelfStorage.Failure.self) {
            try gone.bringIn(try file("x.txt"), transfer: .move)
        }
    }

    // MARK: - Relocating

    @Test func `relocating moves every shelf item into the new folder`() throws {
        try file("a.txt", in: shelf)
        try file("b.txt", in: shelf)
        let next = try folder("NewShelf")
        try file("a.txt", in: next)

        let relocation = try storage().relocate(to: next)

        #expect(try names(in: shelf).isEmpty)
        #expect(try names(in: next) == ["a 2.txt", "a.txt", "b.txt"])
        #expect(relocation.storage.folder == next)
        #expect(relocation.moves.count == 2)
    }

    @Test func `relocating to a missing folder changes nothing`() throws {
        try file("a.txt", in: shelf)

        #expect(throws: ShelfStorage.Failure.self) {
            try storage().relocate(to: source.appendingPathComponent("Nope", isDirectory: true))
        }
        #expect(try names(in: shelf) == ["a.txt"])
    }

    // MARK: - Choosing a folder

    @Test func `the home folder and disk roots cannot be the shelf`() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser

        #expect(ShelfStorage.problem(withFolder: home, home: home) != nil)
        #expect(ShelfStorage.problem(withFolder: URL(fileURLWithPath: "/"), home: home) != nil)
        #expect(ShelfStorage.problem(withFolder: shelf, home: home) == nil)
    }

    @Test func `the default folder lives in Application Support`() {
        #expect(ShelfStorage.defaultFolder.path.hasSuffix("Library/Application Support/Tray/Shelf"))
    }

    @Test func `a folder is on its own volume`() {
        #expect(ShelfStorage.areOnSameVolume(shelf, source))
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `./Scripts/test.sh 2>&1 | grep -E "error:|✘|Test run" | head`
Expected: a compile error, `cannot find 'ShelfStorage' in scope`.

- [ ] **Step 3: Implement `ShelfStorage`**

Create `Sources/Tray/Files/ShelfStorage.swift`:

```swift
import Foundation

/// The folder the shelf lives in, and the only code that moves files for it
/// (§3, §38, §40).
///
/// A file dropped on the tray is moved — or, from another disk, copied — into
/// this folder, and lives there until it is dragged out or removed. The folder
/// is the shelf: whatever is in it is on the tray, so a crash or a quit loses
/// nothing.
///
/// `nonisolated` because moving a file can take minutes when it crosses
/// disks, and that work must not happen on the main actor. Everything here is
/// synchronous and throwing; `TrayStore` decides where it runs.
nonisolated struct ShelfStorage: Sendable {
    enum Transfer: Sendable, Equatable {
        case move
        case copy

        var verb: String { self == .move ? "move" : "copy" }
    }

    enum Failure: LocalizedError, Equatable {
        case folderUnavailable(path: String)
        case transferFailed(name: String, transfer: Transfer, reason: String)
        case trashFailed(name: String, reason: String)

        var errorDescription: String? {
            switch self {
            case .folderUnavailable(let path):
                "The shelf folder isn't available: \((path as NSString).abbreviatingWithTildeInPath)"
            case .transferFailed(let name, let transfer, let reason):
                "Couldn't \(transfer.verb) \(name): \(reason)"
            case .trashFailed(let name, let reason):
                "Couldn't move \(name) to the Trash: \(reason)"
            }
        }
    }

    struct Move: Sendable, Equatable {
        let from: URL
        let to: URL
    }

    /// Where the shelf went, and what moved to get there.
    struct Relocation: Sendable {
        let storage: ShelfStorage
        let moves: [Move]
    }

    let folder: URL

    /// How a file reaches the Trash. The real Trash in the app; a scratch
    /// folder in tests, so a test run never fills the user's.
    private let trash: @Sendable (URL) throws -> Void

    /// Whether two locations share a volume. Injected so tests can stand in
    /// for a second disk without having one.
    private let sameVolume: @Sendable (URL, URL) -> Bool

    init(
        folder: URL,
        trash: @escaping @Sendable (URL) throws -> Void = ShelfStorage.moveToTrash,
        sameVolume: @escaping @Sendable (URL, URL) -> Bool = ShelfStorage.areOnSameVolume
    ) {
        self.folder = folder
        self.trash = trash
        self.sameVolume = sameVolume
    }

    /// `~/Library/Application Support/Tray/Shelf`. Not `/tmp`: macOS empties
    /// that on restart, and these are the only copies of the user's files.
    static var defaultFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tray", isDirectory: true)
            .appendingPathComponent("Shelf", isDirectory: true)
    }

    var isAvailable: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// Only ever called for the default folder. A folder the user chose that
    /// has gone missing is reported, not quietly recreated somewhere they will
    /// never look.
    func createIfMissing() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    // MARK: - What is on the shelf

    /// Everything visible in the folder, in shelf order.
    func contents() throws -> [URL] {
        guard isAvailable else { throw Failure.folderUnavailable(path: folder.path) }
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.addedToDirectoryDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        )
        return Self.shelfOrder(urls.map { (url: $0, arrived: Self.arrival(of: $0)) })
    }

    /// Oldest arrival on the left. Arrival dates can tie — a multi-file drop
    /// lands within one tick — so the name breaks the tie, compared the way
    /// Finder compares names.
    static func shelfOrder(_ entries: [(url: URL, arrived: Date)]) -> [URL] {
        entries.sorted { a, b in
            if a.arrived != b.arrived { return a.arrived < b.arrived }
            return a.url.lastPathComponent
                .localizedStandardCompare(b.url.lastPathComponent) == .orderedAscending
        }
        .map(\.url)
    }

    private static func arrival(of url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey])
        return values?.addedToDirectoryDate ?? values?.creationDate ?? .distantPast
    }

    /// Directly inside the folder — not merely somewhere beneath it.
    func holds(_ url: URL) -> Bool {
        Self.key(url.deletingLastPathComponent()) == Self.key(folder)
    }

    func isSameVolume(as url: URL) -> Bool {
        sameVolume(url, folder)
    }

    // MARK: - Bringing files in

    /// The first free name for `source` in the folder: `report.pdf`, then
    /// `report 2.pdf`, `report 3.pdf` — Finder's numbering. A plain folder is
    /// not split at its last dot; a package keeps its extension.
    func availableDestination(for source: URL) -> URL {
        let name = source.lastPathComponent
        let values = try? source.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        let isPlainFolder = (values?.isDirectory ?? false) && !(values?.isPackage ?? false)
        let base = isPlainFolder ? name : (name as NSString).deletingPathExtension
        let ext = isPlainFolder ? "" : (name as NSString).pathExtension

        var candidate = folder.appendingPathComponent(name)
        var number = 2
        while Self.exists(candidate) {
            let numbered = ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)"
            candidate = folder.appendingPathComponent(numbered)
            number += 1
        }
        return candidate
    }

    /// Moves or copies one file or folder onto the shelf, and says where it
    /// landed. Something already on the shelf stays exactly where it is.
    func bringIn(_ source: URL, transfer: Transfer) throws -> URL {
        guard isAvailable else { throw Failure.folderUnavailable(path: folder.path) }
        if holds(source) { return source }

        let destination = availableDestination(for: source)
        do {
            switch transfer {
            case .move: try FileManager.default.moveItem(at: source, to: destination)
            case .copy: try FileManager.default.copyItem(at: source, to: destination)
            }
            return destination
        } catch {
            // Half a file is worse than none. While the original is still
            // where it was, whatever reached the shelf can only be a partial
            // copy, and it goes.
            if Self.exists(source) {
                try? FileManager.default.removeItem(at: destination)
            }
            throw Failure.transferFailed(
                name: source.lastPathComponent,
                transfer: transfer,
                reason: Self.reason(error)
            )
        }
    }

    // MARK: - Leaving

    /// Sends a shelf item to the Trash. Refuses anything that is not on the
    /// shelf: removing something from the tray must never be able to trash a
    /// file somewhere else.
    func discard(_ url: URL) throws {
        guard holds(url) else { return }
        do {
            try trash(url)
        } catch {
            throw Failure.trashFailed(name: url.lastPathComponent, reason: Self.reason(error))
        }
    }

    // MARK: - Moving the shelf

    /// Moves every shelf item into `newFolder`, renaming on a clash. On
    /// failure, whatever already moved goes back, so the shelf is never split
    /// between two folders.
    func relocate(to newFolder: URL) throws -> Relocation {
        let target = ShelfStorage(folder: newFolder, trash: trash, sameVolume: sameVolume)
        guard target.isAvailable else { throw Failure.folderUnavailable(path: newFolder.path) }
        guard Self.key(newFolder) != Self.key(folder) else {
            return Relocation(storage: target, moves: [])
        }

        var moves: [Move] = []
        do {
            for url in try contents() {
                moves.append(Move(from: url, to: try target.bringIn(url, transfer: .move)))
            }
        } catch {
            for move in moves.reversed() {
                try? FileManager.default.moveItem(at: move.to, to: move.from)
            }
            throw error
        }
        return Relocation(storage: target, moves: moves)
    }

    // MARK: - Choosing a folder

    /// Why a folder cannot be the shelf, or `nil` if it can. Everything in the
    /// folder appears on the tray, so a home folder or a whole disk would turn
    /// the shelf into a file browser.
    static func problem(
        withFolder candidate: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String? {
        let path = key(candidate)
        if path == key(home) {
            return "Your home folder can't be the shelf: everything in it would appear on the tray."
        }
        let isVolume = (try? candidate.resourceValues(forKeys: [.isVolumeKey]).isVolume) ?? false
        if path == "/" || isVolume {
            return "The top level of a disk can't be the shelf."
        }
        return nil
    }

    // MARK: - Helpers

    /// The form two locations are compared in: standardised, symlinks
    /// resolved, so `/var/…` and `/private/var/…` are one place.
    static func key(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Present on disk, including a symlink whose target is gone — a name is
    /// taken whether or not the thing it points at still exists.
    private static func exists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    private static func reason(_ error: any Error) -> String {
        let error = error as NSError
        return error.localizedFailureReason ?? error.localizedDescription
    }

    static func moveToTrash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    static func areOnSameVolume(_ a: URL, _ b: URL) -> Bool {
        let first = try? a.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        let second = try? b.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        guard let first, let second else { return false }
        return first.isEqual(second)
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `./Scripts/test.sh 2>&1 | grep -E "error:|✘|ShelfStorage|Test run" | head -40`
Expected: every `ShelfStorageTests` test passes and the final line reads `Test run with N tests … passed`.

- [ ] **Step 5: Checkpoint.** Run the full suite (`./Scripts/test.sh`) and confirm it is green. Don't commit (see Global Constraints).

---

### Task 2: `TrayStore` over the folder, with `TrayItem`, `FolderWatcher` and the test helpers

**Files:**
- Create: `Sources/Tray/Files/FolderWatcher.swift`
- Create: `Tests/TrayTests/TestSupport.swift`
- Modify: `Sources/Tray/Files/TrayItem.swift` (whole file)
- Modify: `Sources/Tray/Files/TrayStore.swift` (whole file)
- Modify: `Sources/Tray/App/AppState.swift`: the store's construction and the debug seed
- Modify: `Sources/Tray/Tray/TrayWindowController.swift`: `refreshAvailability()` call sites, `paste()` and `remove(_:)`
- Modify: `Sources/Tray/DragDrop/FileDropHandler.swift`: a minimal compile fix only. Task 3 rewrites it.
- Modify: `Sources/Tray/Tray/TrayItemView.swift`: replace the missing-file badge
- Test: replace `Tests/TrayTests/TrayStoreTests.swift` (whole file)
- Test: modify `Tests/TrayTests/TraySelectionTests.swift` and `Tests/TrayTests/TrayAppearanceTests.swift`

**Interfaces:**
- Consumes: everything `ShelfStorage` produces in Task 1.
- Produces:
  - `TrayItem.init(url:id:isArriving:)`, `TrayItem.isArriving`, `TrayItem.isAvailable` (equal to `!isArriving`), and `static func identity(of: URL) -> String`.
  - `TrayStore.init(storage: ShelfStorage)`.
  - `TrayStore` properties: `items`, `storage`, `isFolderAvailable` and `notice` (all `private(set)`), plus `isEmpty`, `count`, `isFull` and `capacity`.
  - `TrayStore` methods:
    - `add(_ urls: [URL], transfer: ShelfStorage.Transfer) -> AddOutcome`
    - `settle() async`
    - `reload()`
    - `remove(ids:)`, `remove(id:)`, `removeAll()`
    - `finishDragOut(of:operation:)`
    - `move(id:to:)`
    - `relocate(to:) async throws`
    - `report(_:)`
    - `contains(url:)`, `item(id:)`
  - `AddOutcome` is unchanged.
  - `FolderWatcher.init?(folder:onChange:)`.
  - Test helpers: `Scratch.directory(_:)`, `Scratch.file(_:in:)`, `Scratch.store()`, `Scratch.stocked(_:)`, `Scratch.eventually(within:_:)` and `TestDefaults.scratch(_:)`.

- [ ] **Step 1: Write the test helpers**

Create `Tests/TrayTests/TestSupport.swift`:

```swift
import Foundation
import Synchronization

@testable import Tray

/// Scratch shelves for tests.
///
/// Every store a test builds lives over a fresh folder under the temporary
/// directory, with a stand-in Trash beside it. A test that removes something
/// moves it into that folder, never into the user's real Trash.
@MainActor
enum Scratch {
    static func directory(_ label: String = "TrayTests") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    static func file(_ name: String, in directory: URL, contents: String = "contents") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    /// An empty shelf, the folder behind it, and its stand-in Trash.
    static func store() throws -> (store: TrayStore, shelf: URL, trash: URL) {
        let shelf = try directory("TrayShelf")
        let bin = try directory("TrayTrash")
        let storage = ShelfStorage(folder: shelf, trash: { url in
            try FileManager.default.moveItem(at: url, to: bin.appendingPathComponent(url.lastPathComponent))
        })
        return (TrayStore(storage: storage), shelf, bin)
    }

    /// A shelf holding files with these names, in this order — dropped the
    /// way a user would drop them, so the order is the drop order.
    static func stocked(_ names: [String]) async throws -> TrayStore {
        let (store, _, _) = try store()
        let source = try directory("TraySource")
        let urls = try names.map { try file($0, in: source) }
        store.add(urls, transfer: .move)
        await store.settle()
        return store
    }

    /// Waits for something that arrives through the run loop — a folder
    /// watcher event — without guessing at a fixed delay.
    static func eventually(
        within timeout: Duration = .seconds(2),
        _ condition: () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }
}

/// Settings domains for tests, removed when the test process exits.
///
/// `UserDefaults(suiteName:)` writes a real preferences domain, and a test
/// run used to leave hundreds of them behind.
nonisolated enum TestDefaults {
    private static let names = Mutex<[String]>([])

    static func scratch(_ prefix: String = "TrayTests") -> UserDefaults {
        let name = "\(prefix)-\(UUID().uuidString)"
        let isFirst = names.withLock { list in
            list.append(name)
            return list.count == 1
        }
        if isFirst { atexit { TestDefaults.removeAll() } }
        return UserDefaults(suiteName: name)!
    }

    static func removeAll() {
        for name in names.withLock({ $0 }) {
            UserDefaults.standard.removePersistentDomain(forName: name)
        }
    }
}
```

- [ ] **Step 2: Write the failing store tests**

Replace `Tests/TrayTests/TrayStoreTests.swift` entirely:

```swift
import AppKit
import Foundation
import Testing

@testable import Tray

/// The shelf over its folder (§3, §40, §70).
@MainActor
struct TrayStoreTests {
    private let source: URL

    init() throws {
        source = try Scratch.directory("TrayStoreSource")
    }

    private func file(_ name: String) throws -> URL {
        try Scratch.file(name, in: source)
    }

    private func names(_ store: TrayStore) -> [String] {
        store.items.map(\.url.lastPathComponent)
    }

    // MARK: - Adding

    @Test func `a dropped file moves onto the shelf`() async throws {
        let (store, shelf, _) = try Scratch.store()
        let photo = try file("photo.jpg")

        let outcome = store.add([photo], transfer: .move)
        await store.settle()

        #expect(outcome == .added(store.items.map(\.id)))
        #expect(!FileManager.default.fileExists(atPath: photo.path))
        #expect(names(store) == ["photo.jpg"])
        #expect(ShelfStorage(folder: shelf).holds(store.items[0].url))
    }

    @Test func `a copied file leaves the original behind`() async throws {
        let (store, _, _) = try Scratch.store()
        let photo = try file("photo.jpg")

        store.add([photo], transfer: .copy)
        await store.settle()

        #expect(FileManager.default.fileExists(atPath: photo.path))
        #expect(names(store) == ["photo.jpg"])
    }

    @Test func `an item is arriving until its transfer lands`() async throws {
        let (store, _, _) = try Scratch.store()

        store.add([try file("big.mov")], transfer: .copy)
        #expect(store.items.first?.isArriving == true)

        await store.settle()
        #expect(store.items.first?.isArriving == false)
    }

    @Test func `a folder is recognised as a folder`() async throws {
        let (store, _, _) = try Scratch.store()
        let assets = source.appendingPathComponent("Assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

        store.add([assets], transfer: .move)
        await store.settle()

        #expect(store.items.first?.kind == .folder)
    }

    @Test func `a multi file drop keeps the order it arrived in`() async throws {
        let (store, _, _) = try Scratch.store()

        store.add(try ["c.txt", "a.txt", "b.txt"].map(file), transfer: .move)
        await store.settle()

        #expect(names(store) == ["c.txt", "a.txt", "b.txt"])
    }

    @Test func `newest drops enter on the right`() async throws {
        let (store, _, _) = try Scratch.store()

        store.add([try file("second.txt")], transfer: .move)
        await store.settle()
        store.add([try file("first.txt")], transfer: .move)
        await store.settle()

        #expect(names(store) == ["second.txt", "first.txt"])
    }

    @Test func `a clashing name is numbered rather than overwritten`() async throws {
        let (store, shelf, _) = try Scratch.store()
        try Scratch.file("report.pdf", in: shelf, contents: "old")
        store.reload()

        store.add([try file("report.pdf")], transfer: .move)
        await store.settle()

        #expect(names(store) == ["report.pdf", "report 2.pdf"])
    }

    @Test func `a file already on the shelf is a duplicate, not a second copy`() async throws {
        let store = try await Scratch.stocked(["notes.txt"])

        #expect(store.add([store.items[0].url], transfer: .move) == .allDuplicates)
        await store.settle()
        #expect(names(store) == ["notes.txt"])
    }

    @Test func `the same file twice in one drop lands once`() async throws {
        let (store, _, _) = try Scratch.store()
        let twice = try file("twice.txt")

        store.add([twice, twice], transfer: .copy)
        await store.settle()

        #expect(names(store) == ["twice.txt"])
    }

    @Test func `a non file URL is refused`() throws {
        let (store, _, _) = try Scratch.store()
        #expect(store.add([URL(string: "https://example.com/x.pdf")!], transfer: .move) == .nothingUsable)
    }

    @Test func `an empty drop is refused`() throws {
        let (store, _, _) = try Scratch.store()
        #expect(store.add([], transfer: .move) == .nothingUsable)
    }

    // MARK: - Capacity

    private func fullStore(leaving space: Int = 0) throws -> TrayStore {
        let (store, shelf, _) = try Scratch.store()
        for index in 0..<(TrayStore.capacity - space) {
            try Scratch.file("file-\(index).txt", in: shelf)
        }
        store.reload()
        return store
    }

    @Test func `the shelf refuses to grow past its capacity`() throws {
        let store = try fullStore()

        #expect(store.isFull)
        #expect(store.add([try file("late.txt")], transfer: .move) == .rejectedAtCapacity)
    }

    @Test func `a partly fitting drop still lands what fits`() async throws {
        let store = try fullStore(leaving: 1)

        let outcome = store.add([try file("fits.txt"), try file("does-not.txt")], transfer: .move)
        await store.settle()

        guard case .added(let ids) = outcome else {
            Issue.record("expected .added, got \(outcome)")
            return
        }
        #expect(ids.count == 1)
        #expect(store.isFull)
    }

    // MARK: - Removing

    @Test func `removing sends the file to the Trash`() async throws {
        let store = try await Scratch.stocked(["a.txt", "b.txt"])
        let target = store.items[0]

        store.remove(id: target.id)

        #expect(names(store) == ["b.txt"])
        #expect(!FileManager.default.fileExists(atPath: target.url.path))
    }

    @Test func `removing everything empties the shelf into the Trash`() async throws {
        let (store, _, bin) = try Scratch.store()
        store.add(try ["a.txt", "b.txt"].map(file), transfer: .move)
        await store.settle()

        store.removeAll()

        #expect(store.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: bin.path).sorted() == ["a.txt", "b.txt"])
    }

    @Test func `an item still arriving is not removed out from under its copy`() async throws {
        let (store, _, _) = try Scratch.store()

        store.add([try file("busy.txt")], transfer: .copy)
        store.remove(ids: store.items.map(\.id))
        await store.settle()

        #expect(names(store) == ["busy.txt"])
    }

    // MARK: - The folder is the truth

    @Test func `the shelf survives a relaunch`() async throws {
        let store = try await Scratch.stocked(["one.txt", "two.txt"])

        let relaunched = TrayStore(storage: store.storage)

        #expect(relaunched.items.map(\.filename).sorted() == ["one.txt", "two.txt"])
    }

    @Test func `a file added to the folder in Finder appears on the shelf`() async throws {
        let (store, shelf, _) = try Scratch.store()

        try Scratch.file("from-finder.txt", in: shelf)

        #expect(await Scratch.eventually { names(store) == ["from-finder.txt"] })
    }

    @Test func `a file moved out in Finder leaves the shelf`() async throws {
        let store = try await Scratch.stocked(["leaving.txt"])

        try FileManager.default.moveItem(
            at: store.items[0].url,
            to: source.appendingPathComponent("leaving.txt")
        )

        #expect(await Scratch.eventually { store.isEmpty })
    }

    @Test func `a deleted shelf folder empties the shelf and refuses drops`() async throws {
        let (store, shelf, _) = try Scratch.store()
        try FileManager.default.removeItem(at: shelf)
        store.reload()

        #expect(!store.isFolderAvailable)
        #expect(store.isEmpty)
        #expect(store.add([try file("x.txt")], transfer: .move) == .nothingUsable)
    }

    // MARK: - Dragging out

    @Test func `a file copied out by an app stays on the shelf`() async throws {
        let store = try await Scratch.stocked(["kept.txt"])

        store.finishDragOut(of: store.items.map(\.id), operation: .copy)

        #expect(names(store) == ["kept.txt"])
    }

    @Test func `a file Finder moved out leaves the shelf`() async throws {
        let store = try await Scratch.stocked(["moved.txt"])
        let ids = store.items.map(\.id)
        try FileManager.default.moveItem(at: store.items[0].url, to: source.appendingPathComponent("moved.txt"))

        store.finishDragOut(of: ids, operation: .move)

        #expect(store.isEmpty)
    }

    @Test func `a file dropped on the Trash is trashed by the shelf`() async throws {
        let (store, _, bin) = try Scratch.store()
        store.add([try file("bin-me.txt")], transfer: .move)
        await store.settle()

        store.finishDragOut(of: store.items.map(\.id), operation: .delete)

        #expect(store.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: bin.path) == ["bin-me.txt"])
    }

    // MARK: - Failure

    @Test func `a transfer that fails is reported and leaves no placeholder`() async throws {
        let (store, _, _) = try Scratch.store()
        let ghost = source.appendingPathComponent("ghost.txt")

        store.add([ghost], transfer: .move)
        await store.settle()

        #expect(store.isEmpty)
        #expect(store.notice?.hasPrefix("Couldn't move ghost.txt") == true)
    }

    // MARK: - Order and identity

    @Test func `moving an item reorders the shelf and the order holds`() async throws {
        let store = try await Scratch.stocked(["a.txt", "b.txt", "c.txt"])

        store.move(id: store.items[0].id, to: 2)
        store.reload()

        #expect(names(store) == ["b.txt", "c.txt", "a.txt"])
    }

    @Test func `moving past the end clamps instead of crashing`() async throws {
        let store = try await Scratch.stocked(["a.txt", "b.txt"])

        store.move(id: store.items[0].id, to: 99)

        #expect(names(store) == ["b.txt", "a.txt"])
    }

    @Test func `ids survive a reload`() async throws {
        let store = try await Scratch.stocked(["a.txt"])
        let id = store.items[0].id

        store.reload()

        #expect(store.items[0].id == id)
    }

    // MARK: - Relocating

    @Test func `relocating carries the shelf, its order and its ids to the new folder`() async throws {
        let store = try await Scratch.stocked(["z.txt", "a.txt"])
        let ids = store.items.map(\.id)
        let old = store.storage.folder
        let next = try Scratch.directory("TrayNewShelf")

        try await store.relocate(to: next)

        #expect(store.storage.folder == next)
        #expect(names(store) == ["z.txt", "a.txt"])
        #expect(store.items.map(\.id) == ids)
        #expect(try FileManager.default.contentsOfDirectory(atPath: old.path).isEmpty)
    }

    // MARK: - Queries

    @Test func `contains answers for a URL that was never added`() async throws {
        let store = try await Scratch.stocked(["present.txt"])

        #expect(store.contains(url: store.items[0].url))
        #expect(!store.contains(url: source.appendingPathComponent("absent.txt")))
    }
}
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run: `./Scripts/test.sh 2>&1 | grep -E "error:" | head`
Expected: compile errors such as `extra argument 'storage' in call`, `no member 'settle'` and `no member 'isArriving'`.

- [ ] **Step 4: Implement `TrayItem`**

Replace `Sources/Tray/Files/TrayItem.swift` with:

```swift
import Foundation

/// One thing sitting on the shelf.
///
/// The tray owns the file: dropping one moves it (or, from another disk,
/// copies it) into the shelf folder, and `url` points there (§3, §38). The
/// one exception is an item still *arriving* — a transfer in flight — whose
/// `url` is still the source until the transfer lands.
///
/// Thumbnails are deliberately not stored here. The spec is explicit that
/// image generation is not the model's job (§41); `ThumbnailProvider` owns it
/// and is keyed by the item's identity.
struct TrayItem: Identifiable, Equatable, Sendable {
    enum Kind: Sendable {
        case file
        case folder
    }

    let id: UUID
    let url: URL

    /// The name as Finder would write it — localised, and with the extension
    /// hidden if that is what the user has asked for.
    let filename: String

    let kind: Kind

    /// Still on its way in. Shown dimmed, and not draggable, copyable or
    /// previewable until it lands — there is nothing finished to hand over.
    var isArriving: Bool

    /// The value two URLs are compared by: standardised, symlinks resolved,
    /// so `/tmp/x` and `/private/tmp/x` are one file (§52).
    let identity: String

    init(url: URL, id: UUID = UUID(), isArriving: Bool = false) {
        self.id = id
        self.url = url
        self.isArriving = isArriving
        self.identity = Self.identity(of: url)

        let displayName = FileManager.default.displayName(atPath: identity)
        self.filename = displayName.isEmpty ? url.lastPathComponent : displayName

        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        // A package (.app, .rtfd) is a directory on disk but a single object to
        // the user, so it reads as a file here.
        let isDirectory = (values?.isDirectory ?? false) && !(values?.isPackage ?? false)
        self.kind = isDirectory ? .folder : .file
    }

    static func identity(of url: URL) -> String {
        ShelfStorage.key(url)
    }

    /// Everything that hands the file to something else — dragging, copying,
    /// Quick Look — waits for this.
    var isAvailable: Bool { !isArriving }

    /// What VoiceOver reads for this item (§35).
    var accessibilityLabel: String {
        if isArriving { return "\(filename), arriving" }
        return kind == .folder ? "\(filename), folder" : filename
    }
}
```

- [ ] **Step 5: Implement `FolderWatcher`**

Create `Sources/Tray/Files/FolderWatcher.swift`:

```swift
import Foundation

/// Tells the shelf when its folder changes without the tray doing it (§26).
///
/// Finder finishing a move the tray started, a file added or deleted in the
/// folder by hand: the shelf *is* the folder, so it has to hear about these.
/// A kernel event source on the directory, not a poll. It costs nothing until
/// something in the folder actually changes.
final class FolderWatcher {
    private let source: any DispatchSourceFileSystemObject

    init?(folder: URL, onChange: @escaping @MainActor @Sendable () -> Void) {
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        source.setEventHandler {
            MainActor.assumeIsolated { onChange() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
    }

    isolated deinit {
        source.cancel()
    }
}
```

- [ ] **Step 6: Implement `TrayStore`**

Replace `Sources/Tray/Files/TrayStore.swift` with:

```swift
import AppKit
import Observation

/// The tray's contents: whatever is in the shelf folder (§3, §40).
///
/// The folder is the only source of truth. Dropping a file moves it (or, from
/// another disk, copies it) in; dragging it into a Finder folder moves it out;
/// removing it sends it to the Trash. Quitting or crashing loses nothing — the
/// next launch shows whatever the folder holds.
///
/// Every file operation goes through `ShelfStorage`, and transfers run off the
/// main actor. A file on its way in is shown as *arriving* until it lands.
@Observable
final class TrayStore {
    private(set) var items: [TrayItem] = []

    /// Where the shelf lives, and the only thing that moves files for it.
    private(set) var storage: ShelfStorage

    /// False when the folder cannot be reached — an unplugged drive, a folder
    /// deleted in Finder. The shelf shows empty and drops are refused.
    private(set) var isFolderAvailable = true

    /// One line about the last thing that went wrong, shown under the header
    /// for a few seconds.
    private(set) var notice: String?

    /// Above this, new drops are refused rather than silently dropped on the
    /// floor. A shelf is not an inbox.
    static let capacity = 64

    static let noticeDuration: Duration = .seconds(4)

    var isEmpty: Bool { items.isEmpty }
    var count: Int { items.count }
    var isFull: Bool { items.count >= Self.capacity }

    /// Ids survive a reload: the same file keeps the same id, so a selection
    /// is not lost every time the folder is re-read.
    @ObservationIgnored private var idsByPath: [String: TrayItem.ID] = [:]

    /// The order files reached the shelf this session. Arrival dates on disk
    /// can tie within a multi-file drop; this cannot.
    @ObservationIgnored private var arrivalOrder: [String] = []

    @ObservationIgnored private var arriving: [TrayItem] = []
    @ObservationIgnored private var transfers: [Task<Void, Never>] = []
    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    init(storage: ShelfStorage) {
        self.storage = storage
        reload()
        startWatching()
    }

    // MARK: - Adding

    enum AddOutcome: Equatable {
        /// Items that joined the shelf, in the order they landed.
        case added([TrayItem.ID])
        /// Everything was already here or already on its way (§52).
        case allDuplicates
        case rejectedAtCapacity
        case nothingUsable
    }

    /// Starts bringing `urls` onto the shelf and answers at once.
    ///
    /// The answer has to be synchronous — a drop tells its source straight
    /// away whether it worked — but a copy from another disk can take
    /// minutes. So each file appears immediately as *arriving*, and the
    /// transfer runs off the main actor.
    @discardableResult
    func add(_ urls: [URL], transfer: ShelfStorage.Transfer) -> AddOutcome {
        let usable = urls.filter(\.isFileURL)
        guard !usable.isEmpty, isFolderAvailable else { return .nothingUsable }

        var seen = Set(arriving.map(\.identity))
        var incoming: [TrayItem] = []
        for url in usable {
            let identity = TrayItem.identity(of: url)
            // Already on the shelf, or already on its way.
            guard !storage.holds(url), !seen.contains(identity) else { continue }
            guard items.count + incoming.count < Self.capacity else {
                guard incoming.isEmpty else { break }
                return .rejectedAtCapacity
            }
            seen.insert(identity)
            incoming.append(TrayItem(url: url, isArriving: true))
        }
        guard !incoming.isEmpty else { return .allDuplicates }

        arriving.append(contentsOf: incoming)
        items.append(contentsOf: incoming)

        let storage = self.storage
        transfers.append(Task { [weak self] in
            for item in incoming {
                let source = item.url
                let result = await Task.detached(priority: .userInitiated) {
                    Result { try storage.bringIn(source, transfer: transfer) }
                }.value
                self?.land(item, result)
            }
        })
        return .added(incoming.map(\.id))
    }

    private func land(_ item: TrayItem, _ result: Result<URL, any Error>) {
        arriving.removeAll { $0.id == item.id }
        switch result {
        case .success(let destination):
            let path = TrayItem.identity(of: destination)
            idsByPath[path] = item.id
            if !arrivalOrder.contains(path) { arrivalOrder.append(path) }
        case .failure(let error):
            report(error)
        }
        reload()
    }

    /// Waits until every transfer in flight has landed or failed.
    func settle() async {
        while !transfers.isEmpty {
            let pending = transfers
            transfers.removeAll()
            for task in pending { await task.value }
        }
    }

    // MARK: - Reading the folder

    /// Rebuilds the shelf from the folder. Cheap enough to call whenever
    /// something might have changed: one directory listing.
    func reload() {
        let urls: [URL]
        do {
            urls = try storage.contents()
            isFolderAvailable = true
        } catch {
            urls = []
            isFolderAvailable = false
        }

        let paths = urls.map(TrayItem.identity(of:))
        let live = Set(paths)
        arrivalOrder.removeAll { !live.contains($0) }
        // Anything new — from before this session, or put there in Finder —
        // joins on the right, in the folder's own order.
        for path in paths where !arrivalOrder.contains(path) {
            arrivalOrder.append(path)
        }
        idsByPath = idsByPath.filter { live.contains($0.key) }

        let rank = Dictionary(uniqueKeysWithValues: arrivalOrder.enumerated().map { ($1, $0) })
        let present = zip(urls, paths)
            .sorted { rank[$0.1, default: .max] < rank[$1.1, default: .max] }
            .map { url, path -> TrayItem in
                let id = idsByPath[path] ?? UUID()
                idsByPath[path] = id
                return TrayItem(url: url, id: id)
            }

        let next = present + arriving
        if next != items { items = next }
    }

    private func startWatching() {
        watcher = FolderWatcher(folder: storage.folder) { [weak self] in
            self?.reload()
        }
    }

    // MARK: - Removing

    /// Sends items to the Trash and takes them off the shelf. An item still
    /// arriving is left alone: there is nothing finished to trash yet.
    func remove(ids: [TrayItem.ID]) {
        let doomed = items.filter { ids.contains($0.id) && !$0.isArriving }
        guard !doomed.isEmpty else { return }
        for item in doomed {
            do {
                try storage.discard(item.url)
            } catch {
                report(error)
            }
        }
        reload()
    }

    func remove(id: TrayItem.ID) {
        remove(ids: [id])
    }

    func removeAll() {
        remove(ids: items.map(\.id))
    }

    /// A drag out of the shelf has ended.
    ///
    /// Whether a file left is decided by the folder, not by the drag's
    /// verdict: Finder moving it takes it out of the folder, an app copying
    /// it leaves it there. Dropped on the Trash, the *source* is the one that
    /// has to delete — so the shelf does.
    func finishDragOut(of ids: [TrayItem.ID], operation: NSDragOperation) {
        if operation.contains(.delete) {
            remove(ids: ids)
        } else {
            reload()
        }
    }

    // MARK: - Reordering

    /// Moves an item to a new index, clamped into range. The order holds
    /// until the app quits; after that the folder's arrival dates decide.
    func move(id: TrayItem.ID, to destination: Int) {
        guard let current = items.firstIndex(where: { $0.id == id }) else { return }
        let target = min(max(destination, 0), items.count - 1)
        guard current != target else { return }
        let item = items.remove(at: current)
        items.insert(item, at: target)
        arrivalOrder = items.filter { !$0.isArriving }.map(\.identity)
    }

    // MARK: - Moving the shelf

    /// Moves every shelf item into `folder` and makes it the shelf, keeping
    /// ids and order. On failure nothing changes — `ShelfStorage` puts back
    /// whatever had already moved.
    func relocate(to folder: URL) async throws {
        await settle()
        let current = storage
        let identityByPath = Dictionary(
            items.map { ($0.url.path, $0.identity) },
            uniquingKeysWith: { first, _ in first }
        )

        let relocation = try await Task.detached(priority: .userInitiated) {
            try current.relocate(to: folder)
        }.value

        for move in relocation.moves {
            let old = identityByPath[move.from.path] ?? TrayItem.identity(of: move.from)
            let new = TrayItem.identity(of: move.to)
            if let id = idsByPath.removeValue(forKey: old) { idsByPath[new] = id }
            if let index = arrivalOrder.firstIndex(of: old) { arrivalOrder[index] = new }
        }
        storage = relocation.storage
        startWatching()
        reload()
    }

    // MARK: - Telling the user

    func report(_ error: any Error) {
        notice = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: Self.noticeDuration)
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    // MARK: - Queries

    func contains(url: URL) -> Bool {
        let identity = TrayItem.identity(of: url)
        return items.contains { $0.identity == identity }
    }

    func item(id: TrayItem.ID) -> TrayItem? {
        items.first { $0.id == id }
    }
}
```

- [ ] **Step 7: Fix the callers**

In `Sources/Tray/App/AppState.swift`, replace `let store = TrayStore()` and give the class an initialiser. Task 5 changes this to read the folder from settings.

```swift
    let store: TrayStore
    let thumbnails = ThumbnailProvider()
    let settings = SettingsStore()
```

```swift
    init() {
        let storage = ShelfStorage(folder: ShelfStorage.defaultFolder)
        try? storage.createIfMissing()
        store = TrayStore(storage: storage)
    }
```

In the same file, change the debug seed `if !urls.isEmpty { store.add(urls) }` to the following. A seed copies; it must never move a developer's files.

```swift
        if !urls.isEmpty { store.add(urls, transfer: .copy) }
```

In `Sources/Tray/Tray/TrayWindowController.swift`:
- Delete the `store.refreshAvailability()` line in `paste()` and in `accept(_:)`. The folder watcher keeps the shelf current.
- In `open()`, replace `store.refreshAvailability()` with `store.reload()`.
- In `toggle()`, replace `if !presenter.state.isOpen { store.refreshAvailability() }` with `if !presenter.state.isOpen { store.reload() }`.
- In `paste()`, replace `if case .added(let ids) = store.add(urls) {` with `if case .added(let ids) = store.add(urls, transfer: .copy) {`. ⌘V after ⌘C copies, as in Finder.
- Replace the body of `remove(_:)` with:

```swift
    private func remove(_ items: [TrayItem]) {
        guard !items.isEmpty else { return }
        store.remove(ids: items.map(\.id))
        for item in items where store.item(id: item.id) == nil {
            thumbnails.forget(item)
        }
        selection.prune(to: store.items.map(\.id))
        if selection.isEmpty { presenter.endedInteracting() }
    }
```

In `Sources/Tray/DragDrop/FileDropHandler.swift`, change `return store.add(urls)` to `return store.add(urls, transfer: .move)`. Task 3 replaces this with the Finder rule.

In `Sources/Tray/Tray/TrayItemView.swift`:
- Replace `if !item.isAvailable { unavailableBadge }` with `if item.isArriving { arrivingIndicator }`.
- Replace the whole `unavailableBadge` property, including its doc comment, with:

```swift
    /// Still copying in. A spinner rather than a bar: the tray does not know
    /// how far along a copy is, and a bar that guesses is worse than one that
    /// admits it.
    private var arrivingIndicator: some View {
        ProgressView()
            .controlSize(.mini)
            .tint(palette.primaryInk)
            .offset(x: 2, y: 2)
    }
```

- [ ] **Step 8: Move the other test files onto scratch shelves**

In `Tests/TrayTests/TraySelectionTests.swift`:

1. Run:

```bash
sed -i '' -E 's/func (`[^`]+`)\(\) throws \{/func \1() async throws {/; s/try stocked\(/try await Scratch.stocked(/g' Tests/TrayTests/TraySelectionTests.swift
```

2. Delete the private `stocked(_:)` helper. Keep `directory` and `makeFile` only if something still uses them, and delete them otherwise.
3. Replace the test `a missing file is left off the pasteboard` with:

```swift
    @Test func `a file still arriving is left off the pasteboard`() async throws {
        let store = try await Scratch.stocked(["here.txt"])
        let arriving = TrayItem(url: store.items[0].url, isArriving: true)

        let pasteboard = NSPasteboard(name: .init("TrayTests-\(UUID().uuidString)"))
        #expect(TrayPasteboard.copy([store.items[0], arriving], to: pasteboard))

        // A pasteboard entry for something half-copied fails somewhere the
        // user cannot connect back to the copy they made.
        #expect(TrayPasteboard.pasteableURLs(from: pasteboard).count == 1)
    }
```

4. In `pasting reads back what a copy wrote`, replace the two lines `let destination = TrayStore()` and `destination.add(TrayPasteboard.pasteableURLs(from: pasteboard))` with:

```swift
        let (destination, _, _) = try Scratch.store()
        destination.add(TrayPasteboard.pasteableURLs(from: pasteboard), transfer: .copy)
        await destination.settle()
```

In `Tests/TrayTests/TrayAppearanceTests.swift`:

1. Replace both occurrences of these two lines with `let store = try Self.sampleStore(count: items)`:

```swift
        let store = TrayStore()
        store.add(Self.sampleURLs(count: items))
```

2. Add the following beside `sampleURLs`:

```swift
    /// A shelf holding real apps, so thumbnails are the ones the tray would
    /// actually show. Copied once from `/System/Applications` into a cache,
    /// then cloned into a fresh shelf per render — APFS clones, so free.
    /// Never moved: these are the system's own apps.
    private static func sampleStore(count: Int) throws -> TrayStore {
        let shelf = try Scratch.directory("TrayPreviewShelf")
        let cache = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrayPreviewSamples", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        for app in sampleURLs(count: count) {
            let cached = cache.appendingPathComponent(app.lastPathComponent)
            if !FileManager.default.fileExists(atPath: cached.path) {
                try FileManager.default.copyItem(at: app, to: cached)
            }
            try FileManager.default.copyItem(at: cached, to: shelf.appendingPathComponent(app.lastPathComponent))
        }
        return TrayStore(storage: ShelfStorage(folder: shelf))
    }
```

3. Replace `UserDefaults(suiteName: "TrayPreviews-\(UUID().uuidString)") ?? .standard` with `TestDefaults.scratch("TrayPreviews")`.

In `Tests/TrayTests/TrayShapeTests.swift`, run:

```bash
sed -i '' 's/UserDefaults(suiteName: "TrayTests-\\(UUID().uuidString)")!/TestDefaults.scratch()/g' Tests/TrayTests/TrayShapeTests.swift
```

Then confirm `grep -n "suiteName" Tests/TrayTests/*.swift` prints only the line in `TestSupport.swift`.

- [ ] **Step 9: Run the tests and confirm they pass**

Run: `./Scripts/test.sh 2>&1 | grep -E "error:|✘|Test run" | head -30`
Expected: no errors, no `✘`, and `Test run with N tests … passed`. Run it twice to check that the watcher tests aren't flaky.

- [ ] **Step 10: Checkpoint.** `./Scripts/build.sh` succeeds. Don't commit.

---

### Task 3: Drop-in follows Finder, and the tray ignores its own drags

**Files:**
- Create: `Sources/Tray/DragDrop/DropTransfer.swift`
- Modify: `Sources/Tray/DragDrop/FileDropHandler.swift` (whole file)
- Modify: `Sources/Tray/Tray/TrayDropView.swift`: `respond(to:)` and `prepareForDragOperation(_:)`
- Test: `Tests/TrayTests/DropTransferTests.swift`

**Interfaces:**
- Consumes: `ShelfStorage.Transfer`, `ShelfStorage.isSameVolume(as:)`, and `TrayStore.storage`, `isFolderAvailable`, `isFull` and `add(_:transfer:)`.
- Produces:
  - `DropTransfer.transfer(sourceMask: NSDragOperation, sameVolume: Bool) -> ShelfStorage.Transfer?`.
  - `DropTransfer.operation(for: ShelfStorage.Transfer) -> NSDragOperation`.
  - `FileDropHandler` becomes a `final class`. Its `Acceptance` cases are `.accept(ShelfStorage.Transfer)`, `.full`, `.unavailable` and `.unsupported`.
  - `FileDropHandler.acceptance(carryingFiles:sourceMask:sameVolume:fromTray:)` is the testable seam.

- [ ] **Step 1: Write the failing tests**

Create `Tests/TrayTests/DropTransferTests.swift`:

```swift
import AppKit
import Testing

@testable import Tray

/// Move or copy, decided the way Finder decides it (§38).
@MainActor
struct DropTransferTests {
    @Test(arguments: [
        // (mask, same volume, expected)
        (NSDragOperation.every, true, ShelfStorage.Transfer?.some(.move)),
        (.every, false, .some(.copy)),
        ([.move, .copy], false, .some(.copy)),
        (.copy, true, .some(.copy)),          // ⌥ held
        (.copy, false, .some(.copy)),
        (.generic, true, .some(.move)),       // ⌘ held
        (.generic, false, .some(.move)),
        (.move, false, .some(.move)),
        (.link, true, nil),
        ([], true, nil),
    ])
    func `the transfer matches Finder`(
        mask: NSDragOperation, sameVolume: Bool, expected: ShelfStorage.Transfer?
    ) {
        #expect(DropTransfer.transfer(sourceMask: mask, sameVolume: sameVolume) == expected)
    }

    @Test func `the cursor badge says what will happen`() {
        #expect(DropTransfer.operation(for: .move) == .move)
        #expect(DropTransfer.operation(for: .copy) == .copy)
    }

    // MARK: - Acceptance

    @Test func `files with room are taken, the way Finder would take them`() throws {
        let (store, _, _) = try Scratch.store()
        let handler = FileDropHandler(store: store)

        #expect(handler.acceptance(carryingFiles: true, sourceMask: .every, sameVolume: true, fromTray: false)
            == .accept(.move))
        #expect(handler.acceptance(carryingFiles: true, sourceMask: .every, sameVolume: false, fromTray: false)
            == .accept(.copy))
    }

    @Test func `a drag carrying no files is not the tray's business`() throws {
        let (store, _, _) = try Scratch.store()
        #expect(FileDropHandler(store: store)
            .acceptance(carryingFiles: false, sourceMask: .every, sameVolume: true, fromTray: false)
            == .unsupported)
    }

    @Test func `the tray's own items are not dropped back onto it`() throws {
        let (store, _, _) = try Scratch.store()
        #expect(FileDropHandler(store: store)
            .acceptance(carryingFiles: true, sourceMask: .every, sameVolume: true, fromTray: true)
            == .unsupported)
    }

    @Test func `a source that allows neither move nor copy is refused`() throws {
        let (store, _, _) = try Scratch.store()
        #expect(FileDropHandler(store: store)
            .acceptance(carryingFiles: true, sourceMask: .link, sameVolume: true, fromTray: false)
            == .unsupported)
    }

    @Test func `a full shelf says so rather than pretending`() throws {
        let (store, shelf, _) = try Scratch.store()
        for index in 0..<TrayStore.capacity {
            try Scratch.file("file-\(index).txt", in: shelf)
        }
        store.reload()

        #expect(FileDropHandler(store: store)
            .acceptance(carryingFiles: true, sourceMask: .every, sameVolume: true, fromTray: false)
            == .full)
    }

    @Test func `a missing shelf folder refuses drops`() throws {
        let (store, shelf, _) = try Scratch.store()
        try FileManager.default.removeItem(at: shelf)
        store.reload()

        #expect(FileDropHandler(store: store)
            .acceptance(carryingFiles: true, sourceMask: .every, sameVolume: true, fromTray: false)
            == .unavailable)
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `./Scripts/test.sh 2>&1 | grep -E "error:" | head`
Expected: `cannot find 'DropTransfer' in scope` and `extra arguments … sourceMask`.

- [ ] **Step 3: Implement `DropTransfer`**

Create `Sources/Tray/DragDrop/DropTransfer.swift`:

```swift
import AppKit

/// Whether a drop moves its files onto the shelf or copies them (§38).
///
/// Decided exactly the way Finder decides, so nobody has to learn a second
/// set of rules: on the same disk a drop moves, from another disk it copies,
/// ⌥ forces a copy and ⌘ forces a move. The modifiers reach us already folded
/// into the source's operation mask — ⌥ leaves only `.copy`, ⌘ only
/// `.generic` — so the mask and the volume are all this needs.
enum DropTransfer {
    static func transfer(sourceMask: NSDragOperation, sameVolume: Bool) -> ShelfStorage.Transfer? {
        let canMove = !sourceMask.isDisjoint(with: [.move, .generic])
        let canCopy = sourceMask.contains(.copy)
        switch (canMove, canCopy) {
        case (true, true): return sameVolume ? .move : .copy
        case (true, false): return .move
        case (false, true): return .copy
        case (false, false): return nil
        }
    }

    /// The operation advertised back to the drag, which is what decides the
    /// cursor: a plain arrow for a move, the green "+" for a copy.
    static func operation(for transfer: ShelfStorage.Transfer) -> NSDragOperation {
        switch transfer {
        case .move: .move
        case .copy: .copy
        }
    }
}
```

- [ ] **Step 4: Rewrite `FileDropHandler`**

Replace `Sources/Tray/DragDrop/FileDropHandler.swift` with:

```swift
import AppKit

/// Decides what a drop means (§38).
///
/// A drop *moves* the file onto the shelf — or copies it, by Finder's rules
/// (`DropTransfer`). The decision lives here, separated from the view that
/// receives the drop, so the one rule that touches the user's files is in one
/// readable place.
final class FileDropHandler {
    let store: TrayStore

    /// The volume answer for the drag in progress. `draggingUpdated` fires
    /// continuously, and reading the pasteboard's URLs each time is an
    /// inter-process round trip; which disk the files are on cannot change
    /// mid-drag, so it is read once per drag.
    private var volumeVerdict: (sequence: Int, sameVolume: Bool)?

    init(store: TrayStore) {
        self.store = store
    }

    /// What the tray can do with a drag that is currently overhead.
    enum Acceptance: Equatable {
        /// Files, room for them, and how they will travel.
        case accept(ShelfStorage.Transfer)
        /// Files, but the shelf is full. The tray still opens — being shown a
        /// shelf with sixty-four things on it explains the refusal.
        case full
        /// Files, but the shelf folder cannot be reached. The tray opens and
        /// says so.
        case unavailable
        /// Not something the tray takes — including the tray's own items,
        /// which are already on the shelf.
        case unsupported
    }

    func acceptance(of info: any NSDraggingInfo) -> Acceptance {
        let carriesFiles = PasteboardFileReader.containsFileURLs(info.draggingPasteboard)
        return acceptance(
            carryingFiles: carriesFiles,
            sourceMask: info.draggingSourceOperationMask,
            sameVolume: carriesFiles && sameVolume(for: info),
            fromTray: info.draggingSource is ItemInteractionView
        )
    }

    /// The decision itself, separated from the pasteboard so it can be tested
    /// without conjuring an `NSDraggingInfo`.
    func acceptance(
        carryingFiles: Bool,
        sourceMask: NSDragOperation,
        sameVolume: Bool,
        fromTray: Bool
    ) -> Acceptance {
        guard carryingFiles, !fromTray,
              let transfer = DropTransfer.transfer(sourceMask: sourceMask, sameVolume: sameVolume)
        else { return .unsupported }
        guard store.isFolderAvailable else { return .unavailable }
        return store.isFull ? .full : .accept(transfer)
    }

    /// Brings whatever the drag was carrying onto the shelf.
    ///
    /// Returns the store's own verdict, because the caller has to tell the
    /// *drag source* whether the drop worked — and "nothing landed" and
    /// "nothing needed to land" are different answers.
    func accept(_ info: any NSDraggingInfo) -> TrayStore.AddOutcome {
        let urls = PasteboardFileReader.fileURLs(from: info.draggingPasteboard)
        guard !urls.isEmpty,
              let transfer = DropTransfer.transfer(
                sourceMask: info.draggingSourceOperationMask,
                sameVolume: sameVolume(for: info)
              )
        else { return .nothingUsable }
        return store.add(urls, transfer: transfer)
    }

    /// Whether the drag's first file is on the shelf's disk. One file decides
    /// for the whole drop, as it does in Finder.
    private func sameVolume(for info: any NSDraggingInfo) -> Bool {
        if let verdict = volumeVerdict, verdict.sequence == info.draggingSequenceNumber {
            return verdict.sameVolume
        }
        let first = PasteboardFileReader.fileURLs(from: info.draggingPasteboard).first
        let same = first.map(store.storage.isSameVolume(as:)) ?? false
        volumeVerdict = (info.draggingSequenceNumber, same)
        return same
    }
}
```

- [ ] **Step 5: Teach `TrayDropView` the new answers**

In `Sources/Tray/Tray/TrayDropView.swift`, replace the `switch` in `respond(to:)` with:

```swift
        switch dragAcceptance(sender) {
        case .accept(let transfer):
            updateDragPhase(for: sender)
            return DropTransfer.operation(for: transfer)

        case .full, .unavailable:
            // Still open: a shelf with everything already on it, or one
            // saying its folder is gone, explains the refusal better than a
            // cursor alone.
            onDragApproach()
            return []

        case .unsupported:
            return []
        }
```

Replace `prepareForDragOperation(_:)` with:

```swift
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if case .accept = dragAcceptance(sender) { return true }
        return false
    }
```

Update the doc comment above `respond(to:)` so it says the view answers "move" or "copy" by Finder's rules instead of always `.copy`. Delete every remaining reference to `FileDropHandler.advertisedOperation` (`grep -rn advertisedOperation Sources Tests` must print nothing).

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `./Scripts/test.sh 2>&1 | grep -E "error:|✘|Test run" | head`
Expected: all green.

- [ ] **Step 7: Checkpoint.** `./Scripts/build.sh` succeeds. Don't commit.

---

### Task 4: Drag-out moves, the menus say "Trash", and failures show up on the shelf

**Files:**
- Modify: `Sources/Tray/DragDrop/FileDragSource.swift`: mask, `endedAt`, the `onDragEnded` type and doc comments
- Modify: `Sources/Tray/Tray/TrayItemView.swift`: the `onDragEnded` type and the menu title
- Modify: `Sources/Tray/Tray/TrayContentView.swift`: the `onItemDragEnded` type, the notice line and the header menu title
- Modify: `Sources/Tray/Tray/TrayWindowController.swift`: `finishItemDrag`
- Test: `Tests/TrayTests/DragOutTests.swift`

**Interfaces:**
- Consumes: `TrayStore.finishDragOut(of:operation:)`, `TrayStore.notice` and `TrayStore.isFolderAvailable`.
- Produces: `ItemInteractionView.operationMask(for: NSDraggingContext) -> NSDragOperation`. `onDragEnded` and `onItemDragEnded` change type to `([TrayItem], NSDragOperation) -> Void`.

- [ ] **Step 1: Write the failing test**

Create `Tests/TrayTests/DragOutTests.swift`:

```swift
import AppKit
import Testing

@testable import Tray

/// What a drag out of the shelf offers (§21, §38).
@MainActor
struct DragOutTests {
    @Test func `outside the app a shelf item can be moved, copied or trashed`() {
        #expect(ItemInteractionView.operationMask(for: .outsideApplication) == [.move, .copy, .delete])
    }

    @Test func `inside the app a shelf item goes nowhere`() {
        #expect(ItemInteractionView.operationMask(for: .withinApplication) == [])
    }

    @Test func `an arriving item says so to VoiceOver`() throws {
        let file = try Scratch.file("big.mov", in: try Scratch.directory())
        #expect(TrayItem(url: file, isArriving: true).accessibilityLabel == "big.mov, arriving")
    }
}
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `./Scripts/test.sh 2>&1 | grep -E "error:" | head`
Expected: `type 'ItemInteractionView' has no member 'operationMask'`.

- [ ] **Step 3: Implement the drag source changes**

In `Sources/Tray/DragDrop/FileDragSource.swift`:

1. Change `var onDragEnded: ([TrayItem], Bool) -> Void = { _, _ in }` to `var onDragEnded: ([TrayItem], NSDragOperation) -> Void = { _, _ in }`.
2. Change `let onDragEnded: ([TrayItem], Bool) -> Void` in `ItemInteractionLayer` to `let onDragEnded: ([TrayItem], NSDragOperation) -> Void`.
3. Replace the whole `extension ItemInteractionView: NSDraggingSource { … }` with:

```swift
extension ItemInteractionView: NSDraggingSource {
    /// What a drag out of the shelf allows (§21, §38).
    ///
    /// Move first: dragging a file from the shelf into a Finder folder puts it
    /// there and takes it off the shelf. Copy, for destinations that only
    /// copy — a browser upload, Mail — which leave the shelf's file where it
    /// is. Delete, so the Dock's Trash accepts it. Inside the app, nothing:
    /// reordering is the tray's own business, not a pasteboard round trip.
    static func operationMask(for context: NSDraggingContext) -> NSDragOperation {
        switch context {
        case .withinApplication: []
        case .outsideApplication: [.move, .copy, .delete]
        @unknown default: [.move, .copy, .delete]
        }
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        Self.operationMask(for: context)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        let carried = itemsInFlight
        itemsInFlight = []
        onDragEnded(carried, operation)
    }
}
```

4. Rewrite the type's doc comment. Replace "the tray removes an item on a successful drop and springs it back on a cancel (§22), and only a drag *source* is told which happened" with "the shelf has to learn how a drag ended — moved, copied, trashed or cancelled (§22) — and only a drag *source* is told". In `beginDrag(with:)`, replace the comment "The tray writes a reference to each original file; it never has a copy to offer (§3, §38)." with "Each URL is the file in the shelf folder; a destination that moves it takes it off the shelf (§3, §38)."

- [ ] **Step 4: Thread the operation through the views and the controller**

- In `Sources/Tray/Tray/TrayItemView.swift`, change `let onDragEnded: ([TrayItem], Bool) -> Void` to `let onDragEnded: ([TrayItem], NSDragOperation) -> Void`. In `buildMenu()`, change `"Remove from Tray"` to `"Move to Trash"`.
- In `Sources/Tray/Tray/TrayContentView.swift`, change `let onItemDragEnded: ([TrayItem], Bool) -> Void` to `let onItemDragEnded: ([TrayItem], NSDragOperation) -> Void`. In the header `Menu`, change `Button("Clear the Shelf", action: onClearAll)` to `Button("Move All to Trash", action: onClearAll)`.
- Still in `TrayContentView`, show the notice. Replace the `VStack` in `expandedContents` with:

```swift
        VStack(spacing: 0) {
            header
                // Exactly the housing's own strip, so the header's contents
                // land on the same line as the menu bar's.
                .frame(height: cutout.height)
                .padding(.horizontal, settings.headerInset)
                .zIndex(1)

            if let notice = noticeText {
                Text(notice)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.ink(0.75))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, TrayMetrics.horizontalInset)
                    .padding(.top, 4)
                    .transition(.opacity)
                    .accessibilityAddTraits(.updatesFrequently)
            }

            content
                .padding(.horizontal, TrayMetrics.horizontalInset)
                .padding(.top, TrayMetrics.spacing)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.bottom, TrayMetrics.bottomInset)
        .animation(motion.hover, value: noticeText)
```

and add, next to `contentMetrics`:

```swift
    /// One line about something that went wrong: a file that would not move,
    /// or a shelf folder that has gone missing.
    private var noticeText: String? {
        store.notice ?? (store.isFolderAvailable
            ? nil
            : "The shelf folder isn't available. Choose another in Settings.")
    }
```

- In `Sources/Tray/Tray/TrayWindowController.swift`, change the `onItemDragEnded:` argument to:

```swift
            onItemDragEnded: { [weak self] items, operation in
                self?.finishItemDrag(items, operation: operation)
            },
```

and replace `finishItemDrag` with:

```swift
    /// The folder decides what left. Finder moving a file takes it out of the
    /// folder; an app copying it leaves it there; the Dock's Trash leaves the
    /// deleting to us. Finder can finish its move a moment after the drag
    /// ends — the folder watcher catches that.
    private func finishItemDrag(_ items: [TrayItem], operation: NSDragOperation) {
        presenter.endedDraggingItems()
        store.finishDragOut(of: items.map(\.id), operation: operation)
        for item in items where store.item(id: item.id) == nil {
            thumbnails.forget(item)
        }
        selection.prune(to: store.items.map(\.id))
        if selection.isEmpty { presenter.endedInteracting() }
    }
```

`Tests/TrayTests/TrayAppearanceTests.swift` passes `onItemDragEnded: { _, _ in }` and still compiles unchanged.

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `./Scripts/test.sh 2>&1 | grep -E "error:|✘|Test run" | head`
Expected: all green. Also confirm `grep -rn "Remove from Tray\|Clear the Shelf" Sources` prints nothing.

- [ ] **Step 6: Checkpoint.** `./Scripts/build.sh` succeeds. Don't commit.

---

### Task 5: Choosing the storage folder in Settings

**Files:**
- Modify: `Sources/Tray/Settings/SettingsStore.swift`: key, property, load and `storageFolder`
- Modify: `Sources/Tray/App/AppState.swift`: `init`, `chooseStorageFolder()` and `revealStorageFolder()`
- Modify: `Sources/Tray/Settings/SettingsView.swift`: pass the store and the two actions
- Modify: `Sources/Tray/Settings/SettingsPanes.swift`: the `GeneralPane` card
- Test: `Tests/TrayTests/StorageFolderSettingTests.swift`

**Interfaces:**
- Consumes: `ShelfStorage.defaultFolder`, `ShelfStorage.problem(withFolder:home:)`, `ShelfStorage.contents()`, `TrayStore.relocate(to:)`, `TrayStore.storage` and `TrayStore.isFolderAvailable`.
- Produces: `SettingsStore.storageFolderPath: String?`, `SettingsStore.storageFolder: URL`, `AppState.chooseStorageFolder()` and `AppState.revealStorageFolder()`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/TrayTests/StorageFolderSettingTests.swift`:

```swift
import Foundation
import Testing

@testable import Tray

/// Where the shelf keeps its files (§33).
@MainActor
struct StorageFolderSettingTests {
    @Test func `unset, the shelf lives in Application Support`() {
        let settings = SettingsStore(defaults: TestDefaults.scratch())

        #expect(settings.storageFolderPath == nil)
        #expect(settings.storageFolder == ShelfStorage.defaultFolder)
    }

    @Test func `a chosen folder survives a relaunch`() {
        let defaults = TestDefaults.scratch()
        SettingsStore(defaults: defaults).storageFolderPath = "/Users/someone/Shelf"

        let relaunched = SettingsStore(defaults: defaults)

        #expect(relaunched.storageFolder.path == "/Users/someone/Shelf")
    }

    @Test func `going back to the default forgets the choice`() {
        let defaults = TestDefaults.scratch()
        let settings = SettingsStore(defaults: defaults)
        settings.storageFolderPath = "/Users/someone/Shelf"

        settings.storageFolderPath = nil

        #expect(SettingsStore(defaults: defaults).storageFolderPath == nil)
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `./Scripts/test.sh 2>&1 | grep -E "error:" | head`
Expected: `value of type 'SettingsStore' has no member 'storageFolderPath'`.

- [ ] **Step 3: Add the setting**

In `Sources/Tray/Settings/SettingsStore.swift`:
- Add `static let storageFolder = "storageFolder"` to `enum Key`.
- Add the property next to the other stored settings:

```swift
    /// Where the shelf keeps its files, or `nil` for the default. Stored as a
    /// path: the app is not sandboxed (§39), so no bookmark is needed.
    var storageFolderPath: String? {
        didSet {
            guard storageFolderPath != oldValue else { return }
            if let storageFolderPath {
                defaults.set(storageFolderPath, forKey: Key.storageFolder)
            } else {
                defaults.removeObject(forKey: Key.storageFolder)
            }
        }
    }

    var storageFolder: URL {
        storageFolderPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? ShelfStorage.defaultFolder
    }
```

- In `init(defaults:)`, beside the other loads (for example after `traySize = …`), add:

```swift
        storageFolderPath = defaults.string(forKey: Key.storageFolder)
```

- [ ] **Step 4: Build the store from the setting, and add the two actions**

In `Sources/Tray/App/AppState.swift`, change `let settings = SettingsStore()` to `let settings: SettingsStore` and replace the `init()` from Task 2 with:

```swift
    init() {
        let settings = SettingsStore()
        // Only the default folder is ever created. A folder the user chose
        // that has gone missing is reported, not quietly recreated (§33).
        if settings.storageFolderPath == nil {
            try? ShelfStorage(folder: ShelfStorage.defaultFolder).createIfMissing()
        }
        self.settings = settings
        self.store = TrayStore(storage: ShelfStorage(folder: settings.storageFolder))
    }
```

Add a new section under `// MARK: - Settings`:

```swift
    // MARK: - Storage folder

    /// Lets the user pick where the shelf keeps its files, and moves the shelf
    /// there. Everything in the chosen folder appears on the tray, so a folder
    /// that already holds files is confirmed first.
    func chooseStorageFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        panel.message = "Choose where Tray keeps the files on its shelf."
        panel.directoryURL = store.storage.folder.deletingLastPathComponent()

        NSApp.activate()
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        guard ShelfStorage.key(folder) != ShelfStorage.key(store.storage.folder) else { return }

        if let problem = ShelfStorage.problem(withFolder: folder) {
            inform("That folder can't be the shelf", detail: problem)
            return
        }

        let existing = (try? ShelfStorage(folder: folder).contents().count) ?? 0
        if existing > 0, !confirm(
            "Use a folder that already has files in it?",
            detail: "\(existing) item\(existing == 1 ? "" : "s") in this folder will appear on the shelf.",
            action: "Use Folder"
        ) {
            return
        }

        Task {
            do {
                try await store.relocate(to: folder)
                settings.storageFolderPath = folder.path
            } catch {
                inform("Couldn't move the shelf", detail: error.localizedDescription)
            }
        }
    }

    func revealStorageFolder() {
        NSWorkspace.shared.open(store.storage.folder)
    }

    private func confirm(_ message: String, detail: String, action: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func inform(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.runModal()
    }
```

- [ ] **Step 5: Show it in Settings → General**

In `Sources/Tray/Settings/SettingsView.swift`:
- Add these properties to `SettingsView` after `launchAtLogin`:

```swift
    let store: TrayStore
    let onChooseStorageFolder: @MainActor @Sendable () -> Void
    let onRevealStorageFolder: @MainActor @Sendable () -> Void
```

- Pass them to `GeneralPane(…)` as `store: store, onChooseStorageFolder: { onChooseStorageFolder() }, onRevealStorageFolder: { onRevealStorageFolder() },`, after `launchAtLogin: launchAtLogin,`.
- In `SettingsWindowController.init(state:)`, add to the `SettingsView(…)` call, after `launchAtLogin: state.launchAtLogin,`:

```swift
            store: state.store,
            onChooseStorageFolder: { [weak state] in state?.chooseStorageFolder() },
            onRevealStorageFolder: { [weak state] in state?.revealStorageFolder() },
```

In `Sources/Tray/Settings/SettingsPanes.swift`, inside `GeneralPane`:
- Add these properties after `launchAtLogin`:

```swift
    let store: TrayStore
    let onChooseStorageFolder: () -> Void
    let onRevealStorageFolder: () -> Void
```

- Add these parameters to every `GeneralPane(...)` call site. `grep -rn "GeneralPane(" Sources Tests` lists them, and a debug preview may exist.
- Inside `SettingsPaneLayout { … }`, after the existing `SettingsCard`, add:

```swift
            SettingsCard(
                title: "Shelf",
                footnote: "Files you drop on the tray are moved into this folder. Removing one from the shelf moves it to the Trash."
            ) {
                SettingsRow(
                    icon: "folder",
                    title: "Shelf folder",
                    description: (store.storage.folder.path as NSString).abbreviatingWithTildeInPath
                ) {
                    HStack(spacing: 6) {
                        Button("Show in Finder", action: onRevealStorageFolder)
                            .disabled(!store.isFolderAvailable)
                        Button("Choose…", action: onChooseStorageFolder)
                    }
                    .controlSize(.small)
                }

                if !store.isFolderAvailable {
                    SettingsCallout(
                        icon: "exclamationmark.triangle.fill",
                        tint: .orange,
                        text: "This folder isn't available. Until it is, the shelf is empty and drops are refused.",
                        actionTitle: "Choose…",
                        action: onChooseStorageFolder
                    )
                }
            }
```

- Update `GeneralPane`'s `lead:` to read `"How Tray behaves when your Mac starts, where you can reach it, and where it keeps your files."`.

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `./Scripts/test.sh 2>&1 | grep -E "error:|✘|Test run" | head`
Expected: all green.

- [ ] **Step 7: Checkpoint.** `./Scripts/build.sh` succeeds. Don't commit.

---

### Task 6: The documents tell the truth, the old test defaults are cleaned up, and the app is checked by hand

**Files:**
- Modify: `docs/SPEC.md`: §3, §38, §39 (first bullet) and §40
- Modify: `README.md`: lines 12, 43 and 51
- Modify: `docs/PRIVACY.md`: the "What is never touched" section
- Modify: `CHANGELOG.md`: Unreleased → Changed, and the earlier *Clear the Shelf* mention
- Modify: `Sources/Tray/Settings/SettingsPanes.swift`: `PrivacyPane`, if it claims files are never touched

**Interfaces:** none (docs only).

- [ ] **Step 1: Find every stale promise**

Run:

```bash
grep -rn -i "never moves\|nothing moves\|not move, copy\|never touched\|does not move\|reference to the file\|Remove from Tray\|Clear the Shelf\|refreshAvailability\|in-memory" README.md docs/SPEC.md docs/PRIVACY.md CHANGELOG.md Sources
```

Every hit gets updated in the steps below. `CHANGELOG.md` entries under released versions (`## [0.1.0]`) stay as they are, because they describe history.

- [ ] **Step 2: Rewrite SPEC §3, §38, §40**

Replace the body of `# 3. TRAY SEMANTICS` up to the `---` with:

````markdown
The tray is a **holding place that owns what it holds** — cut and paste for
files.

Dropping a file on the tray **moves it into the shelf folder**. It leaves the
folder it came from and lives only on the shelf:

```text
~/Desktop/photo.jpg   →   <shelf folder>/photo.jpg
```

Dragging it from the tray into a Finder folder moves it there and takes it off
the shelf.

## Move or copy

Drops follow Finder exactly: on the same disk a drop moves; from another disk
it copies and the original stays; ⌥ forces a copy and ⌘ forces a move.
Dragging out to an app that can only copy (a browser upload, Mail) leaves the
file on the shelf.

## Where the files live

In the **shelf folder**, chosen in Settings → General. The default is
`~/Library/Application Support/Tray/Shelf` — never `/tmp`, which macOS empties.

## The folder is the shelf

Whatever is in the folder is on the tray. Quitting or crashing loses nothing;
files added or deleted in Finder appear on or leave the shelf.

## Removing

Removing an item (× or *Move All to Trash*) moves the file to the Trash.
````

Replace the body of `# 38. DRAG/DROP TECHNICAL REQUIREMENTS` from "When dragging a supported filesystem object…" to the `---` with:

```markdown
Advertise the operation Finder would perform: `.move` on the same volume,
`.copy` across volumes, honouring ⌥ (copy-only mask) and ⌘ (`.generic`).
The tray's own items dragged over it are refused.

Dragging out offers `[.move, .copy, .delete]` outside the app. After the drag,
the shelf re-reads its folder: a file Finder moved has left, a file an app
copied has stayed. `.delete` (the Dock's Trash) is performed by the tray.

All file operations live in `ShelfStorage`. Document this distinction clearly
in the code.
```

In §39, change the first bullet to: `- Plain URLs and paths are sufficient; no security-scoped bookmarks are needed, including for the stored shelf-folder path.` Leave the rest of §39 as it is: the app still needs no permissions. Add one line after the "Do not request or require" list: `macOS may ask once per protected folder (Desktop, Documents, Downloads) the first time a file is moved out of it. That prompt is the system's, not a permission the app requests.`

Replace the body of `# 40. PERSISTENCE MODEL` with:

```markdown
`TrayStore` is a view of the shelf folder (`ShelfStorage`). There is no
database and no manifest: the folder is the persistent state, arrival order
comes from each file's added-to-folder date, and ids and drop order are kept
for the session.
```

- [ ] **Step 3: README and Privacy**

- `README.md:12` becomes: `Drag files in, and they leave their folder for the shelf. Drag them out where they belong.`
- Replace `README.md:43` with: `- **It moves your files, the way Finder would.** A file dropped on the shelf moves into Tray's shelf folder, and dragging it into another folder moves it there. From another disk it copies instead, and ⌥ always copies. Nothing is lost on quit or crash: the folder is the shelf.`
- In `README.md:51`, change `Remove from Tray` to `Move to Trash`.
- Replace the `## What is never touched` section of `docs/PRIVACY.md` with a `## What happens to your files` section that says the following.
  - Files dropped on the tray are moved, or copied from another disk, into the shelf folder shown in Settings.
  - They stay there until dragged out or moved to the Trash.
  - Tray never reads their contents beyond what Quick Look and thumbnails need.
  - Nothing leaves the Mac.

- [ ] **Step 4: CHANGELOG**

Under `## [Unreleased]` → `### Changed`, add as the first bullet:

```markdown
- **The tray now holds your files instead of pointing at them.** Dropping a
  file moves it into the shelf folder — Finder's rules: same disk moves,
  another disk copies, ⌥ copies, ⌘ moves — and dragging it into a folder moves
  it there and off the shelf. Dragging it into an app that only copies leaves
  it on the shelf. Removing moves it to the Trash. The shelf folder is set in
  Settings → General (default `~/Library/Application Support/Tray/Shelf`) and
  *is* the shelf: nothing is lost on quit or crash, and files added there in
  Finder appear on the tray. A failed move leaves the original where it was
  and says why under the header.
```

In the earlier Unreleased bullet that mentions *Clear the Shelf*, change it to *Move All to Trash*.

- [ ] **Step 5: Clean up the leftover test defaults once**

Run:

```bash
defaults domains | tr ',' '\n' | sed 's/^ *//' | grep -E '^(TrayPreviews|TrayTests)-' | while read -r domain; do defaults delete "$domain"; done
```

Then confirm `defaults domains | tr ',' '\n' | grep -cE 'TrayPreviews-|TrayTests-'` prints `0`. Run `./Scripts/test.sh` once more and confirm the count is still `0` afterwards. That proves `TestDefaults` cleans up after itself.

- [ ] **Step 6: Full verification**

Run: `./Scripts/test.sh 2>&1 | grep -E "✘|Test run"` and `./Scripts/build.sh 2>&1 | tail -3`.
Expected: `Test run … passed`, then `▸ Done: …/build/Tray.app`.

- [ ] **Step 7: Check by hand in the real app.** These need a person's mouse. Relaunch with `pkill -x Tray; open build/Tray.app` and record the log with `/usr/bin/log stream --level debug --predicate 'subsystem == "com.tray.app"'`.

1. Drag a file from `~/Desktop` onto the tray. It disappears from the Desktop and is on the shelf. If macOS asks for Desktop access, allow it.
2. Hold ⌥ and drag another file in. The cursor shows the green "+" and the original stays.
3. Drag a shelf item into a Finder window on the same disk. It lands there and leaves the shelf within a second.
4. Drag a shelf item into a Safari upload field or a Mail message. The app gets it and the item stays on the shelf.
5. Drag a shelf item onto the Dock's Trash. It goes to the Trash and leaves the shelf.
6. Click × (Move to Trash) on an item. It is in the Trash. Check whether Finder's **Put Back** works for it. If it doesn't, switch `ShelfStorage.moveToTrash` to `NSWorkspace.shared.recycle` (spec, `ShelfStorage` section) and re-check.
7. Quit and relaunch Tray. The shelf still shows the same files.
8. In Settings → General, click **Show in Finder** to open the folder. Add a file there in Finder and it appears on the tray. Then click **Choose…**, pick a new empty folder, and confirm the items move there.
9. Drag a file from a USB stick or disk image, if one is available. It copies, the original stays, and the tile shows the spinner until the copy finishes.

Report the results to the user, including any step that couldn't be run.
