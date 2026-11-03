import AppKit

/// Copying items out of the tray and pasting them in (⌘C, ⌘V).
///
/// The same rule as every other route in and out of the shelf: what moves is a
/// *reference*. Copying writes the file's URL to the pasteboard, which is
/// exactly what Finder writes when you copy a file — so pasting into Finder,
/// a Save dialog or a mail message does what the user expects, and the original
/// never moves (§3, §38).
enum TrayPasteboard {
    /// Writes items to the general pasteboard as file URLs.
    ///
    /// Returns false when nothing usable was written, so the caller can decline
    /// to claim it copied something.
    @discardableResult
    static func copy(_ items: [TrayItem], to pasteboard: NSPasteboard = .general) -> Bool {
        // Only items that still exist: a pasteboard entry pointing at a deleted
        // file fails at paste time, somewhere the user cannot connect to the
        // copy they made here (§52).
        let urls = items.filter(\.isAvailable).map { $0.url as NSURL }
        guard !urls.isEmpty else { return false }

        pasteboard.clearContents()
        return pasteboard.writeObjects(urls)
    }

    /// Reads whatever files the pasteboard is holding.
    static func pasteableURLs(from pasteboard: NSPasteboard = .general) -> [URL] {
        PasteboardFileReader.fileURLs(from: pasteboard)
    }

    static func hasPasteableFiles(_ pasteboard: NSPasteboard = .general) -> Bool {
        PasteboardFileReader.containsFileURLs(pasteboard)
    }
}
