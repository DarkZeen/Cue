#!/usr/bin/env bash
#
# Cuts a release that Cue's updater can find.
#
#   ./Scripts/release.sh 0.2.0
#
# Builds, signs, zips, and publishes a GitHub release with the archive
# attached. Cue's updater looks for the newest release's .zip asset, verifies
# it was signed by the same identity as the running copy, and offers to install
# it — so a release signed with a different certificate will be refused by every
# copy already out there. That is the point, and it is also the trap: keep the
# signing identity.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

VERSION="${1:-}"
[[ -n "$VERSION" ]] || { echo "usage: ./Scripts/release.sh <version>   e.g. 0.2.0" >&2; exit 2; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "error: version must look like 1.2.3 — the updater compares them numerically" >&2
    exit 2
}

command -v gh >/dev/null || { echo "error: the GitHub CLI (gh) is required" >&2; exit 1; }

if [[ -n "$(git status --porcelain)" ]]; then
    echo "error: working tree is dirty. Commit first — a release should name a commit." >&2
    exit 1
fi

echo "▸ Setting the version to $VERSION"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist
git add Resources/Info.plist
git commit -q -m "Cue $VERSION"

./Scripts/build.sh

ARCHIVE="build/Cue-$VERSION.zip"
echo "▸ Archiving"
rm -f "$ARCHIVE"
# `ditto -c -k --keepParent` produces the archive shape macOS expects, with the
# bundle's signature intact. A zip made any other way will fail the updater's
# signature check on the far side.
ditto -c -k --keepParent "build/Cue.app" "$ARCHIVE"

echo "▸ Verifying the archive still passes its own signature"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ditto -x -k "$ARCHIVE" "$WORK"
codesign --verify --deep --strict "$WORK/Cue.app"

echo "▸ Publishing"
git tag "v$VERSION"
git push -q origin main "v$VERSION"
gh release create "v$VERSION" "$ARCHIVE" \
    --title "Cue $VERSION" \
    --generate-notes

echo "▸ Done. Copies already installed will offer this within a day."
