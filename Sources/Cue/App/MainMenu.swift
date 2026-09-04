import AppKit

/// The menu bar Cue shows while it is the active application.
///
/// An agent app normally has no menu at all, and Cue would be happier without
/// one — but the panel has to activate the app to receive the keyboard, and an
/// active application with no main menu is an application where ⌘A, ⌘C, ⌘V and
/// ⌘Z do nothing in a text field. Those are AppKit's own menu items; without
/// the menu there is nothing to send the action to.
///
/// So: the smallest menu that makes the search field behave like a search
/// field, plus the two commands anyone would look for.
enum MainMenu {
    static func install(target: AnyObject) {
        let menu = NSMenu()

        menu.addItem(applicationMenuItem(target: target))
        menu.addItem(editMenuItem())

        NSApp.mainMenu = menu
    }

    private static func applicationMenuItem(target: AnyObject) -> NSMenuItem {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Cue"
        let item = NSMenuItem()
        let menu = NSMenu(title: name)

        menu.addItem(withTitle: "About \(name)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")

        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(AppDelegate.showSettingsFromMenu(_:)),
            keyEquivalent: ","
        )
        settings.target = target
        menu.addItem(settings)

        menu.addItem(.separator())

        menu.addItem(withTitle: "Hide \(name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        menu.addItem(withTitle: "Quit \(name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        item.submenu = menu
        return item
    }

    /// Nothing here has a target: these are the standard responder-chain
    /// actions, and leaving them unassigned is what lets them find whichever
    /// text field is first responder.
    private static func editMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Edit")

        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]

        menu.addItem(.separator())

        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        item.submenu = menu
        return item
    }
}
