import SwiftUI

/// The open shelf's second page, as numerals: the one number that matters now, large, and the day beside it.
///
/// No buttons. The big number is the countdown while a period runs (white, as the Lock Screen's clock is),
/// the period's length while the timer is ready, and the day's focused total once the working day is over.
/// The small number on the right is the day: how much of it is gone, or what you have focused, or when it
/// starts again. The whole page is the control — a click starts, pauses, resumes or skips, a hold stops —
/// which keeps it as quiet as the pill it opens out of. Mia keeps the timer (`MiaFocusLink`); type is Mia's
/// own (`CueType`).
struct TodayPage: View {
    let source: NowPlayingSource

    @Environment(\.trayPalette) private var palette
    @State private var isHovering = false
    @State private var isPressing = false

    var body: some View {
        // Once a second for the countdown and the day; nothing else here moves.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let face = TodayFace(
                focus: source.focus(),
                starting: source.focusStarting(),
                miaInstalled: source.miaInstalled(),
                workday: source.workday(),
                now: context.date
            )
            content(face)
                .contentShape(.rect)
                .onTapGesture { perform(face.click) }
                .onLongPressGesture(minimumDuration: 0.6) {
                    perform(face.hold)
                } onPressingChanged: { pressing in
                    isPressing = pressing && face.hold != nil
                }
                .onHover { isHovering = $0 }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(face.accessibilityLabel)
                .accessibilityActions {
                    if let click = face.click {
                        Button(click.title) { perform(click) }
                    }
                    if let hold = face.hold {
                        Button(hold.title) { perform(hold) }
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func content(_ face: TodayFace) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(face.big)
                        .font(CueType.numerals(36))
                        .foregroundStyle(colour(face.bigTone))
                        .contentTransition(.numericText(countsDown: true))
                        .scaleEffect(isPressing ? 0.96 : 1, anchor: .leading)
                        .animation(.easeOut(duration: 0.6), value: isPressing)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(face.caption)
                        .font(CueType.body(11))
                        .foregroundStyle(palette.ink(0.55))
                        .lineLimit(1)
                }
                Spacer(minLength: 16)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(face.side)
                        .font(CueType.numerals(19))
                        .foregroundStyle(colour(face.sideTone))
                        .lineLimit(1)
                    Text(face.sideCaption)
                        .font(CueType.body(11))
                        .foregroundStyle(palette.ink(0.55))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            HStack(alignment: .bottom) {
                footer(face)
                Spacer(minLength: 16)
                if let hint = face.hint {
                    Text(hint)
                        .font(CueType.label(11))
                        .foregroundStyle(palette.ink(isHovering ? 0.6 : 0.35))
                        .animation(.easeOut(duration: 0.15), value: isHovering)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
    }

    @ViewBuilder
    private func footer(_ face: TodayFace) -> some View {
        switch face.footer {
        case .rounds(let dots):
            HStack(spacing: 6) {
                ForEach(dots.indices, id: \.self) { index in
                    Circle()
                        .fill(dotColour(dots[index]))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityHidden(true)
        case .week(let minutes):
            WeekBars(minutes: minutes)
        case .none:
            EmptyView()
        }
    }

    private func perform(_ action: TodayFace.Action?) {
        switch action {
        case .command(let command, _): source.focusCommand(command)
        case .start: source.startFocus()
        case .openMia: source.openMia()
        case nil: break
        }
    }

    private func colour(_ tone: TodayFace.Tone) -> Color {
        switch tone {
        case .focus, .plain: palette.primaryInk
        case .rest: .green
        case .dim: palette.ink(0.4)
        }
    }

    private func dotColour(_ dot: TodayFace.Dot) -> Color {
        switch dot {
        case .done: .orange
        case .current: .orange.opacity(0.5)
        case .rest: .green
        case .ahead: palette.ink(0.2)
        }
    }
}

/// What the page says at one moment: the numbers, their words and tones, and what a click and a hold do.
///
/// Worked out here, away from the view, so every state can be tested without drawing anything.
struct TodayFace: Equatable {
    enum Tone: Equatable { case focus, rest, plain, dim }
    enum Dot: Equatable { case done, current, rest, ahead }
    enum Footer: Equatable { case rounds([Dot]), week([Int]), none }

    enum Action: Equatable {
        case command(MiaFocusLink.Command, title: String)
        case start
        case openMia

        var title: String {
            switch self {
            case .command(_, let title): title
            case .start: "Start focus"
            case .openMia: "Open Mia"
            }
        }
    }

    var big: String
    var bigTone: Tone
    var caption: String
    var side: String
    var sideTone: Tone
    var sideCaption: String
    var footer: Footer
    var hint: String?
    var click: Action?
    var hold: Action?

    var accessibilityLabel: String {
        "\(caption), \(big). \(sideCaption), \(side)."
    }

    init(focus: MiaFocus?, starting: MiaFocusLink.Starting, miaInstalled: Bool, workday: Workday, now: Date,
         calendar: Calendar = .current) {
        let day = workday.progress(at: now, calendar: calendar)
        let today = focus?.today ?? 0

        // The right-hand number: the day.
        switch day {
        case .before(let starts):
            side = Workday.time(starts, calendar: calendar); sideTone = .plain; sideCaption = "your day starts"
        case .during(let fraction, _):
            side = "\(Int((fraction * 100).rounded(.down)))%"; sideTone = .rest; sideCaption = "of your day"
        case .after:
            side = "Done"; sideTone = .dim; sideCaption = "see you at \(Workday.time(workday.start, calendar: calendar))"
        }

        footer = .none
        hint = nil
        click = nil
        hold = nil

        guard let focus, focus.enabled else {
            // No timer to show: Mia isn't answering, is switched off, or isn't here.
            bigTone = .dim
            if let focus, !focus.enabled {
                big = MiaFocus.hours(today); caption = "Mia's focus timer is switched off"
            } else if !miaInstalled {
                big = "—"; caption = "The focus timer comes from Mia"
            } else {
                switch starting {
                case .waiting:
                    big = "…"; caption = "Starting Mia"
                case .noAnswer:
                    big = "—"; caption = "Mia didn't answer. It needs its latest build."
                    hint = "click to open Mia"; click = .openMia
                case .none:
                    big = "Focus"; bigTone = .plain; caption = "Mia opens in the background"
                    hint = "click to start"; click = .start
                }
            }
            return
        }

        let rounds = Self.dots(focus)
        switch focus.state {
        case .running:
            big = MiaFocus.clock(focus.left(at: now))
            if focus.phase.isBreak {
                bigTone = .plain
                caption = focus.phase.title
                // On a break the right-hand side turns to what you've done.
                side = MiaFocus.hours(today); sideTone = .plain; sideCaption = "focused today"
                hint = "click to skip · hold to stop"
                click = .command(.skip, title: "Skip the break")
            } else {
                bigTone = .focus
                caption = focus.task ?? "Focus · round \(focus.round) of \(focus.rounds)"
                hint = "click to pause · hold to stop"
                click = .command(.pause, title: "Pause")
            }
            hold = .command(.stop, title: "Stop")
            footer = .rounds(rounds)
        case .paused:
            big = MiaFocus.clock(focus.left(at: now)); bigTone = .dim
            caption = "Paused" + (focus.task.map { " · \($0)" } ?? "")
            hint = "click to resume · hold to stop"
            click = .command(.resume, title: "Resume")
            hold = .command(.stop, title: "Stop")
            footer = .rounds(rounds)
        case .done:
            big = "0:00"; bigTone = .dim
            caption = "\(focus.phase.title) done"
            hint = focus.phase == .focus ? "click for a break · hold to stop" : "click to focus · hold to stop"
            click = .command(.next, title: focus.phase == .focus ? "Start the break" : "Start focus")
            hold = .command(.stop, title: "Stop")
            footer = .rounds(rounds)
        case .idle:
            if case .after = day {
                // The working day is over: what it came to is the number now.
                big = MiaFocus.hours(today); bigTone = .plain
                caption = "focused today"
                hint = "click to start anyway"
                footer = .week(focus.week)
            } else {
                big = MiaFocus.clock(focus.length * 60); bigTone = .dim
                caption = focus.task ?? "Ready to focus"
                hint = "click to start"
                footer = .rounds(rounds)
            }
            click = .start
        }
    }

    /// The cycle's rounds: finished ones lit, the one under way half-lit, a break green.
    static func dots(_ focus: MiaFocus) -> [Dot] {
        let count = max(1, focus.rounds)
        let active = focus.isActive || focus.state == .done
        // During or after a break the round it followed is finished; during a focus round, the ones before it.
        let finished: Int
        if !active || focus.phase == .idle {
            finished = 0
        } else if focus.phase.isBreak || focus.state == .done {
            finished = min(count, focus.round)
        } else {
            finished = min(count, max(0, focus.round - 1))
        }
        return (0..<count).map { index in
            if index < finished { return .done }
            if active, index == finished {
                if focus.phase.isBreak, focus.state != .done { return .rest }
                if focus.phase == .focus, focus.state != .done { return .current }
            }
            return .ahead
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
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(index == today ? Color.green : palette.ink(0.25))
                    .frame(width: 5, height: max(2, 18 * CGFloat(days[index]) / CGFloat(most)))
            }
        }
        .frame(height: 18, alignment: .bottom)
        .accessibilityHidden(true)
    }
}
