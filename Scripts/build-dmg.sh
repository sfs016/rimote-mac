#!/bin/bash
#
# Builds Rimote.app (Release) and packages a polished drag-to-install .dmg:
# a custom background with an arrow, the app and an Applications alias laid out
# side by side, a large icon size, hidden toolbar, and the app icon as the
# volume icon.
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
VOL="Rimote"
DERIVED="$REPO/DerivedData"
DIST="$REPO/dist"
DMG_RW="$DIST/rw.dmg"
DMG_OUT="$DIST/$APP_NAME.dmg"
BG="$DIST/dmg-bg.png"

rm -rf "$DIST"
mkdir -p "$DIST"

echo "==> Building $APP_NAME (Release)"
xcodebuild -project Rimote.xcodeproj -scheme "$APP_NAME" -configuration Release \
  -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build >/dev/null

APP="$DERIVED/Build/Products/Release/$APP_NAME.app"
[ -d "$APP" ] || { echo "build did not produce $APP"; exit 1; }

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP"

echo "==> Rendering background"
swift "$REPO/Scripts/make-dmg-background.swift" "$BG" >/dev/null

# Detach any stale volume from a previous run.
hdiutil detach "/Volumes/$VOL" >/dev/null 2>&1 || true

echo "==> Creating writable image"
hdiutil create -size 96m -fs HFS+ -volname "$VOL" -ov "$DMG_RW" >/dev/null
DEV="$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_RW" | grep '^/dev/' | head -1 | awk '{print $1}')"
MOUNT="/Volumes/$VOL"

echo "==> Populating"
cp -R "$APP" "$MOUNT/"
ln -s /Applications "$MOUNT/Applications"
mkdir "$MOUNT/.background"
cp "$BG" "$MOUNT/.background/dmg-bg.png"

# Use the app icon as the volume icon.
if [ -f "$APP/Contents/Resources/AppIcon.icns" ]; then
  cp "$APP/Contents/Resources/AppIcon.icns" "$MOUNT/.VolumeIcon.icns"
  SetFile -a C "$MOUNT" 2>/dev/null || true
fi

echo "==> Styling the Finder window"
osascript <<EOF || echo "   (Finder styling skipped — layout applies on a GUI session)"
with timeout of 90 seconds
  tell application "Finder"
    activate
    tell disk "$VOL"
      open
      delay 1.5
      set current view of container window to icon view
      set toolbar visible of container window to false
      set statusbar visible of container window to false
      set the bounds of container window to {200, 120, 860, 520}
      set theViewOptions to the icon view options of container window
      set arrangement of theViewOptions to not arranged
      set icon size of theViewOptions to 112
      set background picture of theViewOptions to file ".background:dmg-bg.png"
      set position of item "$APP_NAME.app" of container window to {180, 205}
      set position of item "Applications" of container window to {480, 205}
      delay 1
      update without registering applications
      delay 1.5
      close
    end tell
  end tell
end timeout
EOF

sync
echo "==> Finalizing"
hdiutil detach "$DEV" >/dev/null 2>&1 || hdiutil detach "$MOUNT" >/dev/null 2>&1 || true
hdiutil convert "$DMG_RW" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG_OUT" >/dev/null
rm -f "$DMG_RW" "$BG"

echo "==> Done: $DMG_OUT"
ls -lh "$DMG_OUT"
