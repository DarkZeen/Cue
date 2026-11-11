# Move files into the tray

**Status:** design approved in chat on 2026-10-05; awaiting spec review.
**Replaces:** the reference-only shelf in SPEC §3, §38 and §40.

## Purpose

The tray is used to move files between folders: "cut and paste for files". A
file dropped on the tray leaves its folder and lives only in the tray. Dragging
it into another folder puts it there and takes it off the shelf.

Today the tray only remembers a URL and never touches the original. That
behaviour is **removed**, not kept as an option.

## Decisions

| Question | Decision |
|---|---|
| Where tray files live | A **storage folder** chosen in Settings. Default `~/Library/Application Support/Tray/Shelf`. Never `/tmp`, which is emptied on restart. |
| Drop-in: move or copy | **Follow Finder.** Same volume: move. Other volume: copy. ⌥ forces copy, ⌘ forces move. |
| Drag-out into a Finder folder | Finder moves the file and it leaves the shelf. |
| Drag-out into a copy-only app (browser, Mail, Slack) | The app gets a copy and **the file stays on the shelf**. |
| Drag-out to another volume | Finder copies, so the file stays on the shelf. ⌘ forces a move. |
| Remove (× and Clear the Shelf) | The file goes to the **Trash**. |
| Old reference-only mode | **Removed.** No setting. |

## Model: the folder is the shelf

The storage folder is the only source of truth. The shelf shows the folder's
visible contents (hidden files such as `.DS_Store` are skipped), oldest first.
Order comes from each file's `addedToDirectoryDate`, falling back to its
creation date, with name as the tie-breaker. No database or manifest is used.

This means:

- **Crashes and quits:** nothing is lost. After a relaunch the shelf is whatever
  is in the folder.
- **Finder edits:** a file added to or deleted from the folder in Finder shows
  up on, or leaves, the shelf.
- **Refreshes:** the shelf re-reads the folder at launch, after every
  operation, and when a directory watcher (`DispatchSource` file-system object
  source on the folder) reports a change. It is event-driven, so §26 holds.
- **No persistent state for the shelf itself:** `TrayItem.availability` and
  `refreshAvailability()` go away. Anything in the folder is present by
  definition.

## Components

### `ShelfStorage` (new, `Sources/Tray/Files/ShelfStorage.swift`)

This is the only type that touches the file system for the shelf. It has no
UI, takes `FileManager` and the folder URL, and can be tested against a
temporary directory.

- `contents() -> [URL]`: the visible items, in shelf order.
- `bringIn(_ urls: [URL], operation: Transfer) async throws -> [URL]`: moves
  or copies each URL into the folder and returns the new locations. On a name
  clash it renames the incoming item to `name 2.ext`, `name 3.ext` and so on,
  as Finder does. A URL already inside the folder is a no-op that returns the
  same URL.
- `trash(_ urls: [URL]) throws`: sends files to the Trash with
  `FileManager.trashItem` (or `NSWorkspace.recycle`, whichever keeps Finder's
  Put Back working; check this during implementation).
- `relocate(to newFolder: URL) async throws`: moves every shelf item into the
  new folder, renaming on clash.
- `Transfer` is `.move` or `.copy`.
- The work runs off the main actor. A rename on the same volume is instant, but
  a cross-volume copy can take minutes and must not block the UI.

### `TrayStore` (changed)

`TrayStore` becomes a view of `ShelfStorage`. It is still `@Observable` and
keeps its public surface (`items`, `add`, `remove`, `removeAll`, `isFull`,
`count`), so the UI changes little.

- `add(_:operation:)` calls `bringIn` and then reloads.
- `remove` and `removeAll` call `trash` and then reload.
- `reload()` rebuilds `items` from `contents()`.
- Items still copying show as **arriving**: a dimmed tile with a small
  progress indicator. They become normal tiles when the copy finishes and leave
  if it fails.
- Capacity (64) still limits drops. Files put into the folder from Finder are
  all shown, even past 64.

### `TrayItem` (changed)

`TrayItem` drops `Availability`. It gains `isArriving: Bool`. Its `url` is
always inside the storage folder, except for an arriving item, which shows the
source file until the copy lands.

### Drop-in: `TrayDropView` and `FileDropHandler`

- **Advertised operation.** `draggingEntered` and `draggingUpdated` work out an
  operation the way Finder does:
  - **Source mask is copy-only (⌥ held, or the source only offers copy):**
    `.copy`.
  - **Source mask is move-only (⌘ held):** `.move`.
  - **Otherwise:** `.move` if the first file is on the same volume as the
    storage folder (compare `volumeIdentifierKey`), else `.copy`.

  The cursor shows the green "+" badge when the drop would copy, as in Finder.
