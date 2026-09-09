import SwiftUI

/// The waveform Cue is drawn from: lenses in a symmetric envelope, tallest in
/// the middle.
///
/// The same description `Scripts/make-icon.swift` draws the app icon from, so
/// the thing in the Dock and the thing moving in the corner of the screen are
/// one mark rather than two drawings that resemble each other.
enum CueWaveform {
    /// How many lenses to draw at a given height.
    ///
    /// Nine is the mark, and nine is unreadable small — the gaps fall below a
    /// pixel and it mushes into a blob. The small sizes draw a simplified
    /// version of the same idea rather than a shrunk version of the same
    /// drawing.
    static func count(for height: CGFloat) -> Int {
        switch height {
        case 40...: 9
        case 18...: 7
        default: 5
        }
    }

    /// Relative height of each lens, 0 to 1.
    static func envelope(_ index: Int, count: Int) -> CGFloat {
        guard count > 1 else { return 1 }
        let position = CGFloat(index) / CGFloat(count - 1)
        let phase = 0.085 + 0.83 * position
        return pow(sin(phase * .pi), 0.9)
    }

    /// How wide a lens of a given height should be. Bolder when there are fewer
    /// of them, so a simplified mark carries the same weight.
    static func width(forHeight height: CGFloat, count: Int) -> CGFloat {
        let ratio: CGFloat = count >= 9 ? 0.115 : (count >= 7 ? 0.15 : 0.2)
        return max(height * ratio, 1.2)
    }
}

/// One lens: a vesica with pointed ends.
struct LensShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let top = CGPoint(x: rect.midX, y: rect.minY)
        let bottom = CGPoint(x: rect.midX, y: rect.maxY)
        // A cubic with both controls at the same offset reaches three quarters
        // of it, so the reach is divided back out to land on the intended width.
        let reach = (rect.width / 2) / 0.75
        let lift = rect.height / 4

        path.move(to: top)
        path.addCurve(
            to: bottom,
            control1: CGPoint(x: rect.midX + reach, y: rect.minY + lift),
            control2: CGPoint(x: rect.midX + reach, y: rect.maxY - lift)
        )
        path.addCurve(
            to: top,
            control1: CGPoint(x: rect.midX - reach, y: rect.maxY - lift),
            control2: CGPoint(x: rect.midX - reach, y: rect.minY + lift)
        )
        path.closeSubpath()
        return path
    }
}

/// Cue's mark, still. Used where a logo is wanted rather than a performance.
struct CueMark: View {
    var height: CGFloat = 18
    var tint: Color = .white

    var body: some View {
        CueWaveformView(height: height, level: 0, isPlaying: false, tint: tint)
            .accessibilityHidden(true)
    }
}

/// The mark, alive.
///
/// Every lens is driven by two things: where it sits in the envelope, and how
/// loud the music is right now. The envelope keeps it recognisable as Cue's
/// mark at rest; the level is what makes it the *music's* mark while something
/// is playing.
///
/// A travelling phase runs through it so the lenses do not all rise together —
/// nine shapes pulsing in unison reads as one shape breathing, which is the
/// thing this replaced.
struct CueWaveformView: View {
    var height: CGFloat = 18
    /// 0 to 1. Real, when the page will give it up; otherwise a stand-in.
    var level: Double = 0
    var isPlaying: Bool = false
    var tint: Color = .white

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var count: Int { CueWaveform.count(for: height) }
    private var spacing: CGFloat { max(height * 0.055, 1) }

    var body: some View {
        TimelineView(.animation(paused: !isPlaying || reduceMotion)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate

            HStack(spacing: spacing) {
                ForEach(0..<count, id: \.self) { index in
                    let envelope = CueWaveform.envelope(index, count: count)
                    let lensHeight = height * envelope * displacement(index, at: elapsed)
                    let width = CueWaveform.width(forHeight: height * envelope, count: count)

                    LensShape()
                        .fill(tint.opacity(0.72 + 0.28 * envelope))
                        .frame(width: width, height: max(lensHeight, width))
                }
            }
            .frame(height: height)
        }
    }

    /// How far this lens is pushed from its resting height, at this instant.
    private func displacement(_ index: Int, at elapsed: TimeInterval) -> CGFloat {
        guard isPlaying, !reduceMotion else { return 1 }

        // Outer lenses travel further than inner ones. A waveform whose middle
        // moves most looks like it is inflating; one whose edges move most
        // looks like sound arriving.
        let envelope = CueWaveform.envelope(index, count: count)
        let reach = 0.55 + 0.45 * (1 - envelope)

        // The phase walks along the mark rather than hitting every lens at once,
        // which is the difference between a waveform and a heartbeat.
        let phase = elapsed * 3.2 - Double(index) * 0.42
        let wave = (sin(phase) + sin(phase * 1.7 + 0.9)) / 2

        // The level sets how much of that motion is expressed. Silence is
        // stillness; loud is the full swing.
        let amplitude = 0.10 + 0.42 * min(max(level, 0), 1)

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
