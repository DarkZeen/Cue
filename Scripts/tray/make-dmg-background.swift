#!/usr/bin/env swift

// Draws the disk image background (§65).
//
// Quiet on purpose: a soft neutral field and one arrow. A DMG window is a
// signpost the user looks at for two seconds, and every extra thing on it is
// something between them and the one action they came to perform.

import AppKit
import Foundation

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: make-dmg-background.swift <output.png>\n".utf8))
    exit(1)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])

// 2× the window size, so the background stays sharp on a Retina display.
let scale: CGFloat = 2
let size = NSSize(width: 620 * scale, height: 400 * scale)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width),
    pixelsHigh: Int(size.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let bounds = NSRect(origin: .zero, size: size)

NSGradient(colors: [
    NSColor(calibratedRed: 0.965, green: 0.968, blue: 0.976, alpha: 1),
    NSColor(calibratedRed: 0.906, green: 0.914, blue: 0.933, alpha: 1),
])?.draw(in: bounds, angle: -90)

// The arrow between the two icons. It says "that way" without a caption.
let arrowY = size.height - 190 * scale
let arrow = NSBezierPath()
arrow.lineWidth = 3 * scale
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 268 * scale, y: arrowY))
arrow.line(to: NSPoint(x: 352 * scale, y: arrowY))
arrow.move(to: NSPoint(x: 338 * scale, y: arrowY + 11 * scale))
arrow.line(to: NSPoint(x: 352 * scale, y: arrowY))
arrow.line(to: NSPoint(x: 338 * scale, y: arrowY - 11 * scale))
NSColor(calibratedWhite: 0.55, alpha: 1).setStroke()
arrow.stroke()

let caption = "Drag Tray into your Applications folder"
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13 * scale, weight: .regular),
    .foregroundColor: NSColor(calibratedWhite: 0.42, alpha: 1),
]
let measured = caption.size(withAttributes: attributes)
caption.draw(
    at: NSPoint(x: (size.width - measured.width) / 2, y: 62 * scale),
    withAttributes: attributes
)

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: output)
print("dmg background → \(output.path)")
