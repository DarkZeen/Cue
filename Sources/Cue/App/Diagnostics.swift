import Foundation
import OSLog

/// Logging and the development switches.
///
/// `Logger` rather than `print`, so messages are cheap enough to leave in and
/// can be pulled out of a log archive after the fact. Nothing here logs a
/// search query, a title, or any part of a token at `.public` — what someone
/// listens to is their business, not a log's.
/// `nonisolated` because the OAuth callback listener runs on its own dispatch
/// queue and still has to be able to log. `Logger` is thread-safe, and the
/// environment switches are read once at launch.
nonisolated enum Diagnostics {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.cue.app"

    static func logger(_ category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }

    /// `CUE_DEBUG_OPEN=1` shows the panel at launch.
    ///
    /// Debug builds only. The panel is the whole app and it is normally two
    /// steps away — build, then trigger the shortcut. This removes both.
    static let opensPanelAtLaunch: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.environment["CUE_DEBUG_OPEN"] == "1"
        #else
        false
        #endif
    }()

    /// `CUE_DEBUG_HOLD=1` stops the panel closing when it loses focus.
    ///
    /// Debug builds only. Every interesting state of this app is one that
    /// disappears the moment you click away from it to look at something else,
    /// which makes them hard to photograph and hard to stare at.
    static let holdsPanelOpen: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.environment["CUE_DEBUG_HOLD"] == "1"
        #else
        false
        #endif
    }()

    /// `CUE_DEBUG_QUERY=ambient` opens the panel with that already typed in.
    ///
    /// Debug builds only. The results list is the half of the panel that only
    /// exists while someone is typing, which makes it the half that is hardest
    /// to look at — and impossible to screenshot without a hand on the
    /// keyboard. This puts a given state on a real screen and leaves it there.
    static var debugQuery: String? {
        #if DEBUG
        let value = ProcessInfo.processInfo.environment["CUE_DEBUG_QUERY"]
        return (value?.isEmpty == false) ? value : nil
        #else
        nil
        #endif
    }

    /// `CUE_DEBUG_SETTINGS=1`, or a pane name such as `accounts`, opens the
    /// settings window at launch on that page.
    ///
    /// Debug builds only. Settings is reachable from a menu item, which is
    /// awkward to get to — and impossible to screenshot from — while iterating
    /// on the window itself.
    static let debugSettingsPane: String? = {
        #if DEBUG
        ProcessInfo.processInfo.environment["CUE_DEBUG_SETTINGS"]
        #else
        nil
        #endif
    }()

    /// `CUE_DEBUG_NETWORK=1` logs every request the providers make, with the
    /// query and the response size.
    ///
    /// Debug builds only, and it is the only switch that logs anything about
    /// what was searched for — which is exactly why it is not a setting.
    static let logsNetwork: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.environment["CUE_DEBUG_NETWORK"] == "1"
        #else
        false
        #endif
    }()
}
