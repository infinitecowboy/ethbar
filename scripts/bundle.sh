#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="EthBar"
APP_BUNDLE="$PROJECT_DIR/.build/release/${APP_NAME}.app"

echo "Building release binary…"
cd "$PROJECT_DIR"
swift build -c release

echo "Creating app bundle…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp ".build/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

echo "Installing to /Applications…"
cp -R "$APP_BUNDLE" "/Applications/${APP_NAME}.app"

echo "Done! App bundle at: $APP_BUNDLE"
echo "Installed to: /Applications/${APP_NAME}.app"
echo "Run with: open /Applications/${APP_NAME}.app"
