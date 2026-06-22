#!/bin/bash
#
# Builds Rimote.app (Release) and packages a polished drag-to-install .dmg:
# a custom background with an arrow, the app and an Applications alias laid out
# side by side, a large icon size, hidden toolbar, and the app icon as the
# volume icon.
#
# Signing & notarization (automatic when credentials are present):
#   - If a "Developer ID Application" identity is in the keychain, the app and
#     the .dmg are signed with the hardened runtime + a secure timestamp.
#     Override the chosen identity with RIMOTE_SIGN_IDENTITY.
#   - If the notary credentials below are also set, the .dmg is submitted to
#     Apple's notary service and the ticket is stapled, so a downloaded copy
#     opens with a normal double-click (no right-click → Open):
#         RIMOTE_NOTARY_KEY     path to the App Store Connect API key (.p8)
#         RIMOTE_NOTARY_KEY_ID  the key's Key ID
#         RIMOTE_NOTARY_ISSUER  the issuer UUID
#   - With neither, it falls back to an ad-hoc signature (local-use only; the
#     first launch needs a right-click → Open to get past Gatekeeper).
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
ENTITLEMENTS="$REPO/Rimote/Resources/Rimote.entitlements"

# Resolve a Developer ID Application identity (explicit override, else auto-detect).
SIGN_ID="${RIMOTE_SIGN_IDENTITY:-}"
if [ -z "$SIGN_ID" ]; then
  SIGN_ID="$(security find-identity -v -p codesigning \
    | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')" || true
fi

rm -rf "$DIST"
mkdir -p "$DIST"

echo "==> Building $APP_NAME (Release)"
xcodebuild -project Rimote.xcodeproj -scheme "$APP_NAME" -configuration Release \
  -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build >/dev/null

APP="$DERIVED/Build/Products/Release/$APP_NAME.app"
[ -d "$APP" ] || { echo "build did not produce $APP"; exit 1; }

# Submit an artifact (app zip or dmg) to the notary service and wait. Stapling
# is done separately because the ticket attaches to the .app / .dmg, never to
# the upload zip (stapler can't write into a zip).
notarize_submit() {
  xcrun notarytool submit "$1" \
    --key "$RIMOTE_NOTARY_KEY" \
    --key-id "$RIMOTE_NOTARY_KEY_ID" \
    --issuer "$RIMOTE_NOTARY_ISSUER" \
    --wait
}

NOTARY_READY=""
if [ -n "$SIGN_ID" ] && [ -n "${RIMOTE_NOTARY_KEY:-}" ] \
   && [ -n "${RIMOTE_NOTARY_KEY_ID:-}" ] && [ -n "${RIMOTE_NOTARY_ISSUER:-}" ]; then
  NOTARY_READY="yes"
fi

if [ -n "$SIGN_ID" ]; then
  echo "==> Signing app with hardened runtime: $SIGN_ID"
  codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" --sign "$SIGN_ID" "$APP"
  codesign --verify --strict --verbose=1 "$APP"

  # Notarize + staple the app itself so the very first launch is accepted even
  # offline (the dmg gets its own ticket later). Zip is just the upload vehicle.
  if [ -n "$NOTARY_READY" ]; then
    echo "==> Notarizing the app (so it launches offline)…"
    APP_ZIP="$DIST/app.zip"
    ditto -c -k --keepParent "$APP" "$APP_ZIP"
    notarize_submit "$APP_ZIP"       # registers the app's cdhash with Apple
    rm -f "$APP_ZIP"
    xcrun stapler staple "$APP"      # staple ticket onto the .app bundle
    xcrun stapler validate "$APP"
  fi
else
  echo "==> No Developer ID identity found — ad-hoc signing (local use only)"
  codesign --force --deep --sign - "$APP"
fi

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

# Sign the disk image itself (Developer ID) so its signature matches the app.
if [ -n "$SIGN_ID" ]; then
  echo "==> Signing the .dmg"
  codesign --force --timestamp --sign "$SIGN_ID" "$DMG_OUT"
fi

# Notarize + staple the .dmg so opening the download is accepted offline too.
if [ -n "$NOTARY_READY" ]; then
  echo "==> Notarizing the .dmg…"
  notarize_submit "$DMG_OUT"
  xcrun stapler staple "$DMG_OUT"
  xcrun stapler validate "$DMG_OUT"
  spctl -a -t open --context context:primary-signature -v "$DMG_OUT" || true
else
  echo "==> Skipping notarization (set RIMOTE_NOTARY_KEY / _KEY_ID / _ISSUER to enable)"
fi

echo "==> Done: $DMG_OUT"
ls -lh "$DMG_OUT"
