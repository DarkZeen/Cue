import SwiftUI

/// The Today page's dither, as chosen in the design league (Today + LED dot field + dithered serif digits):
/// a quiet grid of unlit dots behind the page, like the SmallTV's dot matrix, and the big number filled with
/// an ordered (Bayer 4×4) dither that runs from the ink at the top to the period's colour at the bottom.
enum OrderedDither {
    /// The 4×4 Bayer matrix, 0…15.
    static let matrix: [[Int]] = [
        [0, 8, 2, 10],
        [12, 4, 14, 6],
        [3, 11, 1, 9],
        [15, 7, 13, 5],
    ]

    /// How much of the lower colour a row shows, 0…1: none in the top quarter, then rising to full
    /// just above the bottom.
    static func tone(row: Int, rows: Int) -> Double {
        guard rows > 0 else { return 0 }
        let v = (Double(row) + 0.5) / Double(rows)
        return min(1, max(0, (v - 0.25) * 1.4))
    }

    /// Whether the cell at this column and row takes the lower colour.
    static func isLit(column: Int, row: Int, rows: Int) -> Bool {
        let threshold = (Double(matrix[row & 3][column & 3]) + 0.5) / 16
        return tone(row: row, rows: rows) > threshold
    }
}

/// A two-colour ordered-dither gradient, top colour to bottom colour, on a grid of `cell`-point squares.
struct DitherGradient: View {
    let top: Color
    let bottom: Color
    var cell: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(top))
            let columns = Int((size.width / cell).rounded(.up))
            let rows = Int((size.height / cell).rounded(.up))
            var lit = Path()
            for row in 0..<rows {
                for column in 0..<columns where OrderedDither.isLit(column: column, row: row, rows: rows) {
                    lit.addRect(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell))
                }
            }
            context.fill(lit, with: .color(bottom))
        }
        .accessibilityHidden(true)
    }
}

/// A grid of unlit dots behind the page, like the SmallTV's dot matrix.
struct DotField: View {
    var pitch: CGFloat = 6
    var radius: CGFloat = 1.3

    @Environment(\.trayPalette) private var palette

    var body: some View {
        Canvas { context, size in
            var dots = Path()
            var y = pitch / 2
            while y < size.height {
                var x = pitch / 2
                while x < size.width {
                    dots.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                    x += pitch
                }
                y += pitch
            }
            context.fill(dots, with: .color(palette.ink(0.08)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
