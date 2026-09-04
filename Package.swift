// swift-tools-version: 6.2

import Foundation
import PackageDescription

// Swift Testing ships inside the Command Line Tools as a *framework*, and on a
// machine with no Xcode SwiftPM passes its directory as a header search path
// rather than a framework search path — so `import Testing` cannot be resolved.
// Adding `-F` fixes it. The path is only added when it actually exists, so a
// machine with Xcode (and CI) is untouched.
let commandLineToolsFrameworks =
    "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"

// Testing.framework in turn loads lib_TestingInterop.dylib from a sibling
// directory that is likewise not on the default search path.
let commandLineToolsLibraries =
    "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

let hasCommandLineToolsFrameworks =
    FileManager.default.fileExists(atPath: commandLineToolsFrameworks)

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
