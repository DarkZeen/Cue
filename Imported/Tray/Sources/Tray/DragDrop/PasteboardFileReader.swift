import AppKit
import UniformTypeIdentifiers

/// Pulls filesystem URLs out of a dragging pasteboard (§38).
///
/// Everything here is defensive. A pasteboard is data from another process and
/// can be empty, malformed, or full of things that are not files at all; none
/// of those may crash the tray (§80).
enum PasteboardFileReader {
    /// Reads every file URL a drag is carrying, in the order the source
    /// supplied them, so a multi-file drop lands in a predictable order.
    static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]

        guard let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL] else { return [] }

        return objects.filter(\.isFileURL)
    }

    /// Whether a drag is carrying anything the tray can accept, without
    /// materialising the URLs. Used on `draggingEntered`, which is called
    /// often enough that it should stay cheap.
    static func containsFileURLs(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
    }
}
