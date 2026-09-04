#!/usr/bin/env bash
#
# Builds Cue.app.
#
# SwiftPM compiles the binary; this script assembles the bundle around it by
# hand. There is no .xcodeproj and there is no xcodebuild step, so the command
# a developer runs on a laptop is the same one CI runs. Cue has no app
# extension, so unlike some hand-built bundles this one needs nothing from
# Xcode at all — the Command Line Tools are enough.
#
#   ./Scripts/build.sh                 release build, signed, into build/
#   ./Scripts/build.sh --dev           separate bundle id, coexists with a release install
#   ./Scripts/build.sh --debug         debug configuration (CUE_DEBUG_* switches available)
#   ./Scripts/build.sh --install       also copy into /Applications and launch
#   ./Scripts/build.sh --universal     add an x86_64 slice

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT="$PWD"

CONFIGURATION="release"
BUNDLE_ID="com.cue.app"
APP_NAME="Cue"
DISPLAY_NAME="Cue"
URL_SCHEME="cue"
UNIVERSAL=0
INSTALL=0

# ---------------------------------------------------------------- arguments

for argument in "$@"; do
    case "$argument" in
        --dev)
            BUNDLE_ID="com.cue.app.dev"
            DISPLAY_NAME="Cue (dev)"
            # A separate scheme as well as a separate identifier. Two builds
            # registering `cue://` means macOS picks one of them to hand the
            # shortcut to, and which one is not something you get to decide.
            URL_SCHEME="cue-dev"
            ;;
        --debug)     CONFIGURATION="debug" ;;
        --universal) UNIVERSAL=1 ;;
        --install)   INSTALL=1 ;;
        -h|--help)
            sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "error: unknown option '$argument'" >&2
            exit 2
            ;;
    esac
done

# -------------------------------------------------------------- environment

command -v swift >/dev/null || {
    echo "error: swift not found. Install the Xcode Command Line Tools:" >&2
    echo "         xcode-select --install" >&2
    exit 1
}

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP/Contents"

echo "▸ Cue $VERSION ($BUILD_NUMBER) — $CONFIGURATION, $BUNDLE_ID"

# ------------------------------------------------------------------ compile

echo "▸ Compiling"
if [[ $UNIVERSAL -eq 1 ]]; then
    swift build -c "$CONFIGURATION" --arch arm64 --arch x86_64
    BINARY="$(swift build -c "$CONFIGURATION" --arch arm64 --arch x86_64 --show-bin-path)/$APP_NAME"
else
    swift build -c "$CONFIGURATION" --arch arm64
    BINARY="$(swift build -c "$CONFIGURATION" --arch arm64 --show-bin-path)/$APP_NAME"
fi

[[ -f "$BINARY" ]] || { echo "error: no binary at $BINARY" >&2; exit 1; }

# ----------------------------------------------------------------- assemble

echo "▸ Assembling $APP_NAME.app"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BINARY" "$CONTENTS/MacOS/$APP_NAME"
chmod +x "$CONTENTS/MacOS/$APP_NAME"

cp Resources/Info.plist "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID"                  "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME"                         "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $DISPLAY_NAME"              "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME"                   "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION"            "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER"                  "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleURLTypes:0:CFBundleURLSchemes:0 $URL_SCHEME" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :LSUIElement true"                               "$CONTENTS/Info.plist"

printf 'APPL????' > "$CONTENTS/PkgInfo"

echo "▸ Drawing the icon"
swift Scripts/make-icon.swift "$CONTENTS/Resources/$APP_NAME.icns" >/dev/null

# Extended attributes picked up from Downloads, iCloud or a File Provider
# invalidate a signature after the fact. Strip them before signing.
xattr -c -r "$APP"

# -------------------------------------------------------------------- sign
#
# Three tiers, tried in order. Nothing in the source tree requires a paid
# account; the difference is only how far the result travels.

ENTITLEMENTS="$ROOT/Resources/Cue.entitlements"

# `-v` is omitted deliberately: the local identity from setup-signing.sh is
# self-signed and therefore untrusted, so it never shows up as "valid" even
# though codesign signs with it perfectly well.
find_identity() {
    security find-identity -p codesigning 2>/dev/null \
        | { grep "$1" || true; } | head -1 | awk -F'"' '{ print $2 }'
}

DEVELOPER_ID="${CUE_SIGNING_IDENTITY:-$(find_identity 'Developer ID Application')}"
SELF_SIGNED="$(find_identity 'Cue Signing')"

if [[ -n "$DEVELOPER_ID" ]]; then
    echo "▸ Signing with Developer ID: $DEVELOPER_ID"
    codesign --force --strip-disallowed-xattrs --options runtime --timestamp \
        --entitlements "$ENTITLEMENTS" --sign "$DEVELOPER_ID" "$APP"
elif [[ -n "$SELF_SIGNED" ]]; then
    echo "▸ Signing with the local identity: $SELF_SIGNED"
    codesign --force --strip-disallowed-xattrs \
        --entitlements "$ENTITLEMENTS" --sign "$SELF_SIGNED" "$APP"
else
    echo "▸ Signing ad-hoc"
    codesign --force --strip-disallowed-xattrs --sign - "$APP"
    cat >&2 <<'WARNING'

  warning: this build is signed ad-hoc, so its signature changes every time you
           build it. macOS treats each rebuild as a different application, which
           means Launch at Login will not survive a rebuild — and, worse here,
           neither will the keychain items holding your tokens. You will be
           asked to sign in again after every build.

           Run ./Scripts/setup-signing.sh once to create a stable local identity.

WARNING
fi

echo "▸ Verifying"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/    /'

# ----------------------------------------------------------------- install

if [[ $INSTALL -eq 1 ]]; then
    echo "▸ Installing to /Applications"
    pkill -x "$APP_NAME" 2>/dev/null || true
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" "/Applications/$APP_NAME.app"
    open "/Applications/$APP_NAME.app"
fi

echo "▸ Done: $APP"
