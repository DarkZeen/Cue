import SwiftUI

/// Cue's mark, drawn at any size.
///
/// The same shape `Scripts/make-icon.swift` draws for the app icon — a playhead
/// marker and a play triangle starting from it — so the thing in the corner of
/// the screen and the thing in the Dock are one mark rather than two drawings
/// that happen to resemble each other.
///
/// Proportions are expressed against the marker's height, which is the tallest
/// element, so callers size it the way they would size text.
struct CueMark: View {
    /// The marker's height. Everything else is derived from it.
    var height: CGFloat = 18
    var markerColor: Color = .white
    var accentColor: Color = CuePalette.accent

    // From the icon, on its 1024 canvas.
    private var unit: CGFloat { height / 470 }
    private var markerWidth: CGFloat { max(34 * unit, 1.5) }
    private var gap: CGFloat { max(62 * unit, 1.5) }
    private var triangleWidth: CGFloat { max(250 * unit, 5) }
    private var triangleHeight: CGFloat { max(300 * unit, 6) }

    var body: some View {
        HStack(spacing: gap) {
            Capsule()
                .fill(markerColor)
                .frame(width: markerWidth, height: height)

            PlayTriangle()
                .fill(accentColor)
                .frame(width: triangleWidth, height: triangleHeight)
        }
        .frame(width: markerWidth + gap + triangleWidth, height: height)
        .accessibilityHidden(true)
    }
}

/// A play triangle with softened corners.
///
/// Rounded because a sharp apex at these sizes aliases into grey mush, and
/// because the icon's own triangle is rounded — a square-cornered one beside it
/// would read as a different mark.
struct PlayTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        let corner = min(rect.width, rect.height) * 0.16

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + corner / 2))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - corner / 2))
        path.addLine(to: CGPoint(x: rect.maxX - corner / 2, y: rect.midY))
        path.closeSubpath()

        return path.strokedPath(.init(lineWidth: corner, lineJoin: .round))
            .union(path)
    }
}

/// The colours the redesigned surfaces are drawn from.
///
/// Small on purpose. The world is near-black grounds, one accent, and artwork —
/// which means most of the colour on screen belongs to the album covers, and
/// anything Cue adds competes with them.
enum CuePalette {
    /// The single accent. The red of the mark and of anything currently active.
    static let accent = Color(red: 1.0, green: 0.13, blue: 0.24)

    /// The panel's ground. Near-black rather than black: true black gives a
    /// translucent surface nothing to be translucent against, and sits oddly
    /// beside the system's own materials.
    static let ground = Color(white: 0.07)

    /// The ground a tile sits on before its artwork arrives.
    static let tileGround = Color(white: 0.14)
}
