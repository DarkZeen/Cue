import SwiftUI

/// One shape of the mark, drawn where it belongs within the whole.
///
/// Each is given the mark's full rectangle rather than a slice of it, so the
/// thirteen shapes land in the right places relative to each other and can then
/// be moved individually.
nonisolated struct CueLogoShape: Shape {
    let index: Int

    func path(in rect: CGRect) -> Path {
        // Fitted to the artwork's aspect so the mark is never stretched, and
        // every shape is fitted to the *same* box or they would drift apart.
        let scale = min(rect.width / CueLogoPath.aspect, rect.height)
        let size = CGSize(width: scale * CueLogoPath.aspect, height: scale)
        let box = CGRect(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        return CueLogoPath.path(forShape: index, in: box)
    }
}

/// Cue's mark, still. Used where a logo is wanted rather than a performance.
struct CueMark: View {
    var height: CGFloat = 18
    var tint: Color = .white

    var body: some View {
        CueLogoPath.path(in: CGRect(
            origin: .zero,
            size: CGSize(width: height * CueLogoPath.aspect, height: height)
        ))
        .fill(tint)
        .frame(width: height * CueLogoPath.aspect, height: height)
        .accessibilityHidden(true)
    }
}

/// The mark, alive.
///
/// The artwork's own shapes, each stretched about the centre line. Nothing is
/// redrawn or approximated — the thing that moves is the logo, which is the
/// only way the corner of the screen and the Dock stay recognisably the same
/// mark.
///
/// Two rules give it its character. A travelling phase runs along the mark so
/// the shapes do not all rise together — shapes pulsing in unison read as one
/// shape breathing, which is what this replaced. And the small shapes travel
/// further than the tall one: the mark decays from left to right, the tall
/// shape is what makes it recognisable, and a logo whose anchor pumps reads as
/// a novelty.
struct CueWaveformView: View {
    var height: CGFloat = 18
    /// 0 to 1. The page's own analysis when it will give it up, and a stand-in
    /// otherwise — see `PlayerService.audioLevel`.
    var level: Double = 0
    var isPlaying: Bool = false
    var tint: Color = .white

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var count: Int { CueLogoPath.shapes.count }
    private var width: CGFloat { height * CueLogoPath.aspect }

    var body: some View {
        TimelineView(.animation(paused: !isPlaying || reduceMotion)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate

            ZStack {
                ForEach(0..<count, id: \.self) { index in
                    CueLogoShape(index: index)
                        .fill(tint)
                        // About the centre, so a shape grows in both directions
                        // like a waveform rather than sprouting upward.
                        .scaleEffect(y: displacement(index, at: elapsed), anchor: .center)
                }
            }
            .frame(width: width, height: height)
        }
        .frame(width: width, height: height)
    }

    /// How far this shape is stretched from its resting height, this instant.
    private func displacement(_ index: Int, at elapsed: TimeInterval) -> CGFloat {
        guard isPlaying, !reduceMotion else { return 1 }

        // How far along the decay this shape sits: 0 is the tall one, 1 is the
        // smallest.
        let along = Double(index) / Double(max(count - 1, 1))

        // The small shapes move most. The tall one anchors the mark, and a logo
        // whose largest element pumps reads as a novelty.
        let reach = 0.25 + 0.75 * along

        // The phase travels along the decay, which is the direction the mark
        // already reads in.
        let phase = elapsed * 3.4 - along * 2.2
        let wave = (sin(phase) + sin(phase * 1.63 + 0.7)) / 2

        // The level decides how much of that motion is expressed. Silence is
        // stillness; loud is the full swing.
        let amplitude = 0.06 + 0.34 * min(max(level, 0), 1)

        return 1 + CGFloat(wave * amplitude) * reach
    }
}

/// The colours the redesigned surfaces are drawn from.
///
/// Small on purpose. The world is near-black grounds, one accent, and artwork —
/// which means most of the colour on screen belongs to the album covers, and
/// anything Cue adds competes with them.
enum CuePalette {
    /// The single accent. Used for what is active, never for the mark itself:
    /// the logo is white on black, and it stays that way.
    static let accent = Color(red: 1.0, green: 0.13, blue: 0.24)

    /// The panel's ground. Near-black rather than black: true black gives a
    /// translucent surface nothing to be translucent against.
    static let ground = Color(white: 0.07)

    /// The ground a tile sits on before its artwork arrives.
    static let tileGround = Color(white: 0.14)
}
