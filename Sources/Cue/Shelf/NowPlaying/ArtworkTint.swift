import CoreGraphics
import Foundation

/// A colour for the now-playing mark, taken from the cover and made to read
/// on the shelf.
///
/// Pure arithmetic over pixels, split into the three steps that can each be
/// wrong in their own way: sampling (the only part that touches Core
/// Graphics), picking the cover's colour, and making that colour legible
/// against whatever the shelf is painted. Kept off the main actor because the
/// first step reads a bitmap, and a hitch in the frame the wings grow on is
/// the one place anybody would see it.
///
/// What it is deliberately not is an average. The mean of most album covers
/// is a muddy brown — the colours cancel — so the cover's colour is the hue
/// with the most saturated, brightest pixels behind it, and covers that have
/// no such hue get no tint at all rather than a grey one.
nonisolated enum ArtworkTint {
    /// A colour as sRGB components, 0 to 1, gamma-encoded — the values a
    /// bitmap holds, before any linearising.
    struct RGB: Equatable, Sendable {
        var red: Double
        var green: Double
        var blue: Double

        static let black = RGB(red: 0, green: 0, blue: 0)
        static let white = RGB(red: 1, green: 1, blue: 1)

        /// Every component pulled back into 0...1.
        var clamped: RGB {
            RGB(red: unit(red), green: unit(green), blue: unit(blue))
        }

        var maximum: Double { max(red, green, blue) }
        var minimum: Double { min(red, green, blue) }

        /// How far from grey, in the components' own units.
        var chroma: Double { maximum - minimum }

        /// Brightness as a bitmap sees it: Rec. 601 luma on the encoded
        /// values. Not relative luminance, which calls a dark navy "black" —
        /// this is what decides which pixels are letterbox bars and paper
        /// borders, and a navy cover is neither.
        var luma: Double { 0.299 * red + 0.587 * green + 0.114 * blue }

        /// HSV saturation and value, for weighting.
        var saturation: Double { maximum > 0 ? chroma / maximum : 0 }
        var value: Double { maximum }

        /// The hue, 0 up to 1, red at 0. Meaningless — and returned as 0 — for
        /// a grey.
        var hue: Double {
            guard chroma > 0 else { return 0 }
            let degrees: Double
            if maximum == red {
                degrees = 60 * ((green - blue) / chroma).truncatingRemainder(dividingBy: 6)
            } else if maximum == green {
                degrees = 60 * ((blue - red) / chroma + 2)
            } else {
                degrees = 60 * ((red - green) / chroma + 4)
            }
            let turn = degrees / 360
            return turn < 0 ? turn + 1 : turn
        }
    }

    /// Hue, saturation and lightness — the space the legibility step moves in,
    /// because it can change how light a colour is while holding its hue
    /// exactly.
    struct HSL: Equatable, Sendable {
        var hue: Double
        var saturation: Double
        var lightness: Double

        init(hue: Double, saturation: Double, lightness: Double) {
            self.hue = hue
            self.saturation = saturation
            self.lightness = lightness
        }

        init(_ rgb: RGB) {
            let lightness = (rgb.maximum + rgb.minimum) / 2
            let denominator = 1 - abs(2 * lightness - 1)
            self.init(
                hue: rgb.hue,
                saturation: denominator > 0 ? rgb.chroma / denominator : 0,
                lightness: lightness
            )
        }

        var rgb: RGB {
            let chroma = (1 - abs(2 * lightness - 1)) * saturation
            let sector = hue * 6
            let x = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
            let m = lightness - chroma / 2
            let (r, g, b): (Double, Double, Double) = switch sector {
            case ..<1: (chroma, x, 0)
            case ..<2: (x, chroma, 0)
            case ..<3: (0, chroma, x)
            case ..<4: (0, x, chroma)
            case ..<5: (x, 0, chroma)
            default: (chroma, 0, x)
            }
            return RGB(red: r + m, green: g + m, blue: b + m).clamped
        }
    }

    // MARK: Tuning

    /// Pixels darker than this are letterbox bars or a black sleeve, and
    /// brighter ones are paper; neither is the cover's colour.
    static let lumaFloor = 0.04
    static let lumaCeiling = 0.96

    /// Below this a pixel is grey to the eye, whatever its hue says.
    static let pixelChromaFloor = 0.08

    /// Fewer surviving pixels than this share and the cover has no colour
    /// worth taking — a photograph in black and white with a coloured logo in
    /// a corner, say.
    static let survivorShare = 0.05

    /// A result this close to grey is not a tint, it is a dim white.
    static let resultChromaFloor = 0.12

    /// Twenty-four bins of fifteen degrees: fine enough to tell orange from
    /// red, coarse enough that one cover's reds land together.
    static let hueBins = 24

    /// How far apart, in bins, a second colour has to be: three bins is
    /// forty-five degrees — orange against red, not red against red.
    static let secondHueSeparation = 3

    /// How much of the first colour's weight a second has to carry to count:
    /// enough to be part of the cover, not a speck in a corner of it.
    static let secondHueShare = 0.15

    /// Neon reds and greens vibrate against black. Held just short of full.
    static let maximumSaturation = 0.85

    // MARK: Sampling

    /// The cover, shrunk to `side` × `side` sRGB pixels.
    ///
    /// Drawn into a bitmap of known layout rather than read from the image's
    /// own, which may be any depth, order or colour space. Shrinking is the
    /// point: a 544pt cover has three hundred thousand pixels, and the colour
    /// of the whole is just as visible in five hundred. Transparent pixels are
    /// left out — they are not part of the cover.
    static func samples(of image: CGImage, side: Int = 24) -> [RGB] {
        let side = max(1, side)
        let bytesPerRow = side * 4
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: side,
                  height: side,
                  bitsPerComponent: 8,
                  bytesPerRow: bytesPerRow,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return [] }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))

        guard let data = context.data else { return [] }
        let bytes = data.bindMemory(to: UInt8.self, capacity: side * bytesPerRow)

        var samples: [RGB] = []
        samples.reserveCapacity(side * side)
        for pixel in 0..<(side * side) {
            let base = pixel * 4
            let alpha = Double(bytes[base + 3]) / 255
            guard alpha >= 0.5 else { continue }
            // Premultiplied, so divided back out.
            samples.append(RGB(
                red: Double(bytes[base]) / 255 / alpha,
                green: Double(bytes[base + 1]) / 255 / alpha,
                blue: Double(bytes[base + 2]) / 255 / alpha
            ).clamped)
        }
        return samples
    }

    // MARK: Picking

    /// The cover's colour, or `nil` when it has none.
    ///
    /// Each pixel that is neither near-black, near-white nor near-grey votes
    /// for its hue with its saturation times its value, so a vivid pixel
    /// counts for more than a dull one and a bright one for more than a dim
    /// one. The winning hue is read together with its two neighbours, so a
    /// colour that happens to sit on a bin edge is not split in half, and the
    /// answer is the vote-weighted mean of the pixels behind it — a colour the
    /// cover actually contains, not a hue with an invented saturation.
    static func dominant(_ samples: [RGB]) -> RGB? {
        palette(samples, maximum: 1).first
    }

    /// The cover's colours, most present first: its own hue, then — when the
    /// cover has one — a second that is clearly a different colour rather
    /// than a shade of the first. Party mode paints with both; everything else
    /// uses only the first.
    ///
    /// The second hue has to sit `secondHueSeparation` bins away from the
    /// first and carry at least `secondHueShare` of its weight, so a red
    /// cover's darker reds do not come back as a "second" colour.
    static func palette(_ samples: [RGB], maximum: Int = 2) -> [RGB] {
        guard !samples.isEmpty, maximum > 0 else { return [] }

        var weights = [Double](repeating: 0, count: hueBins)
        var sums = [RGB](repeating: .black, count: hueBins)
        var survivors = 0

        for sample in samples {
            guard sample.luma >= lumaFloor,
                  sample.luma <= lumaCeiling,
                  sample.chroma >= pixelChromaFloor
            else { continue }

            survivors += 1
            let weight = sample.saturation * sample.value
            let bin = min(hueBins - 1, Int(sample.hue * Double(hueBins)))
            weights[bin] += weight
            sums[bin].red += sample.red * weight
            sums[bin].green += sample.green * weight
            sums[bin].blue += sample.blue * weight
        }

        guard Double(survivors) >= Double(samples.count) * survivorShare else { return [] }

        func neighbourhood(_ bin: Int) -> [Int] {
            [(bin + hueBins - 1) % hueBins, bin, (bin + 1) % hueBins]
        }

        func weight(around bin: Int) -> Double {
            neighbourhood(bin).reduce(0) { $0 + weights[$1] }
        }

        func colour(around bin: Int) -> RGB? {
            var total = 0.0
            var mean = RGB.black
            for neighbour in neighbourhood(bin) {
                total += weights[neighbour]
                mean.red += sums[neighbour].red
                mean.green += sums[neighbour].green
                mean.blue += sums[neighbour].blue
            }
            guard total > 0 else { return nil }
            let result = RGB(
                red: mean.red / total,
                green: mean.green / total,
                blue: mean.blue / total
            ).clamped
            return result.chroma >= resultChromaFloor ? result : nil
        }

        func distance(_ a: Int, _ b: Int) -> Int {
            let raw = abs(a - b)
            return min(raw, hueBins - raw)
        }

        let ranked = weights.indices.sorted { weight(around: $0) > weight(around: $1) }
        guard let first = ranked.first, let firstColour = colour(around: first) else { return [] }

        var colours = [firstColour]
        let floor = weight(around: first) * secondHueShare
        for bin in ranked.dropFirst() where colours.count < maximum {
            guard weight(around: bin) >= floor, weight(around: bin) > 0 else { break }
            guard distance(bin, first) >= secondHueSeparation,
                  let second = colour(around: bin)
            else { continue }
            colours.append(second)
        }
        return colours
    }

    // MARK: Legibility

    /// WCAG relative luminance: the components linearised, then weighted by
    /// how bright each primary looks.
    static func relativeLuminance(_ rgb: RGB) -> Double {
        func linear(_ component: Double) -> Double {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.red) + 0.7152 * linear(rgb.green) + 0.0722 * linear(rgb.blue)
    }

    /// WCAG contrast between two relative luminances, 1 to 21.
    static func contrast(_ first: Double, _ second: Double) -> Double {
        (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    /// `rgb`, with its hue kept and its lightness moved just far enough to
    /// reach `minimumContrast` against a ground of `groundLuminance` (WCAG
    /// relative luminance).
    ///
    /// Lighter on a dark ground and darker on a light one — whichever way
    /// there is more contrast to be had. As little as it takes, so a cover
    /// that is already legible keeps its own colour. Saturation is capped on
    /// the way through. 4.5 rather than the 3 graphics are allowed, because
    /// the mark is twelve points tall with hairline outer shapes and dims to
    /// 42% when paused.
    static func legible(
        _ rgb: RGB,
        against groundLuminance: Double,
        minimumContrast: Double = 4.5
    ) -> RGB {
        var hsl = HSL(rgb.clamped)
        hsl.saturation = min(hsl.saturation, maximumSaturation)

        func colour(at lightness: Double) -> RGB {
            HSL(hue: hsl.hue, saturation: hsl.saturation, lightness: lightness).rgb
        }

        func reads(_ lightness: Double) -> Bool {
            contrast(relativeLuminance(colour(at: lightness)), groundLuminance) >= minimumContrast
        }

        let start = min(1, max(0, hsl.lightness))
        guard !reads(start) else { return colour(at: start) }

        let lightens = contrast(1, groundLuminance) >= contrast(0, groundLuminance)
        // Luminance only ever rises with lightness at a fixed hue and
        // saturation, so the boundary can be found by halving. `fails` is
        // always on the unreadable side of it and `passes` on the readable
        // side, and the answer is the passing end: as close to the cover's
        // own lightness as still reads.
        var fails = start
        var passes: Double = lightens ? 1 : 0
        guard reads(passes) else { return colour(at: passes) }

        for _ in 0..<24 {
            let middle = (fails + passes) / 2
            if reads(middle) { passes = middle } else { fails = middle }
        }
        return colour(at: passes)
    }

    // MARK: All three

    /// The tint for a cover on a ground, or `nil` when the cover has no colour
    /// to give. Runs off the main actor: the bitmap work is small, but it
    /// happens in the same moment the wings start to grow.
    @concurrent
    static func tint(for image: CGImage, groundLuminance: Double) async -> RGB? {
        dominant(samples(of: image)).map { legible($0, against: groundLuminance) }
    }

    /// A second colour for a cover that has only one: the same colour turned
    /// a little round the wheel and moved in lightness, so a gradient between
    /// the two moves visibly without leaving the cover's palette.
    static func companion(of rgb: RGB, against groundLuminance: Double) -> RGB {
        var hsl = HSL(rgb.clamped)
        hsl.hue = (hsl.hue + 0.08).truncatingRemainder(dividingBy: 1)
        hsl.lightness = hsl.lightness > 0.6 ? hsl.lightness - 0.22 : hsl.lightness + 0.22
        return legible(hsl.rgb, against: groundLuminance, minimumContrast: 3)
    }

    /// Both of the cover's colours, made legible, for party mode. A cover with
    /// one colour gets it back alone; the caller derives a second from it.
    @concurrent
    static func tints(for image: CGImage, groundLuminance: Double) async -> [RGB] {
        palette(samples(of: image)).map { legible($0, against: groundLuminance) }
    }
}

nonisolated private func unit(_ value: Double) -> Double {
    value.isFinite ? min(1, max(0, value)) : 0
}
