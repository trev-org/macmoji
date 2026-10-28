#!/usr/bin/env bash
# Builds dist/Macmoji-<version>.dmg with the classic "drag to Applications" window.
# Runs on macOS only.
#
# Usage:
#   scripts/make-dmg.sh                 # build Release via xcodegen + xcodebuild, then package
#   scripts/make-dmg.sh path/to/Macmoji.app   # package an already-built app
#   scripts/make-dmg.sh --swiftpm       # no Xcode: build with scripts/build-app.sh (SwiftPM), then package
#
# Optional environment:
#   DEVELOPER_ID_APPLICATION  e.g. "Developer ID Application: Trevor Gerald (ABCDE12345)".
#                             Signs the app (hardened runtime, timestamp) and the DMG.
#   NOTARY_PROFILE            notarytool keychain profile (xcrun notarytool store-credentials).
#                             Submits the DMG, waits, then staples. Requires DEVELOPER_ID_APPLICATION.
#   SKIP_FINDER_LAYOUT=1      Skip the Finder AppleScript styling (headless CI without a GUI session).
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: make-dmg.sh must run on macOS" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
DIST="$ROOT/dist"
BUILD="$ROOT/build"
BG1="$ROOT/packaging/dmg-background.png"
BG2="$ROOT/packaging/dmg-background@2x.png"

# Window layout in points; keep in sync with packaging/make-art.py.
WIN_W=660; WIN_H=400; ICON_SIZE=128
APP_X=180; APPS_X=480; ICON_Y=190

log() { printf '==> %s\n' "$*"; }

