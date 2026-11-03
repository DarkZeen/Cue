import Foundation
import OSLog

/// Logging and the development debug overlay (§71, §80).
///
/// `Logger` rather than `print`, so messages are cheap enough to leave in and
/// can be pulled out of a device log archive after the fact. Nothing here logs
/// file contents or paths at `.public` — a tray full of filenames is the
/// user's business, not a log's.
enum Diagnostics {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.tray.app"

    static func logger(_ category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }

    /// `TRAY_DEBUG_SEED=/path/one:/path/two` puts those files on the shelf and
    /// opens it at launch.
    ///
    /// Debug builds only. It exists so a particular tray state can be put on
    /// screen and *looked at* — with a real desktop behind it, real
    /// translucency, real notch alignment — without a hand on the trackpad.
    /// Reviewing motion and materials by eye is the point of §84's loop, and
    /// this is the shortest path to something to review.
    static var debugSeedURLs: [URL] {
        #if DEBUG
        guard let value = ProcessInfo.processInfo.environment["TRAY_DEBUG_SEED"],
              !value.isEmpty
        else { return [] }
        return value.split(separator: ":").map { URL(fileURLWithPath: String($0)) }
        #else
        []
        #endif
    }

    /// `TRAY_DEBUG_HOLD=1` stops the tray closing on its own.
    ///
    /// Debug builds only. Every interesting state of this app is one the tray
    /// leaves after a second or two, which makes them hard to photograph and
    /// hard to stare at. This freezes whichever one you are in.
    static let holdsTrayOpen: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.environment["TRAY_DEBUG_HOLD"] == "1"
        #else
        false
        #endif
    }()

    /// `TRAY_DEBUG_SETTINGS=1`, or a pane name such as `privacy`, opens the
    /// settings window at launch on that page.
    ///
    /// Debug builds only. Settings is reachable from a menu bar item, which is
    /// awkward to get to — and impossible to screenshot from — while iterating
    /// on the window itself.
    static let debugSettingsPane: String? = {
        #if DEBUG
        ProcessInfo.processInfo.environment["TRAY_DEBUG_SETTINGS"]
        #else
        nil
        #endif
    }()

    /// `TRAY_DEBUG=1` turns on the geometry overlay. Read once: it is a
    /// development switch, not a setting.
    ///
    /// Guarded by `#if DEBUG` as well as the variable, so the overlay cannot
    /// reach a release build even if the variable is set (§71).
    static let isDebugOverlayEnabled: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.environment["TRAY_DEBUG"] == "1"
        #else
        false
        #endif
    }()
}
