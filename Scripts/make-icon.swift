#!/usr/bin/env swift

// Draws Cue's app icon and writes Cue.icns.
//
// Generated rather than checked in as a binary, so the mark is readable,
// reviewable and editable as code — and so a fresh clone with the Command Line
// Tools produces exactly the same asset with no design app in the loop.
//
// The mark is a cue point: a marker bar, a gap, and a play triangle. In an
// editor a cue is the marked place a track starts from, which is precisely what
// this app does — you mark the thing you want and it starts. It beats a generic
// note or disc because it means something specific here, and it survives being
// sixteen points wide, which most clever marks do not.

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

    // Near-black rather than black: the same ground YouTube Music uses, and a
    // truly black plate disappears into a dark Dock.
    NSGradient(colors: [
        NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.11, alpha: 1),
        NSColor(calibratedRed: 0.03, green: 0.03, blue: 0.035, alpha: 1),
    ])?.draw(in: plateShape, angle: -90)

    plateShape.addClip()

    let accent = NSColor(calibratedRed: 1.0, green: 0.13, blue: 0.24, alpha: 1)

    // The mark, centred as a group rather than individually: the triangle's
    // optical centre sits behind its point, so centring the two shapes
    // separately leaves the pair looking pushed to the left.
    //
    // The marker is deliberately unlike the triangle in every way available —
    // thin where it is wide, taller than it, and a different colour. A bar of
    // similar weight beside a play triangle is the universal "skip forward"
    // glyph, which is what the first draft of this drew.
    let triangleHeight = 300 * unit
    let markerHeight = 470 * unit
    let markerWidth = 34 * unit
    let gap = 62 * unit
    let triangleWidth = 250 * unit
    let markWidth = markerWidth + gap + triangleWidth

    let originX = size / 2 - markWidth / 2
    let centreY = size / 2

    // The playhead. White rather than the accent, so the eye reads a marker
    // against a coloured triangle rather than two halves of one control.
    NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
    NSBezierPath(
        roundedRect: NSRect(
            x: originX,
            y: centreY - markerHeight / 2,
            width: markerWidth,
            height: markerHeight
        ),
        xRadius: markerWidth / 2,
        yRadius: markerWidth / 2
    ).fill()

    accent.setFill()
    accent.setStroke()

    // The triangle is stroked as well as filled, which is what rounds its
    // corners. Sharp points at sixteen pixels alias into grey mush.
    let triangleLeft = originX + markerWidth + gap
    let corner = 30 * unit

    let triangle = NSBezierPath()
    triangle.move(to: NSPoint(x: triangleLeft, y: centreY - triangleHeight / 2 + corner / 2))
    triangle.line(to: NSPoint(x: triangleLeft, y: centreY + triangleHeight / 2 - corner / 2))
    triangle.line(to: NSPoint(x: triangleLeft + triangleWidth - corner / 2, y: centreY))
    triangle.close()
    triangle.lineJoinStyle = .round
    triangle.lineWidth = corner
    triangle.fill()
    triangle.stroke()

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
