#!/usr/bin/env bash
#
# Runs the test suite.
#
#   ./Scripts/test.sh
#
# On a machine with Xcode, `swift test` does this on its own. With the Command
# Line Tools only, `swift test` builds the bundle and then exits silently
# without executing it — a deliberately failing assertion still reports success
# — so this script loads the bundle and calls Swift Testing's entry point
# itself. Same tests, same output, actually run.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
LIBRARIES="/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
RUNNER=".build/testrunner/run-tests"

[[ $# -eq 0 ]] || { echo "error: unknown option '$1'" >&2; exit 2; }

# The hand-rolled runner is for the Command Line Tools alone. With Xcode
# selected, `swift test` works and the older Testing here would not match it.
if [[ "$(xcode-select -p)" == *CommandLineTools* && -d "$FRAMEWORKS/Testing.framework" ]]; then
    echo "▸ Building tests"
    swift build --build-tests

    BUNDLE="$(swift build --show-bin-path)/CuePackageTests.xctest/Contents/MacOS/CuePackageTests"
    [[ -f "$BUNDLE" ]] || { echo "error: no test bundle at $BUNDLE" >&2; exit 1; }

    if [[ ! -x "$RUNNER" || Scripts/run-tests.swift -nt "$RUNNER" ]]; then
        echo "▸ Building the test runner"
        mkdir -p "$(dirname "$RUNNER")"
        swiftc -swift-version 6 -F "$FRAMEWORKS" -framework Testing \
            -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
            -Xlinker -rpath -Xlinker "$LIBRARIES" \
            -o "$RUNNER" Scripts/run-tests.swift
    fi
    echo "▸ Running"
    exec "$RUNNER" "$BUNDLE"
else
    echo "▸ Running via swift test"
    exec swift test
fi
