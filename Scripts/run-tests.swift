#!/usr/bin/env swift -F /Library/Developer/CommandLineTools/Library/Developer/Frameworks

// Runs the Swift Testing bundle.
//
// `swift test` builds the bundle correctly on a machine with the Command Line
// Tools and no Xcode, but the helper that would execute it exits silently
// without running anything — a deliberately failing assertion still reports
// success, which is worse than having no tests at all.
//
// So the bundle is loaded and Swift Testing's own entry point is called
// directly. `Scripts/test.sh` builds and then runs this. On a machine with
// Xcode, and in CI, plain `swift test` works and this is not needed.

import Foundation
import Testing

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: run-tests.swift <bundle-binary>\n".utf8))
    exit(2)
}

let bundlePath = arguments[1]
guard FileManager.default.fileExists(atPath: bundlePath) else {
    FileHandle.standardError.write(Data("no test bundle at \(bundlePath)\n".utf8))
    exit(2)
}

// Loading the bundle registers its tests with the Testing runtime.
guard dlopen(bundlePath, RTLD_NOW | RTLD_GLOBAL) != nil else {
    let message = String(cString: dlerror())
    FileHandle.standardError.write(Data("could not load the test bundle: \(message)\n".utf8))
    exit(2)
}

// `nil` means "take the options from the command line", which is how the usual
// runner is configured too.
let status: CInt = await Testing.__swiftPMEntryPoint(
    passing: nil as Testing.__CommandLineArguments_v0?
)
exit(status)
