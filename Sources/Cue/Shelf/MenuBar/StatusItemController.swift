import AppKit

/// Cue's menu bar presence (§31).
///
/// An access point, not the product: the speed dial is a keystroke and the
/// shelf is the top of the screen. Every item here does something neither of
/// those can, or is a way to reach them without the keyboard or the pointer's
/// aim.
@MainActor
final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem?

    var onOpenPanel: () -> Void = {}
    var onOpenShelf: () -> Void = {}
    var onTogglePlayer: () -> Void = {}
    var isPlayerVisible: () -> Bool = { false }
    /// What the panel's shortcut is, for the menu to show beside "Open Cue".
    var panelShortcut: () -> String? = { nil }
    var onOpenSettings: () -> Void = {}
    var onToggleLaunchAtLogin: () -> Void = {}
    var isLaunchAtLoginEnabled: () -> Bool = { false }
    var launchAtLoginExplanation: () -> String? = { nil }

    func setVisible(_ visible: Bool) {
        if visible {
            guard statusItem == nil else { return }
            install()
        } else {
            guard let statusItem else { return }
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = MenuBarIcon.menuBarImage()
        item.button?.toolTip = "Cue"
        item.button?.setAccessibilityLabel("Cue")
        item.menu = buildMenu()
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let open = menu.addAction(title: "Open Cue") { [weak self] in self?.onOpenPanel() }
        open.identifier = Self.openItemIdentifier
        menu.addAction(title: "Open Shelf") { [weak self] in self?.onOpenShelf() }
        let player = menu.addAction(title: "Show Player") { [weak self] in self?.onTogglePlayer() }
        player.identifier = Self.playerItemIdentifier

        menu.addItem(.separator())

        let launch = menu.addAction(title: "Launch at Login") { [weak self] in
            self?.onToggleLaunchAtLogin()
        }
        launch.identifier = Self.launchItemIdentifier

        menu.addAction(title: "Settings…") { [weak self] in self?.onOpenSettings() }

        menu.addItem(.separator())

        menu.addAction(title: "About Cue") {
            NSApp.activate()
            NSApp.orderFrontStandardAboutPanel(nil)
        }

        menu.addAction(title: "Quit Cue") {
            NSApp.terminate(nil)
        }

        return menu
    }

    private static let launchItemIdentifier = NSUserInterfaceItemIdentifier("launchAtLogin")
    private static let openItemIdentifier = NSUserInterfaceItemIdentifier("openPanel")
    private static let playerItemIdentifier = NSUserInterfaceItemIdentifier("player")
}

extension StatusItemController: NSMenuDelegate {
    /// The checkmark is refreshed as the menu opens rather than cached,
    /// because the login item can be switched off in System Settings without
    /// telling us (§34).
    func menuWillOpen(_ menu: NSMenu) {
        for item in menu.items {
            switch item.identifier {
            case Self.launchItemIdentifier:
                item.state = isLaunchAtLoginEnabled() ? .on : .off
                item.toolTip = launchAtLoginExplanation()
            case Self.playerItemIdentifier:
                item.title = isPlayerVisible() ? "Hide Player" : "Show Player"
            case Self.openItemIdentifier:
                // Shown as a hint, not bound: the shortcut is a global hotkey,
                // and a menu key equivalent would only fire with the menu open.
                item.toolTip = panelShortcut().map { "Or press \($0) anywhere." }
            default:
                break
            }
        }
    }
}
