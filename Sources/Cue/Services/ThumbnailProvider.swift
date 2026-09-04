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

    /// Bumped whenever an image lands.
    ///
    /// Views read it so that a cover arriving redraws the tile. Reading through
    /// `image(for:)` alone was not enough — covers only appeared once something
    /// else forced a redraw, such as changing page — and an explicit signal is
    /// more honest than hoping a lookup through a method on a shared cache gets
    /// tracked.
    private(set) var version = 0

    /// How many fetches have failed, so a grid of placeholders can be told
    /// apart from a grid of items that never had artwork to begin with.
    private(set) var failures = 0

    private var images: [URL: NSImage] = [:]
    /// Requests in flight, so that nine tiles pointing at one playlist's
    /// artwork make one request rather than nine.
    private var loading: Set<URL> = []
    private var order: [URL] = []

    /// Waiting their turn.
    ///
    /// Warming the whole pool so that Shuffle is instant meant asking for
    /// something like a hundred and fifty covers at once, and the nine actually
    /// on screen queued behind all of them. A small number in flight, with the
    /// visible ones jumping the queue, is faster in the only way anyone can
    /// see.
    private var queue: [URL] = []

    /// Enough to keep the connection busy, few enough that nine visible covers
    /// are never waiting behind a page nobody has turned to.
    private static let maximumInFlight = 5

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
    ///
    /// `soon` marks the covers currently on screen, which go to the front of
    /// the queue. Everything else is warming for a page that has not been
    /// turned to yet and can wait.
    func prefetch(_ url: URL?, soon: Bool = false) {
        guard let url, images[url] == nil, !loading.contains(url) else { return }

        if let existing = queue.firstIndex(of: url) {
            guard soon else { return }
            queue.remove(at: existing)
        }

        soon ? queue.insert(url, at: 0) : queue.append(url)
        pump()
    }

    /// Starts as many waiting requests as the limit allows.
    private func pump() {
        while loading.count < Self.maximumInFlight, !queue.isEmpty {
            let url = queue.removeFirst()
            guard images[url] == nil, !loading.contains(url) else { continue }

            loading.insert(url)

            Task { [weak self] in
                guard let self else { return }
                defer {
                    self.loading.remove(url)
                    self.pump()
                }

                do {
                    let (data, response) = try await session.data(from: url)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200..<300).contains(status) else {
                        self.failures &+= 1
                        logger.notice("Thumbnail refused: HTTP \(status, privacy: .public)")
                        return
                    }
                    guard let image = NSImage(data: data) else {
                        self.failures &+= 1
                        logger.notice("Thumbnail undecodable: \(data.count, privacy: .public) bytes")
                        return
                    }
                    self.store(image, for: url)
                } catch {
                    self.failures &+= 1
                    logger.notice("Thumbnail failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func store(_ image: NSImage, for url: URL) {
        images[url] = image
        order.append(url)
        version &+= 1

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
