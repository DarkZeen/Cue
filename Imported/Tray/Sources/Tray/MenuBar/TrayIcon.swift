import AppKit

/// The menu bar glyph (§32).
///
/// Drawn rather than shipped as an asset so it stays crisp at every menu bar
/// height and adapts to light and dark bars through template rendering.
///
/// It is the app icon's creature, reduced to what survives at sixteen points: a
/// body with one corner swept away, and two eyes knocked straight out of it. The
/// eyes have to be holes rather than dark shapes, because a template image has
/// exactly one colour to work with.
enum TrayIcon {
    static func menuBarImage() -> NSImage {
        let size = NSSize(width: 17, height: 15)

        let image = NSImage(size: size, flipped: false) { _ in
            let path = NSBezierPath()
            // Even-odd winding: the eyes are subtracted from the body rather
            // than painted over it, so the menu bar shows through them.
            path.windingRule = .evenOdd

            path.append(
                body(NSRect(x: 1.4, y: 1.0, width: 14.2, height: 13.4))
            )
            path.append(eye(center: NSPoint(x: 6.8, y: 7.4), width: 2.9, height: 5.6))
            path.append(eye(center: NSPoint(x: 11.1, y: 8.6), width: 2.5, height: 4.7))

            NSColor.black.setFill()
            path.fill()

            return true
        }

        // Template rendering lets macOS invert the glyph for light menu bars,
        // highlight it correctly, and tint it in accent-coloured bars.
        image.isTemplate = true
        return image
    }

    /// The creature's silhouette: one corner swept far more than the others,
    /// which is what stops it reading as a rounded rectangle.
    private static func body(_ rect: NSRect) -> NSBezierPath {
        let path = NSBezierPath()
        let topLeft = rect.width * 0.42
        let topRight = rect.width * 0.72
        let bottomRight = rect.width * 0.30
        let bottomLeft = rect.width * 0.36

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

    private static func eye(center: NSPoint, width: CGFloat, height: CGFloat) -> NSBezierPath {
        let path = NSBezierPath(
            roundedRect: NSRect(
                x: -width / 2,
                y: -height / 2,
                width: width,
                height: height
            ),
            xRadius: width / 2,
            yRadius: width / 2
        )
        var transform = AffineTransform.identity
        transform.translate(x: center.x, y: center.y)
        transform.rotate(byDegrees: -16)
        path.transform(using: transform)
        return path
    }
}
