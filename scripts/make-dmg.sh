#!/usr/bin/env bash
# Build seemd.app (via bundle.sh) and assemble a styled install DMG:
#   ┌────────────────────────────────────────────────────────┐
#   │   [seemd.app]         →         [Applications]         │
#   │       Drag seemd to Applications to install            │
#   └────────────────────────────────────────────────────────┘
#
# Pipeline: build .app -> generate background -> create UDRW dmg ->
# mount -> copy app + Applications symlink + .background -> AppleScript
# Finder layout (icon view, positions, background image) -> detach ->
# convert to UDZO compressed final dmg.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VOL_NAME="seemd"
DMG_OUT="$ROOT/dist/seemd.dmg"
APP="$ROOT/seemd.app"
BG_SRC="$ROOT/Resources/dmg-background.png"
BG_GEN="$ROOT/scripts/make-dmg-bg.swift"
STAGING="$(mktemp -d -t seemd-dmg.XXXXXX)"
WORK_DMG="$STAGING/work.dmg"
EMPTY_DIR="$STAGING/empty"
MOUNT_POINT="/Volumes/$VOL_NAME"

cleanup() {
    if [ -d "$MOUNT_POINT" ]; then
        hdiutil detach "$MOUNT_POINT" -force >/dev/null 2>&1 || true
    fi
    rm -rf "$STAGING"
}
trap cleanup EXIT

# 1. Build the .app if missing.
if [ ! -d "$APP" ]; then
    echo "==> seemd.app not found — running bundle.sh first"
    "$ROOT/scripts/bundle.sh" release
fi

# 2. Regenerate the background if the source generator is newer or PNG is missing.
if [ ! -f "$BG_SRC" ] || [ "$BG_GEN" -nt "$BG_SRC" ]; then
    echo "==> Generating DMG background"
    swift "$BG_GEN" "$BG_SRC"
fi

mkdir -p "$ROOT/dist"
rm -f "$DMG_OUT"

# 3. Create a writable (UDRW) DMG sized for the app + headroom.
APP_KB="$(du -sk "$APP" | awk '{print $1}')"
WORK_KB=$(( APP_KB + 61440 ))   # +60 MB for background, .DS_Store, slack

mkdir -p "$EMPTY_DIR"
echo "==> Creating writable DMG (~${WORK_KB} KB)"
hdiutil create -srcfolder "$EMPTY_DIR" -volname "$VOL_NAME" \
    -fs HFS+ -fsargs "-c c=64,a=16,e=16" \
    -format UDRW -size "${WORK_KB}k" -ov "$WORK_DMG" >/dev/null

echo "==> Mounting"
hdiutil attach "$WORK_DMG" -mountpoint "$MOUNT_POINT" \
    -nobrowse -noverify -noautoopen >/dev/null

echo "==> Populating volume"
cp -R "$APP" "$MOUNT_POINT/seemd.app"
ln -s /Applications "$MOUNT_POINT/Applications"
mkdir -p "$MOUNT_POINT/.background"
cp "$BG_SRC" "$MOUNT_POINT/.background/dmg-background.png"

# 4. Apply Finder window layout (icon view, positions, background image).
echo "==> Applying Finder layout"
osascript <<EOF
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        delay 0.6
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set pathbar visible of container window to false
        -- Window {left, top, right, bottom} on screen. Content ≈ 720x420.
        set the bounds of container window to {360, 180, 1080, 600}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 128
        set text size of theViewOptions to 13
        set background picture of theViewOptions to file ".background:dmg-background.png"
        -- Icon positions are top-left origin within the window content.
        set position of item "seemd.app" of container window to {180, 180}
        set position of item "Applications" of container window to {540, 180}
        update without registering applications
        delay 1.2
        close
    end tell
end tell
EOF

# 5. Detach and compress to UDZO read-only final.
echo "==> Finalizing"
sync
hdiutil detach "$MOUNT_POINT" -force >/dev/null

hdiutil convert "$WORK_DMG" -format UDZO -imagekey zlib-level=9 \
    -o "$DMG_OUT" >/dev/null

echo "==> Done: $DMG_OUT"
