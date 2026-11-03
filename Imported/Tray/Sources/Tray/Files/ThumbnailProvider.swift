import AppKit
import QuickLookThumbnailing

/// Pictures for tray items (§25).
///
/// Two tiers, on purpose. `NSWorkspace`'s icon is synchronous, always
/// available and instant, so an item is never blank for even one frame. The
/// Quick Look thumbnail — the actual page of the PDF, the actual photo —
/// arrives afterwards and replaces it. The user sees content immediately and a
/// better version shortly after, rather than a spinner.
///
/// Nothing here blocks the main thread, and nothing is written to disk: the
/// cache is a dictionary that dies with the process, matching the tray's own
/// session lifetime (§25, §40).
@Observable
final class ThumbnailProvider {
    /// Keyed by the item's resolved path, so two entries pointing at the same
    /// file share one image.
    private var cache: [String: NSImage] = [:]

    /// System icons, already flattened. Separate from the Quick Look cache so
    /// a preview arriving does not throw away the icon it replaced.
    private var icons: [String: NSImage] = [:]

    private let generator = QLThumbnailGenerator.shared

    /// Rendered larger than displayed so the image stays crisp on Retina and
    /// while the item scales under the pointer.
    private static let renderScale: CGFloat = 2

    /// The immediate answer: a cached Quick Look thumbnail if we have one,
    /// otherwise the system's file icon. Never `nil`, never blocking.
    func immediateImage(for item: TrayItem, size: CGFloat) -> NSImage {
        if let cached = cache[item.identity] { return cached }
        return systemIcon(for: item, size: size)
    }

    /// Asks Quick Look for a real preview. Returns `nil` when the file has no
    /// meaningful preview (most plain documents, folders), in which case the
    /// system icon already on screen is the right answer and stays.
    func previewImage(for item: TrayItem, size: CGSize) async -> NSImage? {
        if let cached = cache[item.identity] { return cached }
        guard item.isAvailable else { return nil }

        let request = QLThumbnailGenerator.Request(
            fileAt: item.url,
            size: size,
            scale: Self.renderScale,
            representationTypes: .thumbnail
        )
        request.iconMode = false

        // Quick Look does its own offloading; awaiting here does not occupy
        // the main thread, and a failure is an ordinary outcome rather than an
        // error worth surfacing (§80).
        guard let representation = try? await generator.generateBestRepresentation(for: request)
        else { return nil }

        let image = representation.nsImage
        cache[item.identity] = image
        return image
    }

    func forget(_ item: TrayItem) {
        cache[item.identity] = nil
        for key in icons.keys where key.hasPrefix("\(item.identity)@") {
            icons[key] = nil
        }
    }

    func removeAll() {
        cache.removeAll()
        icons.removeAll()
    }

    private func systemIcon(for item: TrayItem, size: CGFloat) -> NSImage {
        // Keyed by size too: the same file drawn larger needs a fresh
        // rasterisation, not the small one scaled up.
        let key = "\(item.identity)@\(Int(size))"
        if let cached = icons[key] { return cached }

        guard item.isAvailable else {
            return NSImage(
                systemSymbolName: "questionmark.square.dashed",
                accessibilityDescription: nil
            ) ?? NSImage()
        }

        let icon = Self.flattened(NSWorkspace.shared.icon(forFile: item.url.path), to: size)
        icons[key] = icon
        return icon
    }

    /// Draws an icon once into a plain bitmap.
    ///
    /// `NSWorkspace`'s icons carry dozens of lazily-resolved representations
    /// and report a 32pt size, so drawing one straight into the tray both
    /// re-resolves representations on every pass and upscales from the small
    /// one. Flattening it at the size it will actually be shown fixes the
    /// sharpness and takes the work out of the draw path.
    private static func flattened(_ image: NSImage, to side: CGFloat) -> NSImage {
        let size = NSSize(width: side, height: side)

        let result = NSImage(size: size)
        result.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        result.unlockFocus()
        return result
    }
}
