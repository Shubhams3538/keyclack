#!/usr/bin/env bash
# Builds KeyClack.app into ./build.
#   scripts/build-app.sh            release build, ad-hoc signed
#   scripts/build-app.sh debug      debug build
#   CODESIGN_IDENTITY="Apple Development: you@example.com (TEAMID)" scripts/build-app.sh
#
# With ad-hoc signing ("-") macOS identifies the app by its code hash, so the Input
# Monitoring permission has to be granted again after every rebuild. Signing with a real
# identity (a free Apple Development certificate from Xcode works) keeps it across rebuilds.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
IDENTITY="${CODESIGN_IDENTITY:--}"
APP="build/KeyClack.app"

swift build -c "$CONFIG" --product KeyClack
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/KeyClack" "$APP/Contents/MacOS/KeyClack"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign "$IDENTITY" "$APP"

echo "Built $APP"
echo "Run it with:  open $APP"
