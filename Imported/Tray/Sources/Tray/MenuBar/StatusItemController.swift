import AppKit

/// The menu bar presence (§31).
///
/// An access point, not the product. Five items, and every one of them does
/// something the tray itself cannot.
@MainActor
final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem?

    var onOpenTray: () -> Void = {}
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
        item.button?.image = TrayIcon.menuBarImage()
        item.button?.toolTip = "Tray"
        item.button?.setAccessibilityLabel("Tray")
        item.menu = buildMenu()
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        menu.addAction(title: "Open Tray") { [weak self] in self?.onOpenTray() }

        menu.addItem(.separator())

        let launch = menu.addAction(title: "Launch at Login") { [weak self] in
            self?.onToggleLaunchAtLogin()
        }
        launch.identifier = Self.launchItemIdentifier

        menu.addAction(title: "Settings…") { [weak self] in self?.onOpenSettings() }

        menu.addItem(.separator())

        menu.addAction(title: "About Tray") {
            NSApp.activate()
            NSApp.orderFrontStandardAboutPanel(nil)
        }

        menu.addAction(title: "Quit Tray") {
            NSApp.terminate(nil)
        }

        return menu
    }

    private static let launchItemIdentifier = NSUserInterfaceItemIdentifier("launchAtLogin")
}

extension StatusItemController: NSMenuDelegate {
    /// The checkmark is refreshed as the menu opens rather than cached,
    /// because the login item can be switched off in System Settings without
    /// telling us (§34).
    func menuWillOpen(_ menu: NSMenu) {
        guard let item = menu.items.first(where: { $0.identifier == Self.launchItemIdentifier })
        else { return }

        item.state = isLaunchAtLoginEnabled() ? .on : .off
        item.toolTip = launchAtLoginExplanation()
    }
}
