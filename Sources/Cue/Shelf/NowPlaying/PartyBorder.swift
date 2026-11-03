import SwiftUI

/// Party mode: a gradient in the cover's two colours running round the
/// closed pill, faster on the beat.
///
/// Drawn by the shelf over its surface, only while the wings are out — the
/// open shelf stays plain. The line runs down the sides and along the bottom,
/// a little way outside the black, and stops below the shoulders: nothing
/// along the top edge, which is the bezel, and nothing on the surface itself,
/// where on a notched Mac the camera housing would cover it.
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
        let outline = PartyOutline(
            cornerRadius: cornerRadius,
            shoulder: shoulder,
            // Clear of the black by a hair, so all of the line is seen.
            gap: width / 2 + 1
        )

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
                    .stroke(gradient, style: StrokeStyle(lineWidth: width * 1.6, lineCap: .round))
                    .blur(radius: 2 + 4 * intensity)
                    .opacity(0.35 + 0.45 * intensity)
                outline
                    .stroke(gradient, style: StrokeStyle(lineWidth: width, lineCap: .round))
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

/// The pill's shoulders, sides and bottom, `gap` outside its surface: an open
/// line that starts at the screen's top edge beside one shoulder and ends at
/// it beside the other, never running along the edge itself.
///
/// Traced from the same numbers `TraySurface` draws with — its shoulder and
/// bottom-corner rules — so it follows the black at a constant distance.
struct PartyOutline: Shape {
    var cornerRadius: CGFloat
    var shoulder: CGFloat
    var gap: CGFloat

    nonisolated func path(in rect: CGRect) -> Path {
        guard rect.width > 0, rect.height > 0 else { return Path() }

        // `TraySurface.path(in:)`'s own rules, on the surface's own rect.
        let shoulder = max(0, min(self.shoulder, rect.height * 0.28, rect.width / 2))
        let bottom = max(0, min(cornerRadius, rect.height / 2, (rect.width - shoulder * 2) / 2))

        // Walls and bottom pushed out by `gap`; the corners grow by the same.
        let left = rect.minX + shoulder - gap
        let right = rect.maxX - shoulder + gap
        let floor = rect.maxY + gap
        let radius = bottom + gap
        let top = rect.minY + shoulder

        // The shoulders are concave quarter circles centred out beside the
        // shape, at the wall's top; outside them is toward that centre, so the
        // offset curve has the same centre and a radius `gap` smaller.
        let shoulderRadius = shoulder - gap
        let rightShoulder = CGPoint(x: rect.maxX, y: top)
        let leftShoulder = CGPoint(x: rect.minX, y: top)

        var path = Path()
        if shoulderRadius > 0 {
            path.move(to: CGPoint(x: rect.maxX, y: top - shoulderRadius))
            path.addArc(
                center: rightShoulder,
                radius: shoulderRadius,
                startAngle: .degrees(270),
                endAngle: .degrees(180),
                clockwise: true
            )
        } else {
            path.move(to: CGPoint(x: right, y: top))
        }
        path.addLine(to: CGPoint(x: right, y: floor - radius))
        path.addArc(
            center: CGPoint(x: right - radius, y: floor - radius),
            radius: radius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: left + radius, y: floor))
        path.addArc(
            center: CGPoint(x: left + radius, y: floor - radius),
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: left, y: top))
        if shoulderRadius > 0 {
            path.addArc(
                center: leftShoulder,
                radius: shoulderRadius,
                startAngle: .degrees(0),
                endAngle: .degrees(270),
                clockwise: true
            )
        }
        return path
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
