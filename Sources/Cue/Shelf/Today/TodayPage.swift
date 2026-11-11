import SwiftUI

/// The open shelf's second page: how far through the working day you are, Mia's focus timer, and how long
/// you have focused.
///
/// Reached by swiping across the open shelf. Everything on it is a glance and a press or two — the timer's
/// buttons work Mia's timer, which stays Mia's (`MiaFocusLink`) — and nothing here needs the keyboard.
struct TodayPage: View {
    let source: NowPlayingSource

    @Environment(\.trayPalette) private var palette

    var body: some View {
        // Once a second for the countdown and the bar; nothing else here moves.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 12) {
                DayBar(workday: source.workday(), now: context.date)
                HStack(alignment: .top, spacing: 12) {
                    focusCard(now: context.date)
                    focusedCard
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: The timer

    @ViewBuilder
    private func focusCard(now: Date) -> some View {
        TodayCard {
            if let focus = source.focus(), focus.enabled {
                VStack(alignment: .leading, spacing: 6) {
                    Text(focusHeading(focus))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.ink(0.55))
                    Text(focus.state == .idle ? MiaFocus.clock(focus.length * 60) : MiaFocus.clock(focus.left(at: now)))
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(focus.isPaused ? palette.ink(0.55) : palette.primaryInk)
                        .contentTransition(.numericText(countsDown: true))
                    if let task = focus.task {
                        Text(task)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.ink(0.7))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    buttons(for: focus)
                }
            } else if let focus = source.focus(), !focus.enabled {
                placeholder("Mia's focus timer is switched off in its Settings → Extensions.", action: nil)
            } else if source.miaInstalled() {
                startCard
            } else {
                placeholder("The focus timer comes from Mia, which isn't on this Mac.", action: nil)
            }
        }
    }

    private func focusHeading(_ focus: MiaFocus) -> String {
        switch focus.state {
        case .idle: return "Focus"
        case .done: return "\(focus.phase.title) done"
        case .running, .paused:
            let round = focus.phase == .focus && focus.round > 0 ? " · round \(focus.round) of \(focus.rounds)" : ""
            return focus.phase.title + (focus.isPaused ? " · paused" : "") + round
        }
    }

    @ViewBuilder
    private func buttons(for focus: MiaFocus) -> some View {
        HStack(spacing: 2) {
            switch focus.state {
            case .idle:
                TrayIconButton(symbol: "play.fill", title: "Start focus", size: 26) { source.startFocus() }
            case .done:
                TrayIconButton(symbol: "play.fill", title: "Start the next period", size: 26) { source.startFocus() }
                TrayIconButton(symbol: "stop.fill", title: "Stop", size: 26) { source.focusCommand(.stop) }
            case .running:
                TrayIconButton(symbol: "pause.fill", title: "Pause", size: 26) { source.focusCommand(.pause) }
                TrayIconButton(symbol: "forward.end.fill", title: "Skip", size: 26) { source.focusCommand(.skip) }
                TrayIconButton(symbol: "stop.fill", title: "Stop", size: 26) { source.focusCommand(.stop) }
            case .paused:
                TrayIconButton(symbol: "play.fill", title: "Resume", size: 26) { source.focusCommand(.resume) }
                TrayIconButton(symbol: "forward.end.fill", title: "Skip", size: 26) { source.focusCommand(.skip) }
                TrayIconButton(symbol: "stop.fill", title: "Stop", size: 26) { source.focusCommand(.stop) }
            }
        }
    }

    /// Mia isn't running (or hasn't said anything): Start opens it in the background and starts the timer.
    @ViewBuilder
    private var startCard: some View {
        switch source.focusStarting() {
        case .waiting:
            VStack(alignment: .leading, spacing: 6) {
                Text("Focus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.ink(0.55))
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Starting Mia…")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.ink(0.7))
                }
                Spacer(minLength: 0)
            }
        case .noAnswer:
            placeholder(
                "Mia didn't answer. It needs its latest build to take orders from Cue.",
                action: ("Open Mia", source.openMia)
            )
        case .none:
            VStack(alignment: .leading, spacing: 6) {
                Text("Focus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.ink(0.55))
                Text("Ready")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.primaryInk)
                Text("Mia runs the timer; it opens in the background.")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.ink(0.7))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                TrayIconButton(symbol: "play.fill", title: "Start focus", size: 26) { source.startFocus() }
            }
        }
    }

    // MARK: Hours

    @ViewBuilder
    private var focusedCard: some View {
        TodayCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Focused today")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.ink(0.55))
                Text(MiaFocus.hours(source.focus()?.today ?? 0))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(palette.primaryInk)
                Spacer(minLength: 0)
                WeekBars(minutes: source.focus()?.week ?? [])
            }
        }
    }

    private func placeholder(_ words: String, action: (String, () -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Focus")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.ink(0.55))
            Text(words)
                .font(.system(size: 12))
                .foregroundStyle(palette.ink(0.7))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(TrayButtonStyle())
                    .font(.system(size: 12, weight: .medium))
            }
        }
    }
}

/// A rounded tile on the shelf, the island's own card.
private struct TodayCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    @Environment(\.trayPalette) private var palette

    var body: some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(palette.controlFill(selected: false), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// How far through the working day it is: a slim bar, and the words for it.
struct DayBar: View {
    let workday: Workday
    let now: Date

    @Environment(\.trayPalette) private var palette

    var body: some View {
        let progress = workday.progress(at: now)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Today")
                    .foregroundStyle(palette.ink(0.55))
                Spacer()
                Text(words(progress))
                    .foregroundStyle(palette.ink(0.7))
                    .monospacedDigit()
            }
            .font(.system(size: 11, weight: .medium))

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.controlFill(selected: true))
                    Capsule()
                        .fill(Color.green.opacity(0.85))
                        .frame(width: proxy.size.width * fraction(progress))
                }
            }
            .frame(height: 5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today, \(words(progress))")
    }

    private func fraction(_ progress: Workday.Progress) -> Double {
        switch progress {
        case .before: 0
        case .during(let fraction, _): fraction
        case .after: 1
        }
    }

    private func words(_ progress: Workday.Progress) -> String {
        switch progress {
        case .before(let starts): "Starts at \(Workday.time(starts))"
        case .during(let fraction, let ends): "\(Int((fraction * 100).rounded(.down)))% of your day · ends \(Workday.time(ends))"
        case .after: "Your day is done"
        }
    }
}

/// Minutes focused each day this week, Monday first, today's bar lit.
private struct WeekBars: View {
    let minutes: [Int]

    @Environment(\.trayPalette) private var palette

    var body: some View {
        let days = minutes.count == 7 ? minutes : Array(repeating: 0, count: 7)
        let most = max(days.max() ?? 0, 60)
        let today = (Calendar.current.component(.weekday, from: Date()) + 5) % 7
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<7, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(index == today ? Color.green.opacity(0.85) : palette.ink(0.25))
                    .frame(width: 8, height: max(3, 26 * CGFloat(days[index]) / CGFloat(most)))
            }
        }
        .frame(height: 26, alignment: .bottom)
        .accessibilityHidden(true)
    }
}
