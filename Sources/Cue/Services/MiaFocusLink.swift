import AppKit
import Observation
import OSLog

/// Mia's focus timer, as Mia tells it.
///
/// Mia keeps the timer — it syncs to the iPhone and counts the focus hours — and posts its state on the Mac's
/// distributed notifications whenever it changes (Mia's `FocusBridge`). This is that state as plain values,
/// with the countdown worked out here from the end time, so it moves every second without Mia posting every
/// second.
nonisolated struct MiaFocus: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case idle
        case running(endsAt: Date)
        case paused(left: Int)
        case done
    }

    enum Phase: String, Sendable {
        case idle, focus, shortBreak, longBreak

        var title: String {
            switch self {
            case .idle, .focus: "Focus"
            case .shortBreak: "Break"
            case .longBreak: "Long break"
            }
        }

        var isBreak: Bool { self == .shortBreak || self == .longBreak }
    }

    var enabled: Bool
    var phase: Phase
    var state: State
    /// The period's length, in minutes.
    var length: Int
    var round: Int
    var rounds: Int
    var task: String?
    /// Minutes focused today, and on each day this week, Monday first.
    var today: Int
    var week: [Int]

    /// A running or paused period: something the notch and the shelf show.
    var isActive: Bool {
        guard enabled else { return false }
        switch state {
        case .running, .paused: return true
        case .idle, .done: return false
        }
    }

    var isPaused: Bool {
        if case .paused = state { return true }
        return false
    }

    /// Seconds left at `now`.
    func left(at now: Date) -> Int {
        switch state {
        case .running(let endsAt): max(0, Int(endsAt.timeIntervalSince(now).rounded(.up)))
        case .paused(let left): max(0, left)
        case .idle: length * 60
        case .done: 0
        }
    }

    /// How much of the period is gone at `now`, 0 to 1.
    func progress(at now: Date) -> Double {
        guard length > 0 else { return 0 }
        return min(1, max(0, 1 - Double(left(at: now)) / Double(length * 60)))
    }

    /// "24:10", or "1:05:00" for a period over an hour.
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// "3h 05m", "45m", "0m".
    static func hours(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes)m" : String(format: "%dh %02dm", minutes / 60, minutes % 60)
    }

    /// Reads Mia's payload (`FocusBridge.payload` in Mia). Nil for anything that is not one.
    init?(payload: [AnyHashable: Any]?) {
        guard let payload, payload["v"] as? Int == 1,
              let phase = (payload["phase"] as? String).flatMap(Phase.init(rawValue:)),
              let state = payload["state"] as? String
        else { return nil }

        switch state {
        case "running":
            guard let endsAt = payload["endsAt"] as? Double else { return nil }
            self.state = .running(endsAt: Date(timeIntervalSince1970: endsAt))
        case "paused":
            self.state = .paused(left: payload["left"] as? Int ?? 0)
        case "done":
            self.state = .done
        default:
            self.state = .idle
        }
        self.phase = phase
        enabled = payload["enabled"] as? Bool ?? true
        length = payload["length"] as? Int ?? 0
        round = payload["round"] as? Int ?? 0
        rounds = payload["rounds"] as? Int ?? 4
        task = payload["task"] as? String
        today = payload["today"] as? Int ?? 0
        week = payload["week"] as? [Int] ?? []
    }

    init(enabled: Bool = true, phase: Phase, state: State, length: Int, round: Int = 1, rounds: Int = 4,
         task: String? = nil, today: Int = 0, week: [Int] = []) {
        self.enabled = enabled
        self.phase = phase
        self.state = state
        self.length = length
        self.round = round
        self.rounds = rounds
        self.task = task
        self.today = today
        self.week = week
    }
}

/// Listens to Mia's focus timer and works its buttons.
///
/// Asks for the state when Cue starts and whenever Mia launches, forgets it when Mia quits, and sends what the
/// shelf's and the notch's buttons ask for. Nothing here touches the network or brings Mia forward.
@MainActor
@Observable
final class MiaFocusLink {
    /// The timer, while Mia is running and has said; otherwise nil.
    private(set) var focus: MiaFocus?

    nonisolated static let miaBundleID = "com.darkzeen.mia"

