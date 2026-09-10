import AppKit
import SwiftUI

/// Renders every mark at several moments onto one sheet, so the four of them
/// can be looked at side by side without running the app.
/// A plausible spectrum for a given instant, so the reactive path can be seen
/// without a tap and without music.
///
/// Not random. A quiet moment, a build and a hit have different *shapes*, and
/// what needs looking at is whether the mark distinguishes them — so the beat
/// is a sharp low-end spike and the highs chatter over it, which is roughly
/// what a real spectrum does.
func simulated(at moment: TimeInterval) -> (level: Double, bands: [Double]) {
    let kick = pow((sin(moment * 1.9 * .pi) + 1) / 2, 4)
    let bands = (0..<9).map { band -> Double in
        let position = Double(band) / 8
        let low = kick * (1 - position)
        let high = (sin(moment * (4.1 + Double(band) * 0.7)) + 1) / 2 * position * 0.55
        return min(0.18 + low * 0.8 + high, 1)
    }
    let level = bands.enumerated().reduce(0.0) { total, entry in
        total + entry.element * (1 - 0.6 * Double(entry.offset) / 8)
    } / 6.6
    return (min(level, 1), bands)
}

@MainActor
func row(_ style: PlaqueAnimation, listening: Bool) -> some View {
    let moments: [TimeInterval] = [0, 0.45, 0.9, 1.5, 2.3, 3.4, 5.1, 7.2]

    return VStack(alignment: .leading, spacing: 6) {
        Text(style.title + (listening ? "  ·  hearing the music" : "  ·  on its own"))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(listening ? 0.75 : 0.45))

        HStack(spacing: 14) {
            ForEach(moments, id: \.self) { moment in
                let heard = listening ? simulated(at: moment) : (level: 0.0, bands: [Double]())

                Group {
                    switch style {
                    case .wave:
                        WaveIndicator(elapsed: moment, level: heard.level, bands: heard.bands, isAnimating: true)
                    case .disc:
                        DiscIndicator(elapsed: moment, level: heard.level, bands: heard.bands, isAnimating: true)
                    case .bars:
                        BarsIndicator(elapsed: moment, level: heard.level, bands: heard.bands, isAnimating: true)
                    case .orbit:
                        OrbitIndicator(elapsed: moment, level: heard.level, bands: heard.bands, isAnimating: true)
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

@MainActor
func sheet() -> some View {
    VStack(alignment: .leading, spacing: 16) {
        ForEach(PlaqueAnimation.allCases, id: \.self) { style in
            row(style, listening: false)
            row(style, listening: true)
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
