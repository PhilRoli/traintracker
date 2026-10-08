#!/bin/bash
set -e

VERSION="${1:?Usage: package-app.sh <version>}"
BUILD_VERSION="${VERSION%%-*}"   # CFBundleVersion must be numeric, so drop any -suffix
REPO="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO/.build/package"
APP="$BUILD_DIR/TrainTracker.app"

echo "Building universal binary..."
swift build -c release --package-path "$REPO" --arch arm64 --arch x86_64

BINARY="$REPO/.build/apple/Products/Release/TrainTracker"
if [ ! -f "$BINARY" ]; then
    echo "error: expected universal binary at $BINARY, not found" >&2
    exit 1
fi

echo "Assembling app bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/TrainTracker"

sed -e "s/\$(VERSION)/$VERSION/g" -e "s/\$(BUILD_VERSION)/$BUILD_VERSION/g" "$REPO/Packaging/Info.plist" > "$APP/Contents/Info.plist"

ICON="$REPO/Packaging/AppIcon.icns"
if [ ! -f "$ICON" ]; then
    echo "error: $ICON not found (run scripts/make-icon.sh)" >&2
    exit 1
fi
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"

echo "Signing (ad-hoc)..."
codesign --force --options runtime -s - "$APP"

echo "Packaged: $APP"
