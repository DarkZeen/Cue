import Foundation
import Testing

@testable import Cue

/// Mia's focus state as Cue reads it, and the working day the Today page measures.
struct MiaFocusTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func aRunningPeriodCountsDownFromItsEnd() throws {
        let focus = try #require(MiaFocus(payload: [
            "v": 1, "enabled": true, "phase": "focus", "state": "running",
            "endsAt": now.addingTimeInterval(600).timeIntervalSince1970,
            "length": 25, "round": 2, "rounds": 4, "task": "Write the README",
            "today": 75, "week": [30, 0, 75, 0, 0, 0, 0],
        ]))
        #expect(focus.isActive)
        #expect(!focus.isPaused)
        #expect(focus.left(at: now) == 600)
        #expect(abs(focus.progress(at: now) - 0.6) < 0.0001)
        #expect(focus.task == "Write the README")
        #expect(focus.today == 75)
        #expect(focus.week.count == 7)
    }

    @Test func aPausedPeriodHoldsWhatIsLeft() throws {
        let focus = try #require(MiaFocus(payload: [
            "v": 1, "phase": "shortBreak", "state": "paused", "left": 90, "length": 5,
        ]))
        #expect(focus.isActive)
        #expect(focus.isPaused)
        #expect(focus.left(at: now) == 90)
        #expect(focus.left(at: now.addingTimeInterval(3600)) == 90)
        #expect(focus.phase.isBreak)
    }

    @Test func aSwitchedOffTimerIsNeverActive() throws {
        let focus = try #require(MiaFocus(payload: [
            "v": 1, "enabled": false, "phase": "focus", "state": "paused", "left": 90, "length": 25,
        ]))
        #expect(!focus.isActive)
    }

    @Test func aBreakCarriesItsExercise() throws {
        let focus = try #require(MiaFocus(payload: [
            "v": 1, "phase": "shortBreak", "state": "running", "endsAt": now.addingTimeInterval(600).timeIntervalSince1970,
            "length": 15,
            "exercise": ["name": "Push-ups", "amount": "20 reps", "step": 1, "steps": 2, "done": false,
                         "picture": "/tmp/files/ab/abc"] as [String: Any],
        ]))
        #expect(focus.exercise == MiaFocus.Exercise(name: "Push-ups", amount: "20 reps", step: 1, steps: 2, done: false,
                                                    picture: URL(fileURLWithPath: "/tmp/files/ab/abc")))
    }

    @Test func anExerciseWithoutAPictureStillShows() throws {
        let focus = try #require(MiaFocus(payload: [
            "v": 1, "phase": "shortBreak", "state": "paused", "left": 90, "length": 15,
            "exercise": ["name": "Plank", "amount": "60 s", "step": 2, "steps": 2, "done": false] as [String: Any],
        ]))
        #expect(focus.exercise?.picture == nil && focus.exercise?.name == "Plank")
        #expect(try #require(MiaFocus(payload: ["v": 1, "phase": "focus", "state": "idle"])).exercise == nil)
    }

    @Test func somethingElseIsNotAPayload() {
        #expect(MiaFocus(payload: nil) == nil)
        #expect(MiaFocus(payload: ["v": 2, "phase": "focus", "state": "idle"]) == nil)
        #expect(MiaFocus(payload: ["v": 1, "phase": "nap", "state": "idle"]) == nil)
        // Running needs its end.
        #expect(MiaFocus(payload: ["v": 1, "phase": "focus", "state": "running"]) == nil)
    }

    @Test func clocksAndHours() {
        #expect(MiaFocus.clock(1450) == "24:10")
        #expect(MiaFocus.clock(3900) == "1:05:00")
        #expect(MiaFocus.clock(-5) == "0:00")
        #expect(MiaFocus.hours(45) == "45m")
        #expect(MiaFocus.hours(185) == "3h 05m")
    }
}

struct WorkdayTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func at(_ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: hour, minute: minute))!
    }

    @Test func beforeDuringAndAfter() {
        let day = Workday.standard
        #expect(day.progress(at: at(8, 30), calendar: calendar) == .before(starts: 540))
        #expect(day.progress(at: at(13, 30), calendar: calendar) == .during(fraction: 0.5, ends: 1080))
        #expect(day.progress(at: at(18, 0), calendar: calendar) == .after)
    }

    @Test func aDayThatEndsBeforeItStartsHasNothingToMeasure() {
        #expect(Workday(start: 600, end: 600).progress(at: at(12, 0), calendar: calendar) == .after)
    }
}

/// Starting Mia's timer from Cue.
@MainActor
struct MiaFocusStartTests {
    private func link(_ focus: MiaFocus?) -> (MiaFocusLink, () -> [MiaFocusLink.Command]) {
        let link = MiaFocusLink()
        var sent: [MiaFocusLink.Command] = []
        link.sendOverride = { sent.append($0) }
        link.received(focus)
        return (link, { sent })
    }

