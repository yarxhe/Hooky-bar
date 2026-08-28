#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/Packaging/Info.plist")"
RELEASE_LABEL="${HOOKYBAR_RELEASE_LABEL:-$VERSION}"
if [[ ! "$RELEASE_LABEL" =~ '^[A-Za-z0-9._-]+$' ]]; then
    echo "HOOKYBAR_RELEASE_LABEL может содержать только A-Z, a-z, 0-9, точку, дефис и подчёркивание" >&2
    exit 64
fi
DIST_DIR="$PROJECT_DIR/dist"
STAGING_DIR="$(mktemp -d)"
APP_PATH="$STAGING_DIR/Hooky bar.app"
DMG_ROOT="$STAGING_DIR/dmg"
DMG_PATH="$DIST_DIR/Hooky-bar-$RELEASE_LABEL.dmg"
trap 'rm -rf "$STAGING_DIR"' EXIT

"$PROJECT_DIR/Packaging/build-app.sh" "$APP_PATH"
mkdir -p "$DMG_ROOT"
ditto "$APP_PATH" "$DMG_ROOT/Hooky bar.app"
ln -s /Applications "$DMG_ROOT/Applications"
mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"
hdiutil create -quiet -volname "Hooky bar $RELEASE_LABEL" \
    -srcfolder "$DMG_ROOT" -ov -format UDZO "$DMG_PATH"

echo "$DMG_PATH"
