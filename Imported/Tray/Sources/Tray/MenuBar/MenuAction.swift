import AppKit

/// Menus built from closures, next to the thing they act on.
///
/// `NSMenuItem.target` is a weak reference, so a closure-backed target has to
/// be kept alive by something. It is parked in `representedObject`, which the
/// item owns — the action lives exactly as long as the menu item does.
final class MenuActionTarget: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func fire() {
        handler()
    }
}

extension NSMenu {
    @discardableResult
    func addAction(
        title: String,
        isEnabled: Bool = true,
        handler: @escaping () -> Void
    ) -> NSMenuItem {
        let target = MenuActionTarget(handler)
        let item = NSMenuItem(
            title: title,
            action: #selector(MenuActionTarget.fire),
            keyEquivalent: ""
        )
        item.target = target
        item.representedObject = target
        item.isEnabled = isEnabled
        addItem(item)
        return item
    }
}
