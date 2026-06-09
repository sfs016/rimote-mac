#!/bin/bash
#
# Builds Rimote.app (Release) and packages a drag-to-install .dmg.
#
# The app is ad-hoc signed (no Apple Developer account required). Because it
# isn't notarized, the first launch needs a right-click → Open to get past
# Gatekeeper; this is expected until the app is signed + notarized for release.
#
# Usage:  Scripts/build-dmg.sh
# Output: dist/Rimote.dmg

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

APP_NAME="Rimote"
DERIVED="$REPO/DerivedData"
DIST="$REPO/dist"

rm -rf "$DIST"
mkdir -p "$DIST"

echo "==> Building $APP_NAME (Release)"
xcodebuild -project Rimote.xcodeproj -scheme "$APP_NAME" -configuration Release \
  -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build >/dev/null

APP="$DERIVED/Build/Products/Release/$APP_NAME.app"
[ -d "$APP" ] || { echo "build did not produce $APP"; exit 1; }

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP"

echo "==> Staging disk image contents"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> Creating DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO \
  "$DIST/$APP_NAME.dmg" >/dev/null
rm -rf "$STAGE"

echo "==> Done: $DIST/$APP_NAME.dmg"
ls -lh "$DIST/$APP_NAME.dmg"
