#!/usr/bin/env bash
#
# Prepares a release (§69).
#
#   ./Scripts/release.sh 0.2.0
#
# Sets the version, builds and tests everything locally so a broken release
# fails on your machine rather than in CI, then creates the tag. Pushing the
# tag is left to you, deliberately: pushing is the irreversible step, and it is
# the one worth typing yourself.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

VERSION="${1:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "usage: ./Scripts/release.sh <major.minor.patch>" >&2
    exit 2
fi

TAG="v$VERSION"

command -v git >/dev/null || { echo "error: git not found" >&2; exit 1; }

if [[ -n "$(git status --porcelain)" ]]; then
    echo "error: the working tree has uncommitted changes." >&2
    echo "       Commit or stash them first — a release should be reproducible." >&2
    exit 1
fi

if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "error: tag $TAG already exists." >&2
    exit 1
fi

if ! grep -q "^## \[$VERSION\]" CHANGELOG.md; then
    echo "error: CHANGELOG.md has no '## [$VERSION]' section." >&2
    echo "       Write the entry before tagging; nobody writes it afterwards." >&2
    exit 1
fi

echo "▸ Setting the version to $VERSION"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist

echo "▸ Testing"
./Scripts/test.sh

echo "▸ Building the disk image"
./Scripts/create-dmg.sh

echo "▸ Committing and tagging"
git add Resources/Info.plist CHANGELOG.md
git commit -m "Release $VERSION"
git tag -a "$TAG" -m "Tray $VERSION"

cat <<SUMMARY

▸ Ready.

  Local image:  dist/Tray-$VERSION.dmg

  Push when you are happy with it:

      git push origin main
      git push origin $TAG

  The tag starts .github/workflows/release.yml, which rebuilds from a clean
  checkout, notarizes when signing secrets are configured, and publishes the
  disk image and its checksum to the GitHub release.

SUMMARY
