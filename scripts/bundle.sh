#!/usr/bin/env bash
# Build seemd and assemble a macOS .app bundle (ad-hoc signed).
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP="seemd.app"
BIN_NAME="seemd"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BIN_PATH/$BIN_NAME" "$APP/Contents/MacOS/$BIN_NAME"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"

# Bundle SwiftPM resource bundles, if any.
find "$BIN_PATH" -maxdepth 1 -name "*.bundle" -exec cp -R {} "$APP/Contents/Resources/" \; 2>/dev/null || true

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "$APP" || echo "warning: codesign failed (continuing, ad-hoc)"

echo "==> Done: $ROOT/$APP"
