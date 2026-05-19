#!/usr/bin/env bash
# Produce dist/seemd.dmg from a built seemd.app (ad-hoc signed).
# Usage: ./scripts/make-dmg.sh
#   If seemd.app is missing, bundle.sh is run first.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/seemd.app"
DIST="$ROOT/dist"
DMG="$DIST/seemd.dmg"
STAGE="$(mktemp -d)"

cleanup() {
  rm -rf "$STAGE"
}
trap cleanup EXIT

# Build the app bundle if it does not exist yet.
if [[ ! -d "$APP" ]]; then
  echo "==> seemd.app not found — running bundle.sh first"
  "$ROOT/scripts/bundle.sh" release
fi

echo "==> Staging: $STAGE"
cp -R "$APP" "$STAGE/seemd.app"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$DIST"

echo "==> Creating DMG: $DMG"
hdiutil create \
  -volname seemd \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG"

echo "==> Done: $DMG"