    @Test func startIsTheTimersOwnStartNextOrResume() {
        for (state, expected) in [
            (MiaFocus.State.idle, [MiaFocusLink.Command.start]),
            (.done, [.next]),
            (.paused(left: 60), [.resume]),
            (.running(endsAt: .distantFuture), []),
        ] {
            let (link, sent) = link(MiaFocus(phase: .focus, state: state, length: 25))
            link.startFocus()
            #expect(sent() == expected)
        }
    }

    @Test func aSwitchedOffTimerIsLeftAlone() {
        let (link, sent) = link(MiaFocus(enabled: false, phase: .idle, state: .idle, length: 25))
        link.startFocus()
        #expect(sent().isEmpty)
        #expect(link.menuTitle == nil)
    }

    @Test func theMenuSaysWhatItWillDo() {
        #expect(link(MiaFocus(phase: .idle, state: .idle, length: 25)).0.menuTitle == "Start Focus")
        #expect(link(MiaFocus(phase: .focus, state: .running(endsAt: .distantFuture), length: 25)).0.menuTitle == "Pause Focus")
        #expect(link(MiaFocus(phase: .focus, state: .paused(left: 5), length: 25)).0.menuTitle == "Resume Focus")
        #expect(link(MiaFocus(phase: .focus, state: .done, length: 25)).0.menuTitle == "Start Break")
    }

    @Test func theMenuPausesARunningPeriod() {
        let (link, sent) = link(MiaFocus(phase: .focus, state: .running(endsAt: .distantFuture), length: 25))
        link.performMenuAction()
        #expect(sent() == [.pause])
    }
}

/// The Numerals page: what it says and what a click does and which controls show, in every state.
struct TodayFaceTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: hour, minute: minute))!
    }

    private func face(_ focus: MiaFocus?, at date: Date, starting: MiaFocusLink.Starting = .none,
                      installed: Bool = true) -> TodayFace {
        TodayFace(focus: focus, starting: starting, miaInstalled: installed, workday: .standard, now: date,
                  calendar: calendar)
    }

    @Test func focusingCountsDownInAmberWithTheDayBeside() {
        let now = at(13, 30)
        let face = face(MiaFocus(phase: .focus, state: .running(endsAt: now.addingTimeInterval(924)), length: 25,
                                 round: 2, task: "Write the README"), at: now)
        #expect(face.big == "15:24")
        #expect(face.bigTone == .focus)
        #expect(face.caption == "Write the README")
        #expect(face.side == "50%")
        #expect(PixelFont.canDraw(face.side))
        #expect(face.click == .command(.pause, title: "Pause"))
        #expect(face.controls.map(\.symbol) == ["pause.fill", "forward.end.fill", "stop.fill"])
        #expect(face.footer == .rounds([.done, .current, .ahead, .ahead]))
    }

    @Test func aBreakTurnsTheSideToWhatYouveDone() {
        let now = at(15)
        let face = face(MiaFocus(phase: .shortBreak, state: .running(endsAt: now.addingTimeInterval(252)), length: 5,
                                 round: 2, today: 130), at: now)
        #expect(face.bigTone == .plain)
        #expect(face.side == "2h 10m")
        #expect(face.sideCaption == "focused today")
        #expect(face.controls.contains(.command(.skip, title: "Skip the break")))
        #expect(face.footer == .rounds([.done, .done, .rest, .ahead]))
    }

    @Test func aBreakWithAnExerciseOffersDone() {
        let now = at(13, 30)
        var focus = MiaFocus(phase: .shortBreak, state: .running(endsAt: now.addingTimeInterval(600)), length: 15)
        focus.exercise = MiaFocus.Exercise(name: "Push-ups", amount: "20 reps", step: 1, steps: 2, done: false, picture: nil)
        let face = face(focus, at: now)
        #expect(face.exercise?.name == "Push-ups")
        #expect(face.caption == "Push-ups · 20 reps · 1 of 2")
        #expect(face.controls.first == .command(.next, title: "Done"))
        #expect(face.controls.contains(.command(.stop, title: "Stop")))
        #expect(face.click == .command(.pause, title: "Pause"))      // a click pauses, as in any break
    }

    @Test func aFinishedRoutineSaysSo() {
        let now = at(13, 30)
        var focus = MiaFocus(phase: .shortBreak, state: .running(endsAt: now.addingTimeInterval(600)), length: 15)
        focus.exercise = MiaFocus.Exercise(name: "Plank", amount: "60 s", step: 2, steps: 2, done: true, picture: nil)
        #expect(face(focus, at: now).caption == "Routine done ✓")
    }

    @Test func aPausedBreakWithAnExerciseOffersResume() {
        let now = at(13, 30)
        var focus = MiaFocus(phase: .longBreak, state: .paused(left: 300), length: 15)
        focus.exercise = MiaFocus.Exercise(name: "Plank", amount: "60 s", step: 2, steps: 2, done: false, picture: nil)
        let face = face(focus, at: now)
        #expect(face.controls == [.command(.next, title: "Done"), .command(.resume, title: "Resume"),
                                  .command(.stop, title: "Stop")])
        #expect(face.bigTone == .dim)
        #expect(face.click == .command(.resume, title: "Resume"))
        #expect(face.caption == "Paused · Plank · 60 s · 2 of 2")
    }

    @Test func readyShowsThePeriodDimmedAndStarts() {
        let face = face(MiaFocus(phase: .idle, state: .idle, length: 25), at: at(10))
        #expect(face.big == "25:00")
        #expect(face.bigTone == .dim)
        #expect(face.click == .start)
        #expect(face.controls == [.start])
    }

    @Test func afterHoursTheTotalIsTheNumber() {
        let face = face(MiaFocus(phase: .idle, state: .idle, length: 25, today: 275, week: [1, 2, 3, 275, 0, 0, 0]),
                        at: at(19))
        #expect(face.big == "4h 35m")
        #expect(face.side == "Done")
        #expect(face.footer == .week([1, 2, 3, 275, 0, 0, 0]))
        #expect(face.click == .start)
    }

    @Test func withoutMiasStateAClickStartsIt() {
        #expect(face(nil, at: at(10)).click == .start)
        #expect(face(nil, at: at(10), starting: .waiting).click == nil)
        #expect(face(nil, at: at(10), starting: .noAnswer).click == .openMia)
        #expect(face(nil, at: at(10), installed: false).click == nil)
    }
}

