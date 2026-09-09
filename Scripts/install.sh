#!/usr/bin/env bash
#
# Installs Cue into /Applications, properly.
#
#   ./Scripts/install.sh
#
# Running Cue out of build/ works, and costs you two things that matter: the
# app has no stable home for macOS to register (so Launch at Login and the
# cue:// shortcut point at a directory you might move), and every rebuild
# replaces the bundle underneath the running copy. This puts it where an
# application lives.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# A stable signature first. Without it the keychain treats every build as a
# different application and asks for your login password on each launch, and
# the updater cannot verify a new build against this one.
if ! security find-identity -p codesigning 2>/dev/null | grep -q "Cue Signing"; then
    echo "▸ Creating a local signing identity first"
    ./Scripts/setup-signing.sh
fi

./Scripts/build.sh

echo "▸ Quitting any running copy"
osascript -e 'quit app "Cue"' 2>/dev/null || true
pkill -x Cue 2>/dev/null || true
sleep 1

echo "▸ Installing to /Applications"
rm -rf "/Applications/Cue.app"
# `ditto` rather than `cp -R`: it preserves the extended attributes and symlinks
# a signed bundle needs, and a copy that breaks the signature is a copy macOS
# will refuse to launch.
ditto "build/Cue.app" "/Applications/Cue.app"

echo "▸ Registering with Launch Services"
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
    -f "/Applications/Cue.app" 2>/dev/null || true

echo "▸ Launching"
open "/Applications/Cue.app"

cat <<'DONE'

  Installed. Two things worth doing once:

    • Bind a key to `open cue://open`, or set one in Cue's Settings.
    • Settings → Accounts, to connect your YouTube account.

  Cue checks for updates on its own and will offer to install them.

DONE
