import ImageIO
import SwiftUI

/// Mia's exercise picture, moving: the frames of a GIF or APNG (or one still image), read once per file.
struct ExercisePicture: View {
    let url: URL?

    @State private var frames: Frames?

    struct Frames: Equatable {
        var images: [CGImage]
        var delays: [Double]
        var total: Double { delays.reduce(0, +) }
        static func == (a: Frames, b: Frames) -> Bool { a.images.count == b.images.count && a.delays == b.delays }
    }

    var body: some View {
        TimelineView(.animation(paused: (frames?.images.count ?? 0) < 2)) { context in
            if let frames, let image = frame(frames, at: context.date) {
                Image(decorative: image, scale: 1).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "figure.strengthtraining.traditional").resizable().aspectRatio(contentMode: .fit).opacity(0.5)
            }
        }
        .task(id: url) { frames = await Self.load(url) }
    }

    private func frame(_ frames: Frames, at date: Date) -> CGImage? {
        guard frames.images.count > 1, frames.total > 0 else { return frames.images.first }
        var t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: frames.total)
        for (index, delay) in frames.delays.enumerated() {
            if t < delay { return frames.images[index] }
            t -= delay
        }
        return frames.images.last
    }

    /// Up to 300 frames at 240 px; nil when the file can't be read.
    static func load(_ url: URL?) async -> Frames? {
        guard let url else { return nil }
        return await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let count = min(CGImageSourceGetCount(source), 300)
            let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 240,
                           kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary
            var images: [CGImage] = [], delays: [Double] = []
            for index in 0..<count {
                guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options) else { continue }
                images.append(image)
                let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
                let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
                let png = props?[kCGImagePropertyPNGDictionary] as? [CFString: Any]
                let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] ?? gif?[kCGImagePropertyGIFDelayTime]
                             ?? png?[kCGImagePropertyAPNGUnclampedDelayTime] ?? png?[kCGImagePropertyAPNGDelayTime]) as? Double
                delays.append(max(0.02, delay ?? 0.1))
            }
            return images.isEmpty ? nil : Frames(images: images, delays: delays)
        }.value
    }
}
