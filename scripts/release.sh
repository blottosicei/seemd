#!/usr/bin/env bash
# Cut a Sparkle auto-update release of seemd — no Apple Developer account needed.
#
# What it does:
#   1. Bumps the version in Resources/Info.plist.
#   2. Builds + bundles seemd.app (scripts/bundle.sh, ad-hoc signed).
#   3. Zips the app (ditto, preserving signature & symlinks).
#   4. Signs the zip with the EdDSA key in your Keychain and (re)generates
#      appcast.xml pointing at the GitHub release download URL.
#   5. Creates the GitHub release and uploads the zip.
#   6. Commits + pushes appcast.xml so the live feed
#      (raw.githubusercontent.com/.../main/appcast.xml) advertises the update.
#
# Prereqs: `gh` authenticated, EdDSA private key in Keychain (generate_keys, run once).
#
# Usage: scripts/release.sh <version>     e.g. scripts/release.sh 0.2.0
set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "usage: scripts/release.sh <version>   (e.g. 0.2.0)" >&2
  exit 1
fi
TAG="v$VERSION"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REPO="blottosicei/seemd"
PLIST="$ROOT/Resources/Info.plist"
APP="$ROOT/seemd.app"
ARCHIVE_DIR="$ROOT/dist/archives"
ZIP_NAME="seemd-$VERSION.zip"
DL_PREFIX="https://github.com/$REPO/releases/download/$TAG/"

# Locate Sparkle's signing + appcast tools (fetched into .build by SwiftPM).
SIGN_UPDATE="$(find "$ROOT/.build/artifacts" -name 'sign_update' -path '*/bin/*' 2>/dev/null | head -n1)"
GEN_APPCAST="$(find "$ROOT/.build/artifacts" -name 'generate_appcast' 2>/dev/null | head -n1)"
if [ -z "$GEN_APPCAST" ]; then
  echo "error: generate_appcast not found — run 'swift package resolve' first" >&2
  exit 1
fi

echo "==> Bumping version to $VERSION in Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$PLIST"

echo "==> Building bundle"
"$ROOT/scripts/bundle.sh" release

echo "==> Zipping app -> $ZIP_NAME"
mkdir -p "$ARCHIVE_DIR"
rm -f "$ARCHIVE_DIR/$ZIP_NAME"
ditto -c -k --keepParent "$APP" "$ARCHIVE_DIR/$ZIP_NAME"

echo "==> Generating + signing appcast (EdDSA key from Keychain)"
# generate_appcast reads the version from the Info.plist inside the zip, signs
# the archive, and writes appcast.xml into the archive dir.
"$GEN_APPCAST" "$ARCHIVE_DIR" --download-url-prefix "$DL_PREFIX"
cp "$ARCHIVE_DIR/appcast.xml" "$ROOT/appcast.xml"

echo "==> Creating GitHub release $TAG and uploading $ZIP_NAME"
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  gh release upload "$TAG" "$ARCHIVE_DIR/$ZIP_NAME" --repo "$REPO" --clobber
else
  gh release create "$TAG" "$ARCHIVE_DIR/$ZIP_NAME" \
    --repo "$REPO" --title "$TAG" \
    --notes "seemd $VERSION. Auto-update via Sparkle. First-time install: right-click the app → Open (unsigned build)."
fi

echo "==> Committing appcast.xml + version bump"
git add appcast.xml Resources/Info.plist
git commit -m "release: $TAG" || echo "nothing to commit"
git push origin HEAD

echo "==> Done. Live feed: https://raw.githubusercontent.com/$REPO/main/appcast.xml"
echo "    Existing users will be offered $VERSION on next check."
