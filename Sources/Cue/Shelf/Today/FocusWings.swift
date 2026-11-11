import SwiftUI

/// The closed pill while Mia's focus timer runs and nothing is playing: how much of the period is gone, as a
/// ring in the left wing, and the countdown in the right.
///
/// The same two wings the music and the headphones use, so the notch keeps one shape whatever it is showing.
/// One click on the countdown pauses or resumes, the way the timer's own button does; nothing else here takes
/// a click, and neither wing opens the shelf (the window keeps them out of the hover strip).
struct FocusWings<Centre: View>: View {
    let source: NowPlayingSource
    let focus: MiaFocus
    let cutout: CGSize
    @ViewBuilder let centre: () -> Centre

    @Environment(\.trayPalette) private var palette

    var body: some View {
        let artSize = TrayMetrics.wingArtSize(forHeight: cutout.height)
        let padding = TrayMetrics.wingPadding(forHeight: cutout.height)
        let shoulder = TrayMetrics.effectiveShoulder(forHeight: cutout.height)

        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 0) {
                FocusRing(focus: focus, now: context.date, diameter: artSize * 0.86)
                    .frame(width: artSize, height: cutout.height)
                    .padding(.horizontal, padding)
                    .overlay { PillClickTarget(onSingle: nil, onDouble: {}, toolTip: toolTip) }
                    .padding(.leading, shoulder)

                Color.clear
                    .frame(width: cutout.width, height: cutout.height)
                    .overlay { centre() }

                Text(MiaFocus.clock(focus.left(at: context.date)))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(FocusRing.colour(focus).opacity(focus.isPaused ? 0.55 : 1))
                    .fixedSize()
                    .frame(width: artSize, height: cutout.height)
                    .padding(.horizontal, padding)
                    .overlay {
                        PillClickTarget(
                            onSingle: { source.focusCommand(focus.isPaused ? .resume : .pause) },
                            onDouble: {},
                            toolTip: toolTip
                        )
                    }
                    .padding(.trailing, shoulder)
            }
            .frame(height: cutout.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAction(named: focus.isPaused ? "Resume" : "Pause") {
            source.focusCommand(focus.isPaused ? .resume : .pause)
        }
    }

    private var toolTip: String {
        let what = focus.task.map { "\(focus.phase.title) — \($0)" } ?? focus.phase.title
        return focus.isPaused ? "\(what) (paused). Click to resume." : "\(what). Click to pause."
    }

    private var label: String {
        "\(focus.phase.title)\(focus.isPaused ? ", paused" : ""), \(MiaFocus.clock(focus.left(at: Date()))) left"
    }
}

/// How much of the focus period is gone, as a ring: amber for focus, green for a break, dimmed while paused.
struct FocusRing: View {
    let focus: MiaFocus
    let now: Date
    let diameter: CGFloat

    @Environment(\.trayPalette) private var palette

    var body: some View {
        let width = max(2, diameter * 0.14)
        ZStack {
            Circle().stroke(palette.ink(0.18), lineWidth: width)
            Circle()
                .trim(from: 0, to: focus.progress(at: now))
                .stroke(Self.colour(focus), style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter - width, height: diameter - width)
        .opacity(focus.isPaused ? 0.55 : 1)
        .animation(.linear(duration: 1), value: focus.progress(at: now))
    }

    static func colour(_ focus: MiaFocus) -> Color {
        focus.phase.isBreak ? .green : .orange
    }
}
