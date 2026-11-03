#!/usr/bin/env swift

// Draws Tray's app icon and writes Tray.icns (§56).
//
// Generated rather than checked in as a binary, so the icon is readable,
// reviewable and editable as code — and so a fresh clone with Command Line
// Tools produces exactly the same asset with no design app in the loop.
//
// The mark is a shallow open tray: an outline with a shelf floor sitting low
// inside it. Not a folder — a folder means "files live here", and the whole
// point is that they are passing through.

import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.icns>\n".utf8))
    exit(1)
}

let output = URL(fileURLWithPath: arguments[1])
let iconset = FileManager.default.temporaryDirectory
    .appendingPathComponent("Tray-\(UUID().uuidString).iconset")

try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

/// A rounded rectangle whose four corners may each have a different radius.
///
/// Uniform corners read as geometry. Uneven ones read as a body.
func roundedPath(
    _ rect: NSRect,
    topLeft: CGFloat,
    topRight: CGFloat,
    bottomRight: CGFloat,
    bottomLeft: CGFloat
) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: rect.minX + bottomLeft, y: rect.minY))
    path.appendArc(
        from: NSPoint(x: rect.maxX, y: rect.minY),
        to: NSPoint(x: rect.maxX, y: rect.maxY),
        radius: bottomRight
    )
    path.appendArc(
        from: NSPoint(x: rect.maxX, y: rect.maxY),
        to: NSPoint(x: rect.minX, y: rect.maxY),
        radius: topRight
    )
    path.appendArc(
        from: NSPoint(x: rect.minX, y: rect.maxY),
        to: NSPoint(x: rect.minX, y: rect.minY),
        radius: topLeft
    )
    path.appendArc(
        from: NSPoint(x: rect.minX, y: rect.minY),
        to: NSPoint(x: rect.maxX, y: rect.minY),
        radius: bottomLeft
    )
    path.close()
    return path
}

/// A capsule, rotated about its own centre.
func eyePath(center: NSPoint, width: CGFloat, height: CGFloat, degrees: CGFloat) -> NSBezierPath {
    let path = NSBezierPath(
        roundedRect: NSRect(x: -width / 2, y: -height / 2, width: width, height: height),
        xRadius: width / 2,
        yRadius: width / 2
    )
    var transform = AffineTransform.identity
    transform.translate(x: center.x, y: center.y)
    transform.rotate(byDegrees: degrees)
    path.transform(using: transform)
    return path
}

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { fatalError("could not allocate a bitmap") }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let unit = size / 1024

    // macOS icons sit inside the canvas rather than filling it.
    let plate = NSRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    let radius = 185 * unit
    let plateShape = NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius)

    // Graphite, matching the tray's own surface, lit from above.
    NSGradient(colors: [
        NSColor(calibratedRed: 0.20, green: 0.21, blue: 0.24, alpha: 1),
        NSColor(calibratedRed: 0.075, green: 0.080, blue: 0.093, alpha: 1),
    ])?.draw(in: plateShape, angle: -90)

    // The highlight that reads as a bevel catching light along the top edge.
    plateShape.addClip()
    let highlight = NSBezierPath(
        roundedRect: plate.insetBy(dx: 3 * unit, dy: 3 * unit),
        xRadius: radius,
        yRadius: radius
    )
    highlight.lineWidth = 6 * unit
    NSColor(calibratedWhite: 1, alpha: 0.13).setStroke()
    highlight.stroke()

    NSGraphicsContext.current?.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // The mark: something living in the tray, peering out.
    //
    // Two shapes and nothing else. A blob rising from the bottom edge — so it
    // reads as sitting *in* something rather than floating — and two eyes. The
    // asymmetry is the whole trick: the corner radii differ on every corner and
    // the eyes are not a matched pair, which is the difference between a
    // creature and a rounded rectangle with dots on it.
    plateShape.addClip()

    // Sized past the plate on the left and bottom so the clip trims it to the
    // plate's own edge; the one huge corner is what lets the plate show through
    // and turns a filled square into a shape with a head.
    let body = NSRect(x: 130 * unit, y: -60 * unit, width: 820 * unit, height: 840 * unit)
    let creature = roundedPath(
        body,
        topLeft: 230 * unit,
        topRight: 470 * unit,
        bottomRight: 210 * unit,
        bottomLeft: 230 * unit
    )
    // A gentle gradient rather than flat white, so the body reads as a surface
    // catching light rather than as a hole cut in the plate.
    NSGradient(colors: [
        NSColor(calibratedWhite: 0.99, alpha: 1),
        NSColor(calibratedWhite: 0.85, alpha: 1),
    ])?.draw(in: creature, angle: -68)

    // Eyes: capsules, leaning, and deliberately mismatched.
    let dark = NSColor(calibratedWhite: 0.09, alpha: 1)
    dark.setFill()
    eyePath(center: NSPoint(x: 466 * unit, y: 418 * unit),
            width: 102 * unit, height: 214 * unit, degrees: -16).fill()
    eyePath(center: NSPoint(x: 672 * unit, y: 468 * unit),
            width: 86 * unit, height: 176 * unit, degrees: -16).fill()

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
