import AppKit

/// Decides what a drop means (§38).
///
/// Separated from the view that receives it so the rule that matters most —
/// **a drop stores a reference and never copies, moves or modifies the
/// original file** (§3, §38) — lives in one readable place instead of being
/// implied by the absence of code in a view controller.
struct FileDropHandler {
    let store: TrayStore

    /// The operation advertised back to the drag source.
    ///
    /// `.copy` is the honest answer to macOS's question "what will you do with
    /// this?" — it tells the source that its file stays where it is. The tray
    /// does not even copy; it remembers a URL. There is no drag operation that
    /// means "reference", and `.copy` is the one that leaves the original
    /// untouched.
    static let advertisedOperation: NSDragOperation = .copy

    /// What the tray can do with a drag that is currently overhead.
    enum Acceptance: Equatable {
        /// Files, and room for them.
        case accept
        /// Files, but the shelf is full. Distinct from `unsupported` because
        /// the tray still opens — being shown a shelf with sixty-four things on
        /// it explains the refusal better than any message could.
        case full
        /// Not something the tray takes.
        case unsupported
    }

    func acceptance(of info: any NSDraggingInfo) -> Acceptance {
        acceptance(carryingFiles: PasteboardFileReader.containsFileURLs(info.draggingPasteboard))
    }

    /// The decision itself, separated from reading the pasteboard so it can be
    /// tested without conjuring an `NSDraggingInfo`.
    func acceptance(carryingFiles: Bool) -> Acceptance {
        guard carryingFiles else { return .unsupported }
        return store.isFull ? .full : .accept
    }

    /// Stashes whatever the drag was carrying.
    ///
    /// Returns the store's own verdict rather than just the ids that landed,
    /// because the caller has to tell the *drag source* whether the drop
    /// worked — and "nothing landed" and "nothing needed to land" are different
    /// answers to that question.
    func accept(_ info: any NSDraggingInfo) -> TrayStore.AddOutcome {
        let urls = PasteboardFileReader.fileURLs(from: info.draggingPasteboard)
        guard !urls.isEmpty else { return .nothingUsable }
        return store.add(urls)
    }
}
