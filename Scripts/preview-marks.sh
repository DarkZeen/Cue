#!/bin/bash
#
# Renders every plaque animation, at eight moments and stopped, onto one sheet.
#
# An animation is the one kind of drawing you cannot check by running the app:
# it is 26 pixels wide, it only appears while music is playing, and it has
# already moved by the time you have looked at it. This freezes it.
#
# It compiles the real views rather than a copy of them — that is the whole
# point, and it is why the style structs are internal rather than file-private.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p build

BINARY="$(mktemp -d)/marks"

swiftc -O -o "$BINARY" \
    Sources/Cue/UI/NowPlayingStyles.swift \
    Sources/Cue/UI/CueMark.swift \
    Sources/Cue/UI/CueWavePath.swift \
    Sources/Cue/UI/CueLogoPath.swift \
    Sources/Cue/UI/PlaqueAnimation.swift \
    Scripts/preview-marks.swift

"$BINARY" build/marks.png
echo "▸ build/marks.png"