    // The names Mia's `FocusBridge` uses.
    static let stateName = Notification.Name("com.darkzeen.mia.focus.state")
    static let requestName = Notification.Name("com.darkzeen.mia.focus.request")
    static let commandName = Notification.Name("com.darkzeen.mia.focus.command")

    enum Command: String {
        case start, pause, resume, skip, stop, next
    }

    /// A start asked for before Mia could take it: Mia was not running, or had not said anything yet.
    enum Starting: Equatable {
        case none
        /// Mia is opening (in the background) or was asked; the start goes once it answers.
        case waiting
        /// Mia never answered: it is a build without the bridge, or it could not open.
        case noAnswer
    }

    private(set) var starting: Starting = .none

    /// How long to wait for Mia to open and answer before saying it did not.
    @ObservationIgnored var answerTimeout: Duration = .seconds(15)

    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var startTimeout: Task<Void, Never>?
    @ObservationIgnored private let logger = Diagnostics.logger("mia-focus")

    func start() {
        guard observers.isEmpty else { return }
        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(forName: Self.stateName, object: nil, queue: .main) { [weak self] note in
            let focus = MiaFocus(payload: note.userInfo)
            MainActor.assumeIsolated { self?.received(focus) }
        })

        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard Self.isMia(note) else { return }
            // A moment for Mia to load its session before it can answer.
            MainActor.assumeIsolated {
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    self?.request()
                }
            }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard Self.isMia(note) else { return }
            MainActor.assumeIsolated { self?.focus = nil }
        })
        request()
    }

    /// What Mia said, and the start that was waiting for it.
    func received(_ focus: MiaFocus?) {
        self.focus = focus
        guard starting != .none, let focus else { return }
        startTimeout?.cancel()
        starting = .none
        if focus.enabled { begin(focus) }
    }

    /// Starts a focus period from Cue, whatever Mia is doing.
    ///
    /// With Mia running and answering, this is the timer's own Start (or Next, after a period ends, or
    /// Resume while paused). Without it, Cue opens Mia hidden — its window stays put — and sends the start
    /// once Mia has said its state; `starting` tells the shelf it is on its way, or that Mia never answered.
    func startFocus() {
        if let focus {
            if focus.enabled { begin(focus) }
            return
        }
        guard isMiaInstalled else { return }
        starting = .waiting
        if isMiaRunning {
            request()
        } else {
            launchMia(hidden: true)
        }
        startTimeout?.cancel()
        let timeout = answerTimeout
        startTimeout = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self, self.starting == .waiting else { return }
            self.starting = .noAnswer
        }
    }

    private func begin(_ focus: MiaFocus) {
        switch focus.state {
        case .idle: send(.start)
        case .done: send(.next)
        case .paused: send(.resume)
        case .running: break
        }
    }

    /// The menu bar's focus item: what it says, or nil to leave it out.
    var menuTitle: String? {
        guard let focus else { return isMiaInstalled ? "Start Focus" : nil }
        guard focus.enabled else { return nil }
        switch focus.state {
        case .idle: return "Start Focus"
        case .done: return focus.phase == .focus ? "Start Break" : "Start Focus"
        case .running: return "Pause Focus"
        case .paused: return "Resume Focus"
        }
    }

    func performMenuAction() {
        if let focus, case .running = focus.state {
            send(.pause)
        } else {
            startFocus()
        }
    }

    /// Asks Mia to say its state again.
    func request() {
        DistributedNotificationCenter.default().postNotificationName(Self.requestName, object: nil, userInfo: nil, deliverImmediately: true)
    }

    /// Where commands go instead of Mia, for tests.
    @ObservationIgnored var sendOverride: ((Command) -> Void)?

    func send(_ command: Command) {
        if let sendOverride { return sendOverride(command) }
        logger.debug("Asking Mia to \(command.rawValue, privacy: .public).")
        DistributedNotificationCenter.default().postNotificationName(
            Self.commandName, object: nil, userInfo: ["action": command.rawValue], deliverImmediately: true
        )
    }

    /// Whether Mia is on this Mac at all.
    var isMiaInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.miaBundleID) != nil
    }

    var isMiaRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.miaBundleID).isEmpty
    }

    func openMia() {
        launchMia(hidden: false)
    }

    private func launchMia(hidden: Bool) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.miaBundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = hidden
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    private nonisolated static func isMia(_ note: Notification) -> Bool {
        (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == miaBundleID
    }
}