# 1. Get the app.
if [[ "${1:-}" == "--swiftpm" ]] || { [[ $# -eq 0 ]] && ! xcodebuild -version >/dev/null 2>&1; }; then
  log "Building with SwiftPM (scripts/build-app.sh)"
  "$ROOT/scripts/build-app.sh"
  APP="$BUILD/Macmoji.app"
elif [[ $# -ge 1 ]]; then
  APP="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
else
  command -v xcodegen >/dev/null || { echo "error: brew install xcodegen" >&2; exit 1; }
  log "Generating project and building Release"
  xcodegen generate
  xcodebuild -project Macmoji.xcodeproj -scheme Macmoji -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$BUILD" \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build
  APP="$BUILD/Build/Products/Release/Macmoji.app"
fi
[[ -d "$APP" ]] || { echo "error: $APP not found" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || true)"
# shellcheck disable=SC2016 # literal "$(" means an unexpanded build setting
if [[ -z "$VERSION" || "$VERSION" == *'$('* ]]; then
  VERSION="$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' project.yml | head -n1)"
fi
[[ -n "$VERSION" ]] || { echo "error: could not determine version" >&2; exit 1; }
DMG="$DIST/Macmoji-$VERSION.dmg"
log "Packaging Macmoji $VERSION from $APP"

# 2. Sign the app.
SIGNED=0
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  log "Signing app with hardened runtime: $DEVELOPER_ID_APPLICATION"
  codesign --force --deep --options runtime --timestamp \
    --entitlements "$ROOT/App/Resources/Macmoji.entitlements" \
    --sign "$DEVELOPER_ID_APPLICATION" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
  SIGNED=1
else
  log "DEVELOPER_ID_APPLICATION not set: ad-hoc signing"
  codesign --force --deep --sign - --entitlements "$ROOT/App/Resources/Macmoji.entitlements" "$APP"
fi

# 3. Stage.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/Macmoji.app"
mkdir -p "$DIST"
rm -f "$DMG"

# Retina background: combine 1x and @2x into one multi-resolution TIFF when possible.
BG="$BG1"
if command -v tiffutil >/dev/null && [[ -f "$BG2" ]]; then
  tiffutil -cathidpicheck "$BG1" "$BG2" -out "$STAGE/background.tiff" >/dev/null
  BG="$STAGE/background.tiff"
fi

ICNS=""
if command -v iconutil >/dev/null; then
  ICONSET="$STAGE/Macmoji.iconset"
  mkdir -p "$ICONSET"
  cp "$ROOT"/App/Resources/Assets.xcassets/AppIcon.appiconset/icon_*.png "$ICONSET"/
  iconutil -c icns "$ICONSET" -o "$STAGE/VolumeIcon.icns" && ICNS="$STAGE/VolumeIcon.icns"
  rm -rf "$ICONSET"
fi
SRC="$STAGE/src"
mkdir -p "$SRC"
mv "$STAGE/Macmoji.app" "$SRC/"

# 4. Build the DMG.
if command -v create-dmg >/dev/null; then
  log "Building DMG with create-dmg"
  args=(
    --volname "Macmoji"
    --background "$BG"
    --window-pos 200 120
    --window-size "$WIN_W" "$WIN_H"
    --icon-size "$ICON_SIZE"
    --text-size 13
    --icon "Macmoji.app" "$APP_X" "$ICON_Y"
    --hide-extension "Macmoji.app"
    --app-drop-link "$APPS_X" "$ICON_Y"
    --hdiutil-quiet
    --overwrite
  )
  [[ -n "$ICNS" ]] && args+=(--volicon "$ICNS")
  [[ "${SKIP_FINDER_LAYOUT:-0}" == 1 ]] && args+=(--skip-jenkins)
  create-dmg "${args[@]}" "$DMG" "$SRC"
else
  log "create-dmg not found (brew install create-dmg); falling back to hdiutil + AppleScript"
  RW="$STAGE/rw.dmg"
  ln -s /Applications "$SRC/Applications"
  mkdir -p "$SRC/.background"
  cp "$BG" "$SRC/.background/background.${BG##*.}"
  hdiutil create -quiet -srcfolder "$SRC" -volname Macmoji -fs HFS+ -format UDRW -ov "$RW"
  MOUNT_DIR="$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -n1)"
  [[ -n "$MOUNT_DIR" ]] || { echo "error: could not mount $RW" >&2; exit 1; }
  if [[ -n "$ICNS" ]]; then
    cp "$ICNS" "$MOUNT_DIR/.VolumeIcon.icns"
    SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
  fi
  if [[ "${SKIP_FINDER_LAYOUT:-0}" != 1 ]]; then
    VOL="$(basename "$MOUNT_DIR")"
    osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, $((200 + WIN_W)), $((120 + WIN_H))}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to $ICON_SIZE
    set text size of opts to 13
    set background picture of opts to file ".background:background.${BG##*.}"
    set position of item "Macmoji.app" of container window to {$APP_X, $ICON_Y}
    set position of item "Applications" of container window to {$APPS_X, $ICON_Y}
    set extension hidden of item "Macmoji.app" to true
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT
  fi
  sync
  hdiutil detach -quiet "$MOUNT_DIR" || { sleep 3; hdiutil detach -force -quiet "$MOUNT_DIR"; }
  hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG"
fi

# 5. Sign + notarize the DMG.
if [[ "$SIGNED" == 1 ]]; then
  log "Signing DMG"
  codesign --force --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$DMG"
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    log "Notarizing with profile $NOTARY_PROFILE (this can take a few minutes)"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG" || true
  else
    log "NOTARY_PROFILE not set: signed but NOT notarized"
  fi
elif [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo "warning: NOTARY_PROFILE is set but DEVELOPER_ID_APPLICATION is not; skipping notarization" >&2
fi

log "Wrote $DMG"
if [[ "$SIGNED" != 1 || -z "${NOTARY_PROFILE:-}" ]]; then
  cat <<'NOTE'

NOTE: this DMG is not notarized. It works on this Mac, but on other Macs Gatekeeper will
refuse to open Macmoji ("cannot be opened because Apple cannot check it for malicious
software" / "damaged"). Recipients can right-click → Open, or allow it in System Settings →
Privacy & Security, or run: xattr -dr com.apple.quarantine /Applications/Macmoji.app
For a clean install on any Mac, set DEVELOPER_ID_APPLICATION and NOTARY_PROFILE (see README).
NOTE
fi
