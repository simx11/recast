#!/usr/bin/env bash
# Builds build/Recast.app. Usage: scripts/build.sh [release|debug]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIGURATION="${1:-release}"
APP="build/Recast.app"

swift build -c "$CONFIGURATION" --product Recast
BIN="$(swift build -c "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Recast" "$APP/Contents/MacOS/Recast"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature by default. Set SIGNING_IDENTITY to sign with a real certificate.
codesign --force --options runtime --sign "${SIGNING_IDENTITY:--}" "$APP"
echo "Built $APP"
