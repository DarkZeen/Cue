import SwiftUI

/// Party mode: a gradient in the cover's two colours running round the
/// closed pill, faster on the beat.
///
/// Drawn by the shelf over its surface, on the surface's own outline, and
/// only while the wings are out — the open shelf stays plain. The line sits
/// on the edge rather than inside it, so half of it falls below the housing
/// and the whole pill is framed, not just its two wings: on a notched Mac
/// anything drawn inside the housing is under the camera and gone.
///
/// The speed follows the music without a tempo of its own to read. Each frame
/// the gradient moves on by an amount set by the music's energy and its beat,
/// so it surges on every hit and drifts between them — which, heard and seen
/// together, is the tempo. This is the one place a rate does follow the audio,
/// and it is allowed here for the reason the marks forbid it: the marks
/// compute their phase from the clock, and a rate change jumps it; this
/// integrates, so a change of rate only changes what happens next.
struct PartyBorder: View {
    let source: NowPlayingSource
    let cornerRadius: CGFloat
    let shoulder: CGFloat
    let isPlaying: Bool
    /// 0 to 1, from Settings: brighter, a little thicker, a stronger glow.
    let intensity: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = PhaseIntegrator()

    private var isAnimating: Bool { isPlaying && !reduceMotion }

    var body: some View {
        let colours = gradientColours
        let width = 1.2 + 1.8 * intensity
        let outline = TraySurface(cornerRadius: cornerRadius, shoulder: shoulder)

        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !isAnimating)) { context in
            let turn = isAnimating
                ? phase.advance(to: context.date, turnsPerSecond: rate)
                : phase.value
            let gradient = AngularGradient(
                colors: colours,
                center: .center,
                angle: .degrees(turn * 360)
            )

            ZStack {
                // The glow under the line, the stronger the party the wider.
                outline
                    .stroke(gradient, lineWidth: width * 2.5)
                    .blur(radius: 2 + 4 * intensity)
                    .opacity(0.35 + 0.45 * intensity)
                outline
                    .stroke(gradient, lineWidth: width * 2)
            }
        }
        .opacity((isPlaying ? 1 : 0.42) * (0.55 + 0.45 * intensity))
        .animation(.easeOut(duration: 0.25), value: isPlaying)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Turns per second, from the music. Read here, in the leaf, so sixty
    /// audio updates a second redraw the border and nothing round it.
    private var rate: Double {
        let elapsed = Date.timeIntervalSinceReferenceDate
        let energy = ProceduralMotion.energy(source.level(), at: elapsed)
        let beat = ProceduralMotion.beat(source.bands(), at: elapsed)
        return (0.06 + 0.22 * energy + 0.75 * beat * beat) * (0.6 + 0.8 * intensity)
    }

    /// The two colours, repeated round the ring so the sweep never shows a
    /// seam; white and grey for a cover with no colour to give.
    private var gradientColours: [Color] {
        let current = source.tints.current
        let first = current.primary ?? .white
        let second = current.secondary ?? Color.white.opacity(0.45)
        return [first, second, first, second, first]
    }
}

/// Where the border's gradient has got to, advanced a frame at a time.
///
/// A reference type held in `@State`, so moving it on during a redraw does not
/// ask for another one: the timeline is what drives the redraws.
@MainActor
final class PhaseIntegrator {
    /// Turns, wrapped to 0..<1.
    private(set) var value: Double = 0
    private var last: Date?

    func advance(to now: Date, turnsPerSecond rate: Double) -> Double {
        defer { last = now }
        guard let last else { return value }
        // A long gap — the shelf was open, the music paused — is not a long
        // turn: it picks up where it left off.
        let step = min(max(now.timeIntervalSince(last), 0), 0.1)
        value = (value + step * rate).truncatingRemainder(dividingBy: 1)
        return value
    }
}