/// The Today page's pixel look: the SmallTV digits, the minute field, the label and the hairline.
struct TodayPixelTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func face(_ focus: MiaFocus) -> TodayFace {
        TodayFace(focus: focus, starting: .none, miaInstalled: true, workday: .standard, now: now)
    }

    @Test func clocksDrawInPixelsAndWordsDoNot() {
        #expect(PixelFont.canDraw("18:42"))
        #expect(PixelFont.canDraw("1:05:00"))
        #expect(!PixelFont.canDraw("Focus"))
        #expect(!PixelFont.canDraw("—"))
        #expect(!PixelFont.canDraw(""))
        #expect(PixelFont.canDraw("94%"))
        // Five columns a digit, one for the colon, a gap between each.
        #expect(PixelFont.columns("18:42") == 5 * 4 + 1 + 4)
    }

    @Test func everyGlyphIsSevenRowsOfEvenWidth() {
        for (_, rows) in PixelFont.glyphs {
            #expect(rows.count == 7)
            #expect(Set(rows.map(\.count)).count == 1)
        }
    }

    @Test func aRunningRoundHasItsLabelSquaresAndHairline() {
        let focus = MiaFocus(phase: .focus, state: .running(endsAt: now.addingTimeInterval(600)), length: 25,
                             round: 2, task: "Write the README")
        let face = face(focus)
        #expect(face.label == "FOCUS · 2 OF 4")
        #expect(face.field?.count == 25)
        #expect(abs((face.field?.gone ?? 0) - 15) < 0.001)
        #expect(face.fieldTone == .focus)
    }

    @Test func aPausedBreakSaysSoAndGoesGrey() {
        let focus = MiaFocus(phase: .shortBreak, state: .paused(left: 120), length: 5, round: 1)
        let face = face(focus)
        #expect(face.label == "PAUSED · BREAK · 1 OF 4")
        #expect(face.field?.count == 5)
        #expect(face.fieldTone == .dim)
    }

    @Test func noPeriodMeansNoField() {
        let face = face(MiaFocus(phase: .idle, state: .idle, length: 25))
        #expect(face.label == nil)
        #expect(face.field == nil)
    }

    @Test func theDayIsAPercentageThePixelsCanDraw() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let noon = calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 13, minute: 30))!
        let face = TodayFace(focus: nil, starting: .none, miaInstalled: true, workday: .standard, now: noon,
                             calendar: calendar)
        #expect(face.side == "50%")
        #expect(PixelFont.canDraw(face.side))
    }

    @Test func aLongPeriodStillFitsTwentyFiveSquares() {
        let face = face(MiaFocus(phase: .focus, state: .running(endsAt: now.addingTimeInterval(3000)), length: 60))
        #expect(face.field?.count == 25)
    }

    @Test func theEmptyingSquareDithersByLevel() {
        let lit = { (level: Double) in (0..<64).filter { OrderedDither.isLit(column: $0 % 8, row: $0 / 8, level: level) }.count }
        #expect(lit(0) == 0)
        #expect(lit(0.5) == 32)
        #expect(lit(1) == 64)
    }
}
