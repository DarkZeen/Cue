import AppKit
import SwiftUI

/// The menu bar glyph (§32): Cue's logo, as a template image.
///
/// Drawn from `CueLogoPath` rather than shipped as an asset, so it stays crisp
/// at every menu bar height and adapts to light and dark bars through template
/// rendering. One app, one mark — the shelf's header uses it too.
enum MenuBarIcon {
    static func menuBarImage(height: CGFloat = 15) -> NSImage {
        let markWidth = height * CueLogoPath.aspect
        // A little air either side, so the status item is not a sliver.
        let size = NSSize(width: (markWidth + 3).rounded(.up), height: height)

        let image = NSImage(size: size, flipped: true) { bounds in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            // The logo's unit box runs y-down, which a flipped image matches.
            let rect = CGRect(
                x: (bounds.width - markWidth) / 2,
                y: 0,
                width: markWidth,
                height: height
            )
            context.addPath(CueLogoPath.path(in: rect).cgPath)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            return true
        }

        // Template rendering lets macOS invert the glyph for light menu bars,
        // highlight it correctly, and tint it in accent-coloured bars.
        image.isTemplate = true
        return image
    }
}
