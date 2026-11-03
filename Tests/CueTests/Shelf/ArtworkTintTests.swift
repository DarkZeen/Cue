import CoreGraphics
import Testing

@testable import Cue

/// The now-playing mark's colour: taken from the cover, made to read on the
/// shelf, and left white when the cover has no colour to give.
@MainActor
struct ArtworkTintTests {
    private typealias RGB = ArtworkTint.RGB

    /// A cover drawn in the test: bands of colour from the top down, each a
    /// share of the height.
    private func cover(_ bands: [(RGB, Double)], side: Int = 96) -> CGImage {
        let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        var top = CGFloat(side)
        for (colour, share) in bands {
            let height = CGFloat(side) * share
            context.setFillColor(red: colour.red, green: colour.green, blue: colour.blue, alpha: 1)
            context.fill(CGRect(x: 0, y: top - height, width: CGFloat(side), height: height))
            top -= height
        }
        return context.makeImage()!
    }

    private func tint(of image: CGImage) -> RGB? {
        ArtworkTint.dominant(ArtworkTint.samples(of: image))
    }

    private func contrast(_ rgb: RGB, against ground: Double) -> Double {
        ArtworkTint.contrast(ArtworkTint.relativeLuminance(rgb), ground)
    }

    /// Hue distance in turns, the short way round.
    private func hueDistance(_ a: RGB, _ b: RGB) -> Double {
        let difference = abs(a.hue - b.hue)
        return min(difference, 1 - difference)
    }

    private let navy = RGB(red: 0.06, green: 0.09, blue: 0.32)
    private let orange = RGB(red: 0.92, green: 0.46, blue: 0.10)

    // MARK: - Picking

    @Test func `a black and white cover has no tint`() {
        let greys = cover([
            (RGB(red: 0.1, green: 0.1, blue: 0.1), 0.25),
            (RGB(red: 0.4, green: 0.4, blue: 0.4), 0.25),
            (RGB(red: 0.7, green: 0.7, blue: 0.7), 0.25),
            (RGB(red: 0.9, green: 0.9, blue: 0.9), 0.25),
        ])

        #expect(tint(of: greys) == nil)
    }

    @Test func `a coloured logo in a corner is not enough to tint by`() {
        // Under one pixel in twenty: the cover is grey with a fleck of red.
        let mostlyGrey = cover([
            (RGB(red: 0.9, green: 0.1, blue: 0.1), 0.03),
            (RGB(red: 0.5, green: 0.5, blue: 0.5), 0.97),
        ])

        #expect(tint(of: mostlyGrey) == nil)
    }

    @Test func `letterbox bars do not drag the tint toward black`() throws {
        // A video frame: black bars top and bottom, the picture between.
        let framed = cover([(.black, 0.3), (orange, 0.4), (.black, 0.3)])
        let unframed = cover([(orange, 1)])

        let withBars = try #require(tint(of: framed))
        let without = try #require(tint(of: unframed))

        #expect(abs(withBars.red - without.red) < 0.03)
        #expect(abs(withBars.green - without.green) < 0.03)
        #expect(abs(withBars.blue - without.blue) < 0.03)
        #expect(withBars.luma > 0.4)
    }

    @Test func `the tint is a colour the cover has, not an average of it`() throws {
        // Half blue, half a little green: the average would be a teal the
        // cover does not contain.
        let blue = RGB(red: 0.1, green: 0.3, blue: 0.9)
        let twoTone = cover([(blue, 0.7), (RGB(red: 0.2, green: 0.6, blue: 0.2), 0.3)])

        let picked = try #require(tint(of: twoTone))

        #expect(hueDistance(picked, blue) < 0.02)
    }

    // MARK: - Legibility

    @Test func `a dark navy cover is lifted until it reads on black`() throws {
        let picked = try #require(tint(of: cover([(navy, 1)])))
        // The navy itself does not read on the island's black…
        #expect(contrast(picked, against: 0) < 4.5)

        let legible = ArtworkTint.legible(picked, against: 0)

        // …and the lifted one does.
        #expect(contrast(legible, against: 0) >= 4.5)
        #expect(hueDistance(legible, picked) < 0.005)
    }

