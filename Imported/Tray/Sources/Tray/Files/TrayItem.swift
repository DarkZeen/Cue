import Foundation

/// One thing sitting on the shelf.
///
/// The tray never owns the bytes. It owns a *reference* — dropping a file in
/// does not move, copy, or modify it (§3, §38). Everything here is derived
/// from the URL and cheap to recompute.
///
/// Thumbnails are deliberately not stored here. The spec is explicit that
/// image generation is not the model's job (§41); `ThumbnailProvider` owns it
/// and is keyed by the item's identity.
struct TrayItem: Identifiable, Equatable, Sendable {
    enum Kind: Sendable {
        case file
        case folder
    }

    /// Whether the referenced object is still where we left it.
    ///
    /// Refreshed at moments the user can perceive — when the tray opens, after
    /// a drop — rather than polled, so an idle tray costs nothing (§26).
    enum Availability: Sendable {
        case present
        case missing
    }

    let id: UUID
    let url: URL

    /// The name as Finder would write it — localised, and with the extension
    /// hidden if that is what the user has asked for. `lastPathComponent`
    /// would show "QuickTime Player.app" where Finder shows "QuickTime
    /// Player", and the difference is most of a narrow tile's width.
    let filename: String

    let kind: Kind
    var availability: Availability

    /// The value two URLs are compared by when deciding whether a drop is a
    /// duplicate. Symlinks and `..` components are resolved so that
    /// `/tmp/x` and `/private/tmp/x` are recognised as one file, while
    /// `~/Desktop/report.pdf` and `~/Documents/report.pdf` stay distinct (§52).
    let identity: String

    init(url: URL, id: UUID = UUID()) {
        let standardized = url.standardizedFileURL.resolvingSymlinksInPath()

        self.id = id
        self.url = url
        self.identity = standardized.path
        let displayName = FileManager.default.displayName(atPath: standardized.path)
        // `displayName` falls back to the last path component for something
        // that is not there, which is exactly what we want to show anyway.
        self.filename = displayName.isEmpty ? url.lastPathComponent : displayName

        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        // A package (.app, .rtfd) is a directory on disk but a single object to
        // the user, so it reads as a file here.
        let isDirectory = (values?.isDirectory ?? false) && !(values?.isPackage ?? false)
        self.kind = isDirectory ? .folder : .file

        self.availability = FileManager.default.fileExists(atPath: standardized.path)
            ? .present
            : .missing
    }

    var isAvailable: Bool { availability == .present }

    /// What VoiceOver reads for this item (§35).
    var accessibilityLabel: String {
        switch (kind, availability) {
        case (.folder, .present): "\(filename), folder"
        case (.file, .present): filename
        case (_, .missing): "\(filename), file unavailable"
        }
    }
}
