#!/bin/bash
set -e

REPO="$(cd "$(dirname "$0")" && pwd)"
APP="/Applications/TrainTracker.app"
BINARY="$APP/Contents/MacOS/TrainTracker"

echo "Building..."
swift build -c release --package-path "$REPO"

echo "Stopping running instance..."
pkill -x TrainTracker 2>/dev/null || true
sleep 0.5

echo "Installing..."
cp "$REPO/.build/arm64-apple-macosx/release/TrainTracker" "$BINARY"

echo "Re-signing..."
codesign --remove-signature "$APP"
codesign -s - "$APP"

echo "Launching..."
open "$APP"

echo "Done."
