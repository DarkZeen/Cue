import SwiftUI

// The Today page's pixel look, as chosen in the Cue dither league (2026-11-23): the SmallTV's square-pixel
// countdown, its minute field on the right, and a marching checker round for "now".

/// 5×7 pixel glyphs for the countdown and the day: the digits, the colon and %, as on the SmallTV.
enum PixelFont {
    static let glyphs: [Character: [String]] = [
        "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
        "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
        "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
        "3": ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
        "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
        "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
        "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
        "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
        "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
        "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
        ":": ["0", "0", "1", "0", "1", "0", "0"],
        "%": ["11001", "11010", "00010", "00100", "01000", "01011", "10011"],
    ]

    /// Whether every character has a glyph, so the text can be drawn in pixels.
    static func canDraw(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { glyphs[$0] != nil }
    }

    /// Width in cells, with one empty column between characters.
    static func columns(_ text: String) -> Int {
        let widths = text.compactMap { glyphs[$0]?.first?.count }
        return widths.reduce(0, +) + max(0, widths.count - 1)
    }
}

/// Text in square pixels on a grid: lit pixels in the ink, the unlit ones faintly visible.
struct PixelDigits: View {
    let text: String
    let lit: Color
    let unlit: Color
    var cell: CGFloat = 4
    var pixel: CGFloat = 3.2

    var body: some View {
        Canvas { context, _ in
            var on = Path(), off = Path()
            var column = 0
            for character in text {
                guard let glyph = PixelFont.glyphs[character] else { continue }
                for (row, line) in glyph.enumerated() {
                    for (index, bit) in line.enumerated() {
                        let inset = (cell - pixel) / 2
                        let rect = CGRect(x: CGFloat(column + index) * cell + inset, y: CGFloat(row) * cell + inset,
                                          width: pixel, height: pixel)
                        if bit == "1" { on.addRect(rect) } else { off.addRect(rect) }
                    }
                }
                column += (glyph.first?.count ?? 0) + 1
            }
            context.fill(off, with: .color(unlit))
            context.fill(on, with: .color(lit))
        }
        .frame(width: CGFloat(PixelFont.columns(text)) * cell, height: 7 * cell)
        .accessibilityLabel(text)
    }
}

/// The 8×8 Bayer matrix, for the square that is emptying.
enum OrderedDither {
    static let matrix: [[Int]] = {
        var m = [[0]]
        while m.count < 8 {
            let k = m.count
            m = (0..<2 * k).map { y in
                (0..<2 * k).map { x in m[y % k][x % k] * 4 + (y < k ? (x < k ? 0 : 2) : (x < k ? 3 : 1)) }
            }
        }
        return m
    }()

    /// Whether the cell at this column and row is lit at a level of 0…1.
    static func isLit(column: Int, row: Int, level: Double) -> Bool {
        level > (Double(matrix[row & 7][column & 7]) + 0.5) / 64
    }
}

/// The period as squares, five to a row, like the SmallTV's pixel field: the gone ones dark, the rest lit,
/// and the one under way emptying in an ordered dither.
struct MinuteField: View {
    let field: TodayFace.Field
    let colour: Color
    let spent: Color
    var pitch: CGFloat = 9
    var square: CGFloat = 7
    var columns = 5

    var body: some View {
        let rows = (field.count + columns - 1) / columns
        Canvas { context, _ in
            let done = Int(field.gone.rounded(.down))
            var dark = Path(), lit = Path(), speck = Path()
            for index in 0..<field.count {
                let origin = CGPoint(x: CGFloat(index % columns) * pitch, y: CGFloat(index / columns) * pitch)
                let rect = CGRect(origin: origin, size: CGSize(width: square, height: square))
                if index < done {
                    dark.addRect(rect)
                } else if index == done {
                    dark.addRect(rect)
                    let level = 1 - (field.gone - Double(done))
                    let cells = Int(square)
                    for row in 0..<cells {
                        for column in 0..<cells where OrderedDither.isLit(column: column, row: row, level: level) {
                            speck.addRect(CGRect(x: origin.x + CGFloat(column), y: origin.y + CGFloat(row), width: 1, height: 1))
                        }
                    }
                } else {
                    lit.addRect(rect)
                }
            }
            context.fill(dark, with: .color(spent))
            context.fill(lit, with: .color(colour))
            context.fill(speck, with: .color(colour))
        }
        .frame(width: CGFloat(columns - 1) * pitch + square,
               height: CGFloat(max(0, rows - 1)) * pitch + square)
        .accessibilityHidden(true)
    }
}

/// The round under way: a square of checker pixels marching round its edge.
struct MarchingSquare: View {
    let colour: Color
    var size: CGFloat = 10
    var step: CGFloat = 1.5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.14, paused: reduceMotion)) { context in
            let offset = reduceMotion ? 0 : Int(context.date.timeIntervalSinceReferenceDate / 0.14) % 4
            Canvas { canvas, _ in
                let n = Int(4 * size / step)
                var path = Path()
                for i in 0..<n where (i + offset) & 3 <= 1 {
                    var d = CGFloat(i) * step
                    let point: CGPoint
                    if d < size { point = CGPoint(x: d, y: 0) }
                    else if (d - size) < size { d -= size; point = CGPoint(x: size - step, y: d) }
                    else if (d - 2 * size) < size { d -= 2 * size; point = CGPoint(x: size - d - step, y: size - step) }
                    else { d -= 3 * size; point = CGPoint(x: 0, y: size - d - step) }
                    path.addRect(CGRect(origin: point, size: CGSize(width: step, height: step)))
                }
                canvas.fill(path, with: .color(colour))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

