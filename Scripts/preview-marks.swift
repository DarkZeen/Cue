import AppKit
import SwiftUI

/// Renders every mark at several moments onto one sheet, so the four of them
/// can be looked at side by side without running the app.
@MainActor
func sheet() -> some View {
    let moments: [TimeInterval] = [0, 0.45, 0.9, 1.5, 2.3, 3.4, 5.1, 7.2]

    return VStack(alignment: .leading, spacing: 18) {
        ForEach(PlaqueAnimation.allCases, id: \.self) { style in
            VStack(alignment: .leading, spacing: 6) {
                Text(style.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))

                HStack(spacing: 14) {
                    ForEach(moments, id: \.self) { moment in
                        Group {
                            switch style {
                            case .wave: WaveIndicator(elapsed: moment, isAnimating: true)
                            case .disc: DiscIndicator(elapsed: moment, isAnimating: true)
                            case .bars: BarsIndicator(elapsed: moment, isAnimating: true)
                            case .orbit: OrbitIndicator(elapsed: moment, isAnimating: true)
                            }
                        }
                        .frame(width: style.markWidth, height: 26)
                    }

                    Divider().frame(height: 20).overlay(.white.opacity(0.2))

                    // Stopped, which is a state with its own drawing.
                    Group {
                        switch style {
                        case .wave: WaveIndicator(elapsed: 0, isAnimating: false)
                        case .disc: DiscIndicator(elapsed: 0, isAnimating: false)
                        case .bars: BarsIndicator(elapsed: 0, isAnimating: false)
                        case .orbit: OrbitIndicator(elapsed: 0, isAnimating: false)
                        }
                    }
                    .frame(width: style.markWidth, height: 26)
                    .opacity(0.42)
                }
            }
        }
    }
    .padding(20)
    .background(Color(white: 0.07))
}

@main
enum Preview {
    @MainActor
    static func main() throws {
        guard CommandLine.arguments.count > 1 else {
            FileHandle.standardError.write(Data("usage: preview-marks <output.png>\n".utf8))
            exit(1)
        }

        let renderer = ImageRenderer(content: sheet())
        // Four, so the hairlines — a groove, a bar, the arm — are visible at
        // all. At 1x this sheet is a row of smudges and proves nothing.
        renderer.scale = 4

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            FileHandle.standardError.write(Data("render failed\n".utf8))
            exit(1)
        }

        try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
