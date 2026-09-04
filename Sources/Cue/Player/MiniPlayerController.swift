import AppKit
import SwiftUI

/// The plaque's window: a small, always-there transport in the top-right
/// corner, over everything.
///
/// The same non-activating panel the search overlay uses, and for the same
/// reason — clicking Pause must not pull you out of the app you are working in.
/// It differs from that one in never taking the keyboard at all: there is
/// nothing here to type into, and a HUD that steals focus to be pressed is a
/// HUD that costs more than it saves.
@MainActor
final class MiniPlayerController {
    private let player: PlayerService
    private let settings: SettingsStore

    private var panel: MiniPlayerPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var screenObserver: (any NSObjectProtocol)?
    private var moveObserver: (any NSObjectProtocol)?

    private let logger = Diagnostics.logger("mini-player")

    /// Sized for the plaque plus the margin its notes drift into.
    private static let size = NSSize(width: 258, height: 72)
    /// Clear of the menu bar and the right-hand edge without hugging either.
    private static let margin = NSSize(width: 14, height: 8)

    init(player: PlayerService, settings: SettingsStore) {
        self.player = player
        self.settings = settings

        // A display arrangement change moves the corner the plaque is pinned
        // to. Without this it stays where the old corner used to be, which on
        // an unplugged external display is off screen entirely.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
    }

    isolated deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
    }

    /// Puts the plaque back in its corner.
    func resetPosition() {
        settings.miniPlayerOrigin = nil
        reposition()
    }

    /// Brings the plaque into line with what is actually happening.
    ///
    /// Called whenever anything it depends on changes, rather than each caller
    /// deciding for itself whether to show or hide — there are four conditions
    /// and every one of them has to agree.
    /// True while the layout is being arranged: the plaque stays on screen even
    /// with nothing playing, and moves on a plain drag.
    private(set) var isEditing = false

    func beginEditing() {
        isEditing = true
        panel?.isEditing = true
        show()
        panel?.isEditing = true
    }

    func endEditing() {
        isEditing = false
        panel?.isEditing = false
        sync()
    }

    func sync() {
        // Shown regardless while arranging: you cannot place a thing that is
        // not on screen, and requiring music to be playing before the plaque
        // can be positioned would be a strange condition to discover.
        let shouldShow = isEditing || (
            settings.showsMiniPlayer
                && player.nowPlaying != nil
                // Two players on screen saying the same thing is one too many.
                && !player.isWindowVisible
        )

        shouldShow ? show() : hide()
    }

    private func show() {
        let panel = preparePanel()
        reposition()
        panel.orderFrontRegardless()
    }

    private func hide() {
        panel?.orderOut(nil)
    }

    private func reposition() {
        guard let panel else { return }

        // Where it was left, if that is still somewhere a person can see. A
        // saved position survives an unplugged display as a set of coordinates
        // nothing covers any more, and a plaque you cannot find is worse than
        // one that moved.
        if let saved = settings.miniPlayerOrigin,
           NSScreen.screens.contains(where: {
               $0.visibleFrame.intersects(NSRect(origin: saved, size: Self.size))
           }) {
            panel.setFrameOrigin(saved)
            return
        }

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame

        panel.setFrameOrigin(NSPoint(
            x: visible.maxX - Self.size.width - Self.margin.width,
            y: visible.maxY - Self.size.height - Self.margin.height
        ))
    }

    private func preparePanel() -> MiniPlayerPanel {
        if let panel { return panel }

        let panel = MiniPlayerPanel(
            contentRect: NSRect(origin: .zero, size: Self.size)
        )
        panel.isEditing = isEditing

        let view = AnyView(
            MiniPlayerHost(player: player)
                .frame(width: Self.size.width, height: Self.size.height, alignment: .topTrailing)
        )

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: Self.size)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        self.panel = panel
        self.hostingView = hostingView

        // Saved on every move rather than on some later commit. The plaque is
        // dragged with the mouse and there is no moment afterwards that means
        // "done" — a position kept only until the app quits is a position the
        // user has to set again tomorrow.
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { return }
                self.settings.miniPlayerOrigin = panel.frame.origin
            }
        }

        logger.notice("Mini player created.")
        return panel
    }
}

/// Reads the player so the plaque redraws as the track and its state change.
private struct MiniPlayerHost: View {
    let player: PlayerService

    var body: some View {
        if let nowPlaying = player.nowPlaying {

            MiniPlayerView(
                nowPlaying: nowPlaying,
                onOpen: { player.showCurrent() },
                onPrevious: { player.previous() },
                onPlayPause: { player.togglePlayPause() },
                onNext: { player.next() },
                onToggleMute: { player.toggleMute() },
                onAdjustVolume: { player.adjustVolume(by: $0) }
            )
        }
    }
}

/// The window the plaque lives in.
final class MiniPlayerPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        // The plaque draws its own shadow, sized to its rounded rectangle. The
        // window's would be cast by the whole frame, including the transparent
        // margin the notes drift into.
        hasShadow = false

        isFloatingPanel = true
        hidesOnDeactivate = false
        isRestorable = false

        // Draggable, unlike the search panel — but only while Command is held.
        // The plaque is five small buttons in a strip you aim at without
        // looking, and a surface that moves when you miss one is a surface that
        // ends up somewhere you did not put it.
        isMovable = true
        isMovableByWindowBackground = false

        // Above ordinary windows and above the search panel, so pressing Pause
        // never means hunting for the plaque underneath something.
        level = .statusBar

        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]

        animationBehavior = .none
    }

    /// Never. There is nothing here to type into, and taking the keyboard to be
    /// clicked would pull the user out of whatever they were writing in.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Set while the layout is being arranged, when a plain drag moves it.
    var isEditing = false

    /// ⌘-drag moves the plaque; a plain drag does not.
    ///
    /// Intercepted here rather than by `isMovableByWindowBackground`, which
    /// cannot be made conditional: it moves the window on any background drag,
    /// including the one that starts a fraction outside the Pause button.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown,
           isEditing || event.modifierFlags.contains(.command) {
            performDrag(with: event)
            return
        }
        super.sendEvent(event)
    }
}
