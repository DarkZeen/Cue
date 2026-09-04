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
    }

    /// Brings the plaque into line with what is actually happening.
    ///
    /// Called whenever anything it depends on changes, rather than each caller
    /// deciding for itself whether to show or hide — there are four conditions
    /// and every one of them has to agree.
    func sync() {
        let shouldShow = settings.showsMiniPlayer
            && player.nowPlaying != nil
            // Two players on screen saying the same thing is one too many.
            && !player.isWindowVisible

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
        guard let panel, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
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
        isMovable = false
        isRestorable = false

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
}
