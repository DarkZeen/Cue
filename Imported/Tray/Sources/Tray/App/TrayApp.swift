import AppKit

/// Entry point.
///
/// Hand-rolled rather than a SwiftUI `App`, because everything that makes Tray
/// work — a borderless non-activating panel, window levels, collection
/// behaviour, real drag sessions — is AppKit's to give (§27). SwiftUI is used
/// where it is better: drawing the tray.
@main
enum TrayApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()

        application.delegate = delegate

        // Set before `run()` so the app never flashes a Dock tile on launch.
        application.setActivationPolicy(.accessory)

        application.run()
    }
}
