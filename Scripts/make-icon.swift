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
/// The mark, read from the geometry the generator produced.
///
/// JSON rather than the Swift the app uses, because this is a standalone
/// `swift` file with no module to import. Both come from
/// `Resources/CueLogo.svg` by way of `Scripts/generate-logo.py`, so the icon
/// and the app cannot drift apart.
enum CueLogo {
    private static let document: [String: Any] = {
        let url = URL(fileURLWithPath: "Resources/CueLogo.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            FileHandle.standardError.write(Data("error: Resources/CueLogo.json is missing. Run ./Scripts/generate-logo.py\n".utf8))
            exit(1)
        }
        return object
    }()

    static let shapes: [[CGFloat]] = (document["shapes"] as? [[Double]] ?? []).map { $0.map { CGFloat($0) } }
    static let aspect: CGFloat = CGFloat(document["aspect"] as? Double ?? 1)

    /// Fitted into a rectangle, y flipped: the artwork is described with y
    /// increasing downward and AppKit draws with it increasing upward.
    static func draw(in rect: NSRect) {
        let scale = min(rect.width / aspect, rect.height)
        let size = NSSize(width: scale * aspect, height: scale)
        let origin = NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)

        for shape in shapes where shape.count >= 8 {
            func point(_ index: Int) -> NSPoint {
                NSPoint(
                    x: origin.x + shape[index] * size.width,
                    y: origin.y + (1 - shape[index + 1]) * size.height
                )
            }

            let path = NSBezierPath()
            path.move(to: point(0))
            var index = 2
            while index + 5 < shape.count {
                path.curve(to: point(index + 4), controlPoint1: point(index), controlPoint2: point(index + 2))
                index += 6
            }
            path.close()
            path.fill()
        }
    }
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

    // White on black, as the artwork is.
    NSColor.white.setFill()
    CueLogo.draw(in: plate.insetBy(dx: plate.width * 0.11, dy: plate.height * 0.11))

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
