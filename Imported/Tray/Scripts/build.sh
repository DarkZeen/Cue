#!/usr/bin/env bash
#
# Builds Tray.app (§61, §69).
#
# SwiftPM compiles the binary; this script assembles the bundle around it by
# hand. There is no .xcodeproj and there is no xcodebuild step, so the command
# a developer runs on a laptop is the same one CI runs (§66). If it builds
# here, it builds there.
#
#   ./Scripts/build.sh                 release build, signed, into build/
#   ./Scripts/build.sh --dev           separate bundle id, coexists with a release install
#   ./Scripts/build.sh --install       also copy into /Applications and launch
#   ./Scripts/build.sh --debug         debug configuration (TRAY_DEBUG overlay available)
#   ./Scripts/build.sh --universal     add an x86_64 slice (off by default, §60)

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT="$PWD"

CONFIGURATION="release"
BUNDLE_ID="com.tray.app"
APP_NAME="Tray"
DISPLAY_NAME="Tray"
UNIVERSAL=0
INSTALL=0

# ---------------------------------------------------------------- arguments

for argument in "$@"; do
    case "$argument" in
        --dev)
            BUNDLE_ID="com.tray.app.dev"
            DISPLAY_NAME="Tray (dev)"
            ;;
        --debug)     CONFIGURATION="debug" ;;
        --universal) UNIVERSAL=1 ;;
        --install)   INSTALL=1 ;;
        -h|--help)
            sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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

echo "▸ Tray $VERSION ($BUILD_NUMBER) — $CONFIGURATION, $BUNDLE_ID"

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
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID"            "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME"                   "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $DISPLAY_NAME"        "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME"             "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION"      "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER"            "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :LSUIElement true"                         "$CONTENTS/Info.plist"

printf 'APPL????' > "$CONTENTS/PkgInfo"

echo "▸ Drawing the icon"
swift Scripts/make-icon.swift "$CONTENTS/Resources/$APP_NAME.icns" >/dev/null

# Extended attributes picked up from Downloads, iCloud or a File Provider
# invalidate a signature after the fact. Strip them before signing (§61).
xattr -c -r "$APP"

# -------------------------------------------------------------------- sign
#
# Three tiers, tried in order (§67). Nothing in the source tree requires a paid
# account; the difference is only how far the result travels.

ENTITLEMENTS="$ROOT/Resources/Tray.entitlements"
# `-v` is omitted deliberately: the local identity from setup-signing.sh is
# self-signed and therefore untrusted, so it never shows up as "valid" even
# though codesign signs with it perfectly well (§67, tier 2).
# Matched on the quoted common name only. `find-identity` appends a trust
# status such as "(CSSMERR_TP_NOT_TRUSTED)" outside the quotes, which a looser
# pattern would drag into the identity name and then fail to find.
find_identity() {
    security find-identity -p codesigning 2>/dev/null \
        | { grep "$1" || true; } | head -1 | awk -F'"' '{ print $2 }'
}

DEVELOPER_ID="${TRAY_SIGNING_IDENTITY:-$(find_identity 'Developer ID Application')}"
SELF_SIGNED="$(find_identity 'Tray Signing')"

# The local keychain relocks whenever the Mac restarts, and a locked keychain
# makes codesign stop the build with a password dialog — for a password the
# developer never chose, because setup-signing.sh generated it. Unlock it from
# the file that script wrote, so a rebuild after a reboot just works.
KEYCHAIN_PASSWORD_FILE="$HOME/.config/tray/signing-keychain-password"
if [[ -n "$SELF_SIGNED" && -f "$KEYCHAIN_PASSWORD_FILE" ]]; then
    security unlock-keychain -p "$(cat "$KEYCHAIN_PASSWORD_FILE")" \
        tray-signing.keychain 2>/dev/null \
        || echo "  note: could not unlock the signing keychain; codesign may prompt"
fi

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
           means Launch at Login will not survive a rebuild and any permissions
           you grant are dropped.

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
