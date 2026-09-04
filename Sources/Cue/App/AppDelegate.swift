import AppKit

/// The application object's thin edge.
///
/// Cue is an agent: no Dock icon, no main window, nothing in ⌘-Tab until the
/// panel is asked for. Almost everything real lives in `AppState`; this exists
/// to receive the handful of messages AppKit only sends to a delegate.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()

    private let logger = Diagnostics.logger("app-delegate")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt and braces alongside `LSUIElement` in Info.plist: an accessory
        // app has no Dock tile and never becomes the active application by
        // being launched.
        NSApp.setActivationPolicy(.accessory)
        MainMenu.install(target: self)
        state.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Closing Settings is not quitting. The shortcut still works.
        false
    }

    /// The `cue://` URLs, which is how a keyboard shortcut reaches the panel.
    ///
    /// There is no hotkey code in this app and no Accessibility permission
    /// request. The user binds a key to `open cue://open` — in Shortcuts.app,
    /// or in System Settings → Keyboard → Keyboard Shortcuts — and macOS
    /// delivers it here. It costs one launch of `open` and buys the app out of
    /// the single most invasive permission a Mac utility can ask for.
    ///
    ///     cue://open       show the panel
    ///     cue://toggle     show it, or hide it if it is already up
    ///     cue://settings   show the settings window
    ///
    /// The scheme comes from the bundle — a `--dev` build claims `cue-dev` —
    /// so it is `CueURL.scheme` rather than a literal.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            for url in urls where url.scheme == CueURL.scheme {
                logger.notice("Opened with \(CueURL.scheme, privacy: .public)://\(url.host() ?? "", privacy: .public)")
                switch url.host() {
                case "open": state.openPanel()
                case "toggle": state.togglePanel()
                case "settings": state.showSettings()
                default: break
                }
            }
        }
    }

    /// Opening Cue while it is already running opens Settings.
    ///
    /// An agent app has no Dock tile and no window to bring forward, so
    /// double-clicking it in Applications would otherwise appear to do nothing
    /// at all. Settings is the only thing it could sensibly mean — the panel is
    /// what the shortcut is for.
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows: Bool
    ) -> Bool {
        MainActor.assumeIsolated {
            logger.notice("Reopened; showing Settings.")
            state.showSettings()
        }
        return true
    }

    @objc func showSettingsFromMenu(_ sender: Any?) {
        state.showSettings()
    }
}
