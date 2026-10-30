#!/usr/bin/env bash
# Builds build/Rev.app with SwiftPM + the Command Line Tools (no Xcode needed).
#
# Usage:
#   scripts/build-app.sh            # arm64 (default)
#   ARCHS="arm64 x86_64" scripts/build-app.sh   # universal
#   SIGN_IDENTITY="Developer ID Application: ..." scripts/build-app.sh   # default: ad-hoc (-)
#
# Then: open build/Rev.app    or    scripts/make-dmg.sh build/Rev.app
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ARCHS="${ARCHS:-arm64}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
PRODUCT_NAME=Rev
EXECUTABLE_NAME=Rev
BUNDLE_ID=com.trevorgerald.rev
setting() { sed -n "s/^ *$1: *\"\{0,1\}\([^\"]*\)\"\{0,1\} *\$/\1/p" project.yml | head -n1; }
MARKETING_VERSION="$(setting MARKETING_VERSION)"; MARKETING_VERSION="${MARKETING_VERSION:-0.1.0}"
CURRENT_PROJECT_VERSION="$(setting CURRENT_PROJECT_VERSION)"; CURRENT_PROJECT_VERSION="${CURRENT_PROJECT_VERSION:-1}"
MACOSX_DEPLOYMENT_TARGET="$(setting MACOSX_DEPLOYMENT_TARGET)"; MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}"

log() { printf '==> %s\n' "$*"; }

arch_args=()
for a in $ARCHS; do arch_args+=(--arch "$a"); done
log "swift build -c release ${arch_args[*]}"
swift build -c release "${arch_args[@]}"
BIN_DIR="$(swift build -c release "${arch_args[@]}" --show-bin-path)"

APP="$ROOT/build/$PRODUCT_NAME.app"
log "Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXECUTABLE_NAME" "$APP/Contents/MacOS/$EXECUTABLE_NAME"

# Info.plist: substitute the Xcode build-setting placeholders.
sed -e "s/\$(EXECUTABLE_NAME)/$EXECUTABLE_NAME/g" \
    -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$BUNDLE_ID/g" \
    -e "s/\$(PRODUCT_NAME)/$PRODUCT_NAME/g" \
    -e "s/\$(MARKETING_VERSION)/$MARKETING_VERSION/g" \
    -e "s/\$(CURRENT_PROJECT_VERSION)/$CURRENT_PROJECT_VERSION/g" \
    -e "s/\$(MACOSX_DEPLOYMENT_TARGET)/$MACOSX_DEPLOYMENT_TARGET/g" \
    App/Resources/Info.plist > "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
if grep -q '\$(' "$APP/Contents/Info.plist"; then
  echo "error: unsubstituted build setting in Info.plist" >&2; exit 1
fi
plutil -lint "$APP/Contents/Info.plist" >/dev/null
printf 'APPL????' > "$APP/Contents/PkgInfo"

# SwiftPM resource bundles (emoji.json lives in RevCore_RevCore.bundle).
for b in "$BIN_DIR"/*.bundle; do
  [[ -e "$b" ]] && cp -R "$b" "$APP/Contents/Resources/"
done

# Xcode compiles this into Assets.car; the hand-assembled SwiftPM app needs the source image.
MENU_BAR_ICON="$APP/Contents/Resources/MenuBarIcon.svg"
cp App/Resources/Assets.xcassets/MenuBarIcon.imageset/menubar-icon.svg "$MENU_BAR_ICON"
[[ -s "$MENU_BAR_ICON" ]] || { echo "error: menu bar icon was not bundled" >&2; exit 1; }

# App icon.
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
cp App/Resources/Assets.xcassets/AppIcon.appiconset/icon_*.png "$ICONSET"/
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

log "Signing ($SIGN_IDENTITY)"
codesign --force --deep --sign "$SIGN_IDENTITY" \
  --entitlements App/Resources/Rev.entitlements "$APP"
codesign --verify --strict --verbose=1 "$APP"
log "Built $APP ($MARKETING_VERSION, $ARCHS)"
