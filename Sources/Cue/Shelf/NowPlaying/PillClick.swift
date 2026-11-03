import AppKit
import SwiftUI

/// Tells one click from two on the now-playing wings.
///
/// The mark does two things: one click plays or pauses, two skip. A single
/// click therefore cannot act the moment it lands, or the first half of every
/// double click would pause the track the second half then skips. It waits
/// out a short window instead, and a second click inside that window cancels
/// it and fires the double.
///
/// Kept apart from the view that receives the events, with time handed in and
/// actions handed back, in the same shape as `OtherAudioPolicy`: the rules are
/// the part worth testing, and a view cannot be fed clicks at chosen moments.
struct ClickArbiter {
    enum Action: Equatable {
        case single
        case double
    }

    /// How long a single click waits for a second one.
    ///
    /// The system's double-click interval, but never more than 0.3s. Someone
    /// who set a slow double click so they could manage one has not asked for
    /// play and pause to lag by most of a second; a double click slower than
    /// this still reaches `.double` (see `click(count:at:)`), it just no
    /// longer stops the single from having happened first.
    var window: TimeInterval

    /// Whether a lone click does anything here. The cover's does not, so it
    /// has nothing to wait for and its double fires as soon as AppKit counts
    /// two.
    var handlesSingle: Bool

    /// When the waiting single click is due, if there is one.
    private(set) var deadline: TimeInterval?

    init(window: TimeInterval, handlesSingle: Bool = true) {
        self.window = window
        self.handlesSingle = handlesSingle
    }

    /// The window the wings use, read from the user's own setting.
    static var systemWindow: TimeInterval {
        min(NSEvent.doubleClickInterval, 0.3)
    }

    /// A click finished. `count` is AppKit's own count for it — 1, then 2 for
    /// a second click inside the system's interval, and so on.
    ///
    /// Returns what to do now. A single click returns nothing and starts the
    /// window; the caller asks `tick(at:)` again once `deadline` passes.
    mutating func click(count: Int, at now: TimeInterval) -> Action? {
        switch count {
        case ...1:
            guard handlesSingle else { return nil }
            // A second click AppKit did not count as one — the pointer moved
            // too far, say. Whatever was waiting is its own click and goes
            // now, rather than being lost under this one.
            let earlier: Action? = deadline == nil ? nil : .single
            deadline = now + window
            return earlier

        case 2:
            // Inside the window: the waiting single is cancelled and never
            // fires. Outside it the single has already happened, and the
            // double fires anyway — undoing a pause half a second later would
            // be stranger than a pause followed by a skip.
            deadline = nil
            return .double

        default:
            // A third click is a double click with a stutter. Acting on it —
            // as a second skip, or as a play/pause after the skip — would do
            // something nobody aimed for.
            deadline = nil
            return nil
        }
    }

    /// Time passed. Returns the waiting single click once it is due.
    mutating func tick(at now: TimeInterval) -> Action? {
        guard let due = deadline, now >= due else { return nil }
        deadline = nil
        return .single
    }

    /// Forgets anything waiting — the wing went away under it.
    mutating func cancel() {
        deadline = nil
    }
}

/// The AppKit view the wings are clicked through.
///
/// Modelled on `ItemInteractionView`, and AppKit for the same reasons: the
/// panel is non-activating, so every click on it is a first click that SwiftUI
/// would otherwise swallow (§28), and the click count AppKit has already
/// worked out is the honest answer to "was that a double click".
///
/// It takes the whole of `mouseDown` and passes none of it on: the tray's own
/// view would make itself first responder and clear the selection. The panel
/// would also become key, which no view can prevent — `TrayPanel.sendEvent`
/// refuses it for a click that lands here. A click on the mark is not a click
/// into the shelf, and must leave the keyboard exactly where it was. For the same reason
/// it never tells the presenter anything: playing music is not interacting
/// with the files.
final class PillClickView: NSView {
    var onSingle: () -> Void = {}
    var onDouble: () -> Void = {}

    var handlesSingle = true {
        didSet { arbiter.handlesSingle = handlesSingle }
    }

    private var arbiter = ClickArbiter(window: ClickArbiter.systemWindow)
    private var pendingSingle: Task<Void, Never>?
    private var isPressed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // The wing it sits in carries the label and the actions; this is only
        // where the pointer lands.
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    isolated deinit {
        pendingSingle?.cancel()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isPressed else { return }
        isPressed = false
        // A press that ended somewhere else is not a click on this.
        let location = convert(event.locationInWindow, from: nil)
        guard bounds.contains(location) else { return }

        arbiter.window = ClickArbiter.systemWindow
        let action = arbiter.click(count: event.clickCount, at: event.timestamp)
        perform(action)
        scheduleSingle()
    }

    /// Waits for the arbiter's deadline, then asks it again. A cancellable
    /// task rather than a timer, so a second click cancels it outright.
    private func scheduleSingle() {
        pendingSingle?.cancel()
        guard arbiter.deadline != nil else {
            pendingSingle = nil
            return
        }

        pendingSingle = Task { [weak self] in
            while let self, let due = self.arbiter.deadline {
                let wait = due - ProcessInfo.processInfo.systemUptime
                if wait > 0 {
                    try? await Task.sleep(for: .seconds(wait))
                }
                guard !Task.isCancelled else { return }
                // `event.timestamp` and the system uptime share a clock, so
                // the deadline the click set is comparable with this.
                self.perform(self.arbiter.tick(at: ProcessInfo.processInfo.systemUptime))
            }
        }
    }

    private func perform(_ action: ClickArbiter.Action?) {
        switch action {
        case .single: onSingle()
        case .double: onDouble()
        case nil: break
        }
    }

    /// The wing is going away. A play/pause still waiting would land on a
    /// shelf that no longer shows the thing that was clicked.
    func cancelPending() {
        pendingSingle?.cancel()
        pendingSingle = nil
        arbiter.cancel()
    }
}

/// Hosts `PillClickView` over a wing.
struct PillClickTarget: NSViewRepresentable {
    /// `nil` when a lone click does nothing here, so a double need not wait.
    var onSingle: (() -> Void)?
    var onDouble: () -> Void
    var toolTip: String?

    func makeNSView(context: Context) -> PillClickView {
        let view = PillClickView(frame: .zero)
        apply(to: view)
        return view
    }

    func updateNSView(_ view: PillClickView, context: Context) {
        apply(to: view)
    }

    static func dismantleNSView(_ view: PillClickView, coordinator: ()) {
        view.cancelPending()
    }

    private func apply(to view: PillClickView) {
        view.handlesSingle = onSingle != nil
        view.onSingle = onSingle ?? {}
        view.onDouble = onDouble
        // The SwiftUI tooltip on the wing never sees the pointer: this view
        // is on top of it and takes the hover. So the view carries it too.
        view.toolTip = toolTip
    }
}
