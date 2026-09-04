#!/usr/bin/env swift

// Draws Cue's app icon and writes Cue.icns.
//
// Generated rather than checked in as a binary, so the icon is readable,
// reviewable and editable as code — and so a fresh clone with the Command Line
// Tools produces exactly the same asset with no design app in the loop.
//
// The mark is the app: a three-by-three grid with the middle cell playing.
// Eight dots and a triangle. It reads as a speed dial at 512 points and as a
// dial with something at its centre at 16, which is the only size that is
// genuinely hard.

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
/// numbers can be reasoned about at the size the icon was actually designed at.
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

    // The plate. macOS icons are a rounded square with a squircle-ish radius;
    // 22.5% of the side is the proportion Apple's own icons use, and being
    // wrong about it is instantly visible next to them in the Dock.
    let inset = 92 * unit
    let plate = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let plateShape = NSBezierPath(
        roundedRect: plate,
        xRadius: plate.width * 0.225,
        yRadius: plate.width * 0.225
    )

    // Warm dark rather than black: a black plate disappears into a dark Dock,
    // and the grid needs something to sit on.
    NSGradient(colors: [
        NSColor(calibratedRed: 0.16, green: 0.09, blue: 0.12, alpha: 1),
        NSColor(calibratedRed: 0.07, green: 0.05, blue: 0.07, alpha: 1),
    ])?.draw(in: plateShape, angle: -90)

    plateShape.addClip()

    // The grid. Three by three, generously spaced — a tight grid reads as
    // texture, and this one has to read as *positions*.
    let dotSize = 118 * unit
    let spacing = 196 * unit
    let centre = NSPoint(x: size / 2, y: size / 2)

    for row in -1...1 {
        for column in -1...1 {
            let cell = NSRect(
                x: centre.x + CGFloat(column) * spacing - dotSize / 2,
                y: centre.y - CGFloat(row) * spacing - dotSize / 2,
                width: dotSize,
                height: dotSize
            )

            if row == 0 && column == 0 {
                // The middle cell is a play triangle: the one thing the grid is
                // for. Drawn slightly larger than a dot so it carries the same
                // optical weight — a triangle inside a circle's bounds always
                // looks smaller than the circle did.
                let scale: CGFloat = 1.34
                let triangle = NSRect(
                    x: cell.midX - dotSize * scale / 2,
                    y: cell.midY - dotSize * scale / 2,
                    width: dotSize * scale,
                    height: dotSize * scale
                )
                let path = NSBezierPath()
                // Nudged right, because a triangle's visual centre sits behind
                // its point rather than in the middle of its bounding box.
                let shift = triangle.width * 0.09
                path.move(to: NSPoint(x: triangle.minX + shift, y: triangle.minY))
                path.line(to: NSPoint(x: triangle.minX + shift, y: triangle.maxY))
                path.line(to: NSPoint(x: triangle.maxX + shift, y: triangle.midY))
                path.close()
                path.lineJoinStyle = .round
                path.lineWidth = 26 * unit

                NSColor(calibratedRed: 1.0, green: 0.31, blue: 0.36, alpha: 1).setFill()
                NSColor(calibratedRed: 1.0, green: 0.31, blue: 0.36, alpha: 1).setStroke()
                path.fill()
                // Stroked as well as filled, to round the corners off a shape
                // that is otherwise unpleasantly sharp at 16 points.
                path.stroke()
            } else {
                // The dots fade with distance from the middle, so the eye
                // lands on the triangle rather than sweeping the grid. Manhattan
                // distance rather than Chebyshev: the corners are genuinely
                // further away than the edge cells, and treating them as equal
                // — which `max(abs(row), abs(column))` does — is a vignette
                // that does not actually vignette anything.
                let distance = abs(row) + abs(column)
                let alpha = distance >= 2 ? 0.5 : 0.78
                NSColor(calibratedWhite: 0.98, alpha: alpha).setFill()
                NSBezierPath(ovalIn: cell).fill()
            }
        }
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
