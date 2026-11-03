#!/usr/bin/env bash
#
# Builds Tray-x.y.z.dmg (§64, §65, §69).
#
# The window has two icons and an arrow between them, and nothing else. No
# installer, no wizard, no read-me alias, no uninstaller sitting there looking
# ominous — drag the app into Applications and close the window.
#
#   ./Scripts/create-dmg.sh          build the app first, then the disk image
#   ./Scripts/create-dmg.sh --skip-build   use whatever is already in build/

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT="$PWD"

APP_NAME="Tray"
SKIP_BUILD=0

for argument in "$@"; do
    case "$argument" in
        --skip-build) SKIP_BUILD=1 ;;
        *) echo "error: unknown option '$argument'" >&2; exit 2 ;;
    esac
done

if [[ $SKIP_BUILD -eq 0 ]]; then
    ./Scripts/build.sh
fi

APP="$ROOT/build/$APP_NAME.app"
[[ -d "$APP" ]] || { echo "error: no $APP — run ./Scripts/build.sh first" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
VOLUME_NAME="$APP_NAME $VERSION"
DIST="$ROOT/dist"
DMG="$DIST/$APP_NAME-$VERSION.dmg"

mkdir -p "$DIST"
rm -f "$DMG"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"; hdiutil detach "/Volumes/$VOLUME_NAME" -quiet 2>/dev/null || true' EXIT

echo "▸ Staging"
cp -R "$APP" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"
mkdir -p "$STAGING/.background"
swift Scripts/make-dmg-background.swift "$STAGING/.background/background.png" >/dev/null

# Stops macOS writing an .fseventsd log into the image while it is mounted.
mkdir -p "$STAGING/.fseventsd"
touch "$STAGING/.fseventsd/no_log"

# Extended attributes on the staged copy would end up baked into the image.
xattr -c -r "$STAGING"

echo "▸ Creating a writable image"
WRITABLE="$STAGING.dmg"
rm -f "$WRITABLE"
hdiutil create -srcfolder "$STAGING" -volname "$VOLUME_NAME" \
    -fs HFS+ -format UDRW -quiet "$WRITABLE"

echo "▸ Laying out the window"
MOUNT_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "$WRITABLE")"
MOUNT_POINT="$(echo "$MOUNT_OUTPUT" | grep -E '/Volumes/' | sed -E 's/.*(\/Volumes\/.*)$/\1/')"

# Finder is what writes the .DS_Store that carries icon positions, the window
# size and the background. On a headless machine this is not available, so the
# failure is tolerated: the image still works, it just opens with a default
# layout rather than a designed one.
if ! osascript <<APPLESCRIPT >/dev/null 2>&1
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 140, 820, 540}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 116
        set text size of theViewOptions to 12
        set background picture of theViewOptions to file ".background:background.png"
        set position of item "$APP_NAME.app" of container window to {168, 196}
        set position of item "Applications" of container window to {452, 196}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT
then
    echo "  note: Finder could not style the window (headless?); shipping the default layout."
fi

sync
hdiutil detach "$MOUNT_POINT" -quiet

echo "▸ Compressing"
hdiutil convert "$WRITABLE" -format UDZO -imagekey zlib-level=9 -quiet -o "$DMG"
rm -f "$WRITABLE"

# The disk image is signed too when an identity is available, so Gatekeeper has
# something to check before the app is even copied out.
DEVELOPER_ID="${TRAY_SIGNING_IDENTITY:-}"
if [[ -z "$DEVELOPER_ID" ]]; then
    DEVELOPER_ID="$(security find-identity -p codesigning 2>/dev/null \
        | grep 'Developer ID Application' | head -1 | awk -F'"' '{ print $2 }' || true)"
fi

if [[ -n "$DEVELOPER_ID" ]]; then
    echo "▸ Signing the disk image"
    codesign --force --sign "$DEVELOPER_ID" --timestamp "$DMG"
fi

echo "▸ Checksum"
( cd "$DIST" && shasum -a 256 "$(basename "$DMG")" | tee "$(basename "$DMG").sha256" )

echo "▸ Done: $DMG"
