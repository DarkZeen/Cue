import AppKit
import Foundation
import Observation

/// Artwork for tiles and rows, fetched once and kept.
///
/// `AsyncImage` would be fewer lines and would refetch every one of the nine
/// tiles every time the panel opened — which, for a panel meant to be opened
/// forty times a day, is forty times nine requests for pictures that have not
/// changed. This keeps them in memory for the life of the process and lets the
/// URL cache handle the rest.
@Observable
final class ThumbnailProvider {
    /// Nine tiles, twenty results, and the last few of each. Past a couple of
    /// hundred thumbnails the memory is real and the hit rate is not.
    private static let capacity = 240

    private var images: [URL: NSImage] = [:]
    /// Requests in flight, so that nine tiles pointing at one playlist's
    /// artwork make one request rather than nine.
    private var loading: Set<URL> = []
    private var order: [URL] = []

    private let session: URLSession
    private let logger = Diagnostics.logger("thumbnails")

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// The image if it is already here. Views call this while drawing, so it
    /// never waits and never throws.
    func image(for url: URL?) -> NSImage? {
        guard let url else { return nil }
        return images[url]
    }

    /// Asks for an image to be there next time. Safe to call on every draw.
    func prefetch(_ url: URL?) {
        guard let url, images[url] == nil, !loading.contains(url) else { return }

        loading.insert(url)

        Task { [weak self] in
            guard let self else { return }
            defer { self.loading.remove(url) }

            do {
                let (data, response) = try await session.data(from: url)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(status), let image = NSImage(data: data) else { return }
                self.store(image, for: url)
            } catch {
                // A missing thumbnail is a tile with a symbol on it, which is
                // a fine tile. Nothing here is worth interrupting anyone over.
                logger.debug("Thumbnail failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func store(_ image: NSImage, for url: URL) {
        images[url] = image
        order.append(url)

        // Oldest-first eviction rather than least-recently-used: the access
        // pattern here is "the same nine tiles, then whatever was just
        // searched for", and insertion order tracks that closely enough that
        // the bookkeeping for true LRU would not pay for itself.
        while order.count > Self.capacity {
            let evicted = order.removeFirst()
            if !order.contains(evicted) { images[evicted] = nil }
        }
    }
}