- **Drop.** `performDragOperation` hands the URLs and the operation to the
  store.
- **Own drags are ignored.** Drags whose `draggingSource` is the tray's own
  item view are rejected (`[]`). This also fixes the stray
  `draggingItems → dragOver` state seen in the log today.

### Drag-out: `FileDragSource`

- **Allowed operations.** `sourceOperationMaskFor(.outsideApplication)` returns
  `[.move, .copy, .delete]`. Within the application it still returns `[]`.
- **Ending a drag.** `endedAt(operation:)` reloads the store instead of
  removing items by assumption, so **whether the file is still in the folder
  decides whether it is still on the shelf.**
  - **Finder moved it:** it is gone from the folder and leaves the shelf.
  - **An app copied it:** it is still in the folder and stays.
- **Dropped on the Dock's Trash (`.delete`):** the source has to delete the
  file itself, so the store trashes it.

### Settings → General

- **Storage folder:** a row showing the path, with **Choose…** (an `NSOpenPanel`
  folder picker that can create folders) and **Show in Finder**.
- **Choosing a folder that is not empty:** a confirmation reads "N items in
  this folder will appear on the shelf." Choosing the user's home folder or the
  root of a volume is refused.
- **Confirming a new folder:** the existing shelf items move into it
  (`relocate`), and if that fails the setting stays unchanged.
- **Storage:** the path is kept in `UserDefaults`. The app isn't sandboxed
  (§39), so it doesn't need a security-scoped bookmark.

## Errors

| Failure | Behaviour |
|---|---|
| Move or copy fails (permission denied, disk full, file in use, source vanished) | That item does not join the shelf, the original is left where it was, and the tray briefly shows a one-line reason under the header, e.g. "Couldn't move report.pdf: permission denied". Other files in the same drop still land. |
| Partial copy | The partial file is deleted from the storage folder. |
| Storage folder missing at launch (unmounted drive, deleted) | The shelf shows empty and drops are refused with a reason. Settings shows "Folder unavailable" with Choose…. The app does **not** silently recreate the default and lose track. |
| Trash fails | The item stays on the shelf and the reason is shown. |
| macOS privacy prompt (moving out of Desktop, Documents or Downloads) | It is shown once per folder by macOS. If it is denied, the error above applies. Full Disk Access avoids the prompts but is not required. |

## Documentation to update

- **SPEC.md:** rewrite §3 (semantics), §38 (drag operations) and §40
  (persistence). §39 stays: still no sandbox and no permissions required.
- **README.md:** remove "Nothing moves on disk" and describe move semantics.
- **docs/PRIVACY.md:** replace "What is never touched" with what the app moves
  and where.
- **CHANGELOG.md:** add the change under Unreleased → Changed.
- **Code comments** that promise "never moves the original" are rewritten:
  `TrayItem`, `TrayStore`, `FileDropHandler`, `FileDragSource`,
  `TrayWindowController.accept`, and `Tray.entitlements`.

## Testing

`ShelfStorage` tests use a fresh temporary directory per test and never touch
real user folders. The volume check is injected, so cross-volume behaviour can
be tested on one disk.

- **Moving in:** a moved-in file is gone from its source, present in the
  folder, and on the shelf.
- **Copying in:** a copied-in file stays at its source and is also in the
  folder.
- **Name clashes:** produce `name 2.ext` and then `name 3.ext`. A file already
  in the folder is a no-op.
- **Folders:** a whole folder moves and copies.
- **Order:** follows the added date, and survives a reload, which stands in for
  a relaunch.
- **Hidden files** are not shown.
- **Trash:** removing sends the file to the Trash and off the shelf.
- **Relocate** moves everything and handles name clashes.
- **Failed copy:** leaves no partial file and keeps the source.
- **Drag-out:** after a drag ends, a file still in the folder stays on the
  shelf and a file that is gone leaves it.
- **Operation choice:** a pure function from (mask, same volume) to the
  operation, covering every row of the Finder table.
- **Own drags:** a drag from the tray's own items is rejected.

Also, the appearance preview tests delete their `TrayPreviews-<UUID>` defaults
suite afterwards (`removePersistentDomain`), and the existing leftovers on this
Mac are cleaned up once.

## Out of scope

Reordering by drag (§53), file promises (Mail and Photos drags), a global
shortcut, and per-display shelves. These stay on the roadmap.
