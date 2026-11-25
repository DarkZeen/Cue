// swift-tools-version: 6.2

import Foundation
import PackageDescription

// Swift Testing ships inside the Command Line Tools as a *framework*, and on a
// machine with no Xcode SwiftPM passes its directory as a header search path
// rather than a framework search path — so `import Testing` cannot be resolved.
// Adding `-F` fixes it. The path is only added when the Command Line Tools are
// in use and it actually exists, so a machine with Xcode (and CI) is untouched.
let commandLineToolsFrameworks =
    "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"

// Testing.framework in turn loads lib_TestingInterop.dylib from a sibling
// directory that is likewise not on the default search path.
let commandLineToolsLibraries =
    "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

// Only when the Command Line Tools are the *selected* developer directory. A Mac
// can have both, and with Xcode selected its compiler's `@Test` macro expands
// against Xcode's own Testing — so pointing it at the older copy in the Command
// Line Tools breaks every test with a mismatched `__SourceBounds`. Selected
// means what `xcrun` would use: `DEVELOPER_DIR`, else `xcode-select`'s link,
// and with neither set the Command Line Tools are all there is.
let selectedDeveloperDirectory =
    ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
    ?? (try? FileManager.default.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link"))

let selectsCommandLineTools =
    selectedDeveloperDirectory.map { $0.contains("CommandLineTools") } ?? true

let hasCommandLineToolsFrameworks = selectsCommandLineTools
    && FileManager.default.fileExists(atPath: commandLineToolsFrameworks)

let testingCompileFlags: [String] =
    hasCommandLineToolsFrameworks ? ["-F", commandLineToolsFrameworks] : []

let testingLinkFlags: [String] = hasCommandLineToolsFrameworks
    ? ["-F", commandLineToolsFrameworks,
       "-Xlinker", "-rpath", "-Xlinker", commandLineToolsFrameworks,
       "-Xlinker", "-rpath", "-Xlinker", commandLineToolsLibraries]
    : []

let sharedSwiftSettings: [SwiftSetting] = [
    // Everything starts on the main actor and stays there until profiling says
    // otherwise. Network work is `async` and hops off on its own; nothing here
    // needs a second isolation domain to reason about.
    .defaultIsolation(MainActor.self),
    .swiftLanguageMode(.v6),
]

let package = Package(
    name: "Cue",
    platforms: [.macOS("26.0")],
    targets: [
        // The whole app. `Scripts/build.sh` takes the binary this produces and
        // assembles Cue.app around it; SwiftPM never sees the bundle.
        .executableTarget(
            name: "Cue",
            path: "Sources/Cue",
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "CueTests",
            dependencies: ["Cue"],
            path: "Tests/CueTests",
            swiftSettings: sharedSwiftSettings
                + (testingCompileFlags.isEmpty ? [] : [.unsafeFlags(testingCompileFlags)]),
            linkerSettings: testingLinkFlags.isEmpty
                ? []
                : [.unsafeFlags(testingLinkFlags)]
        ),
    ]
)
