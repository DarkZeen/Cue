import AppKit

/// Entry point.
///
/// Hand-rolled rather than a SwiftUI `App`, because everything that makes Cue
/// work — a borderless panel that floats over other apps, window levels,
/// collection behaviour, taking the keyboard without stealing the frontmost
/// app's place in ⌘-Tab — is AppKit's to give. SwiftUI is used where it is
/// better: drawing the panel's contents.
@main
enum CueApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()

        application.delegate = delegate

        // Set before `run()` so the app never flashes a Dock tile on launch.
        application.setActivationPolicy(.accessory)

        application.run()
    }
}
