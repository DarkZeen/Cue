import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.icns>\n".utf8))
    exit(1)
}

let output = URL(fileURLWithPath: arguments[1])
let iconset = FileManager.default.temporaryDirectory
    .appendingPathComponent("Cue-\(UUID().uuidString).iconset")

try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

/// The envelope of the waveform: nine lenses, symmetric, tallest in the middle.
///
/// Shared with the app, which draws the same shape live and lets it move to the
/// music. Keeping the geometry in one description means the thing in the Dock
/// and the thing in the corner of the screen are one mark rather than two
/// drawings that resemble each other.
enum CueWaveform {
    /// How many lenses to draw at a given size.
    ///
    /// Nine is the mark. Nine is also unreadable at sixteen points, where the
    /// gaps fall below a pixel and the whole thing mushes into a white blob —
    /// so the small rungs draw a simplified version of the same idea rather
    /// than a shrunk version of the same drawing. This is what an icon family
    /// is for.
    static func count(for size: CGFloat) -> Int {
        switch size {
        case 96...: 9
        case 40...: 5
        default: 3
        }
    }

    /// Relative height of each lens, 0 to 1.
    ///
    /// A sine, but not a pure one: raised to a power so the outermost pair stay
    /// visible rather than tapering to nothing, and the middle reads as a
    /// plateau rather than a single spike.
    static func envelope(_ index: Int, count: Int) -> CGFloat {
        guard count > 1 else { return 1 }
        let position = CGFloat(index) / CGFloat(count - 1)
        // Inset from the ends of the half-cycle, so index 0 is a short lens
        // rather than a zero-height one.
        let phase = 0.085 + 0.83 * position
        return pow(sin(phase * .pi), 0.9)
    }

    /// How wide a lens of a given height should be.
    ///
    /// Proportional rather than constant: a fixed width would make the short
    /// outer lenses read as fat pills beside slender inner ones. Bolder when
    /// there are fewer of them, so the simplified mark carries the same weight
    /// rather than looking like a thin remnant of the full one.
    static func width(forHeight height: CGFloat, count: Int) -> CGFloat {
        let ratio: CGFloat = count >= 9 ? 0.105 : (count >= 5 ? 0.15 : 0.22)
        return max(height * ratio, 1.5)
    }
}

/// One lens: a vesica with pointed ends, drawn as two mirrored curves.
func lensPath(centre: NSPoint, width: CGFloat, height: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let top = NSPoint(x: centre.x, y: centre.y + height / 2)
    let bottom = NSPoint(x: centre.x, y: centre.y - height / 2)
    // Control points pushed out sideways and a quarter of the way along, which
    // is what gives the shape its taper instead of an ellipse's blunt ends.
    //
    // A cubic with both controls at the same offset reaches only three quarters
    // of it, so the reach is divided back out — without that the lens comes out
    // at twice its intended width and nine of them merge into one blob.
    let reach = (width / 2) / 0.75
    let lift = height / 4

    path.move(to: top)
    path.curve(
        to: bottom,
        controlPoint1: NSPoint(x: centre.x + reach, y: centre.y + lift),
        controlPoint2: NSPoint(x: centre.x + reach, y: centre.y - lift)
    )
    path.curve(
        to: top,
        controlPoint1: NSPoint(x: centre.x - reach, y: centre.y - lift),
        controlPoint2: NSPoint(x: centre.x - reach, y: centre.y + lift)
    )
    path.close()
    return path
}

/// Everything below is expressed against a 1024-point canvas and scaled, so the
/// numbers can be reasoned about at the size the icon was designed at.
func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!

    let unit = size / 1024

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // The plate. 22.5% of the side is the corner proportion Apple's own icons
    // use, and being wrong about it is instantly visible next to them.
    let inset = 92 * unit
    let plate = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let plateShape = NSBezierPath(
        roundedRect: plate,
        xRadius: plate.width * 0.225,
        yRadius: plate.width * 0.225
    )

    // Black, as asked, with just enough gradient to stop it reading as a hole
    // cut in the Dock.
    NSGradient(colors: [
        NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.08, alpha: 1),
        NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.0, alpha: 1),
    ])?.draw(in: plateShape, angle: -90)

    plateShape.addClip()

    let count = CueWaveform.count(for: size)
    let span = 640 * unit
    let spacing = span / CGFloat(count - 1)
    // Short of the plate's edges. A mark that reaches them reads as cropped,
    // and at small sizes the tips would touch the corner radius.
    let tallest = 610 * unit
    let centreY = size / 2
    let firstX = size / 2 - span / 2

    for index in 0..<count {
        let envelope = CueWaveform.envelope(index, count: count)
        let height = tallest * envelope
        let width = CueWaveform.width(forHeight: height, count: count)
        let x = firstX + spacing * CGFloat(index)

        // Faintly cooler at the edges, so nine white shapes have some depth
        // rather than reading as a flat stencil.
        let brightness = 0.88 + 0.12 * envelope
        NSColor(calibratedWhite: brightness, alpha: 1).setFill()
        lensPath(centre: NSPoint(x: x, y: centreY), width: width, height: height).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// The sizes iconutil expects, at 1× and 2×.
let variants: [(name: String, size: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    let rep = drawIcon(size: variant.size)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("could not encode \(variant.name)\n".utf8))
        exit(1)
    }
    try data.write(to: iconset.appendingPathComponent("\(variant.name).png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()

try? FileManager.default.removeItem(at: iconset)

guard iconutil.terminationStatus == 0 else { exit(iconutil.terminationStatus) }
print("icon → \(output.path)")
