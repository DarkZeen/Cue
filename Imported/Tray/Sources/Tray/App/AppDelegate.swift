import AppKit
import Quartz

/// The application object's thin edge (§37).
///
/// Tray is an agent: no Dock icon, no main window, nothing in ⌘-Tab. Almost
/// everything real lives in `AppState`; this exists to receive the handful of
/// messages AppKit only sends to a delegate.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt and braces alongside `LSUIElement` in Info.plist: an accessory
        // app has no Dock tile and never becomes the active application by
        // being launched.
        NSApp.setActivationPolicy(.accessory)
        state.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Closing the settings window is not quitting. The tray is still there.
        false
    }

    /// Opening Tray while it is already running opens Settings.
    ///
    /// An agent app has no Dock tile and no window to bring forward, so
    /// double-clicking it in Applications would otherwise appear to do nothing
    /// at all — the app is running, so macOS just sends this and waits. Settings
    /// is the only thing it could sensibly mean.
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows: Bool
    ) -> Bool {
        MainActor.assumeIsolated { state.showSettings() }
        return true
    }

    // MARK: - Quick Look (§24)

    // `QLPreviewPanel` finds its controller by walking the responder chain,
    // which ends at the application delegate. The tray's own panel is
    // non-activating and deliberately not part of that chain, so the delegate
    // answers on its behalf.

    override nonisolated func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override nonisolated func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { state.quickLook.attach(to: panel) }
    }

    override nonisolated func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { state.quickLook.detach(from: panel) }
    }
}