    @Test func `the tint keeps the cover's hue`() {
        let colours = [
            navy,
            orange,
            RGB(red: 0.55, green: 0.08, blue: 0.20),
            RGB(red: 0.10, green: 0.45, blue: 0.20),
        ]

        for colour in colours {
            let legible = ArtworkTint.legible(colour, against: 0)
            #expect(hueDistance(legible, colour) < 0.005)
        }
    }

    @Test func `on the light surface the tint darkens instead`() {
        let ground = TrayPalette(appearance: .light).groundLuminance
        let pale = RGB(red: 0.95, green: 0.85, blue: 0.30)

        let legible = ArtworkTint.legible(pale, against: ground)

        #expect(ArtworkTint.relativeLuminance(legible) < ArtworkTint.relativeLuminance(pale))
        #expect(contrast(legible, against: ground) >= 4.5)
        #expect(hueDistance(legible, pale) < 0.005)
    }

    @Test func `a cover that already reads keeps its own colour`() {
        // As little as it takes, and nothing is as little as it takes. Under
        // the saturation cap, so that does not move it either.
        let bright = RGB(red: 0.85, green: 0.60, blue: 0.30)
        #expect(ArtworkTint.HSL(bright).saturation < ArtworkTint.maximumSaturation)

        let legible = ArtworkTint.legible(bright, against: 0)

        #expect(abs(legible.red - bright.red) < 0.01)
        #expect(abs(legible.green - bright.green) < 0.01)
        #expect(abs(legible.blue - bright.blue) < 0.01)
    }

    @Test func `the result clamps`() {
        let wild = RGB(red: 1.4, green: -0.2, blue: 0.5)
        let neon = RGB(red: 0, green: 1, blue: 0)

        for colour in [wild, neon] {
            for ground in [0, TrayPalette(appearance: .graphite).groundLuminance, 0.85] {
                let legible = ArtworkTint.legible(colour, against: ground)
                for component in [legible.red, legible.green, legible.blue] {
                    #expect((0...1).contains(component))
                }
                #expect(ArtworkTint.HSL(legible).saturation <= ArtworkTint.maximumSaturation + 0.001)
            }
        }
    }

    // MARK: - The surfaces

    @Test func `the surfaces run from black to light`() {
        let black = TrayPalette(appearance: .black).groundLuminance
        let graphite = TrayPalette(appearance: .graphite).groundLuminance
        let light = TrayPalette(appearance: .light).groundLuminance

        #expect(black == 0)
        #expect(graphite > 0 && graphite < 0.01)
        #expect(light > 0.8 && light < 0.9)
    }

    // MARK: - Two colours, for party mode

    private func palette(of image: CGImage) -> [RGB] {
        ArtworkTint.palette(ArtworkTint.samples(of: image))
    }

    @Test func `a two-colour cover gives both colours, the larger first`() {
        let orange = RGB(red: 0.95, green: 0.55, blue: 0.15)
        let blue = RGB(red: 0.15, green: 0.30, blue: 0.85)
        let colours = palette(of: cover([(orange, 0.65), (blue, 0.35)]))

        #expect(colours.count == 2)
        #expect(hueDistance(colours[0], orange) < 0.05)
        #expect(hueDistance(colours[1], blue) < 0.05)
    }

    @Test func `shades of one colour are one colour`() {
        let red = RGB(red: 0.85, green: 0.15, blue: 0.12)
        let darkRed = RGB(red: 0.45, green: 0.06, blue: 0.05)
        let colours = palette(of: cover([(red, 0.5), (darkRed, 0.5)]))

        #expect(colours.count == 1)
    }

    @Test func `a speck of a second colour is not a second colour`() {
        let green = RGB(red: 0.2, green: 0.75, blue: 0.3)
        let pink = RGB(red: 0.95, green: 0.3, blue: 0.7)
        let colours = palette(of: cover([(green, 0.97), (pink, 0.03)]))

        #expect(colours.count == 1)
    }

    @Test func `the first of the palette is the dominant colour`() {
        let orange = RGB(red: 0.95, green: 0.55, blue: 0.15)
        let blue = RGB(red: 0.15, green: 0.30, blue: 0.85)
        let image = cover([(blue, 0.3), (orange, 0.7)])

        #expect(palette(of: image).first == tint(of: image))
    }
}
