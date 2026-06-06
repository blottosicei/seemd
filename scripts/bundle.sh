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

# App icon (referenced by Info.plist CFBundleIconFile = AppIcon).
if [ -f "Resources/AppIcon.icns" ]; then
  cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# Document icon (referenced by Info.plist CFBundleDocumentTypes /
# CFBundleTypeIconFile = DocumentIcon). Used by Finder as the .md file icon.
if [ -f "Resources/DocumentIcon.icns" ]; then
  cp "Resources/DocumentIcon.icns" "$APP/Contents/Resources/DocumentIcon.icns"
fi

# Bundle SwiftPM resource bundles, if any.
find "$BIN_PATH" -maxdepth 1 -name "*.bundle" -exec cp -R {} "$APP/Contents/Resources/" \; 2>/dev/null || true

# Embed Sparkle.framework (auto-update engine). SwiftPM links against the
# xcframework in .build/artifacts but does NOT copy it into the bundle, so we
# do it here and point the executable's rpath at Contents/Frameworks.
echo "==> Embedding Sparkle.framework"
SPARKLE_FW="$(find "$ROOT/.build/artifacts" -path '*macos-arm64_x86_64/Sparkle.framework' -type d 2>/dev/null | head -n1)"
if [ -z "$SPARKLE_FW" ]; then
  SPARKLE_FW="$(find "$ROOT/.build/artifacts" -name 'Sparkle.framework' -type d 2>/dev/null | head -n1)"
fi
if [ -z "$SPARKLE_FW" ]; then
  echo "error: Sparkle.framework not found under .build/artifacts (run 'swift package resolve')" >&2
  exit 1
fi
mkdir -p "$APP/Contents/Frameworks"
cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"

# Ensure the executable can resolve @rpath/Sparkle.framework from the bundle.
if ! otool -l "$APP/Contents/MacOS/$BIN_NAME" | grep -q "@executable_path/../Frameworks"; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" \
    "$APP/Contents/MacOS/$BIN_NAME"
fi

echo "==> Ad-hoc code signing (inside-out: framework, then app)"
# Sign the embedded framework (and its nested XPC services / helper apps)
# before the outer app, as required for a valid signature.
codesign --force --deep --sign - --timestamp=none \
  "$APP/Contents/Frameworks/Sparkle.framework" \
  || echo "warning: framework codesign failed (continuing, ad-hoc)"
codesign --force --deep --sign - --timestamp=none "$APP" \
  || echo "warning: codesign failed (continuing, ad-hoc)"

echo "==> Done: $ROOT/$APP"
