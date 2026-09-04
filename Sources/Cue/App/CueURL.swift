import Foundation

/// The URL scheme this build actually registered.
///
/// Read from the bundle rather than written down here, because `build.sh`
/// rewrites it: a `--dev` build claims `cue-dev` so that a development copy and
/// an installed release do not fight over the same scheme — whichever one
/// LaunchServices happens to pick would answer the shortcut, and which one it
/// picks is not something you get to decide.
///
/// Hardcoding `"cue"` instead is a bug that hides perfectly: the dev build
/// launches, registers `cue-dev`, receives the URL, compares it against the
/// wrong string and silently does nothing at all.
enum CueURL {
    static let scheme: String = {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        let schemes = types?.first?["CFBundleURLSchemes"] as? [String]
        return schemes?.first ?? "cue"
    }()

    /// The command to put in a keyboard shortcut. Shown in Settings, so it has
    /// to name the scheme this build really answers to.
    static func command(_ action: String) -> String {
        "open \(scheme)://\(action)"
    }
}
