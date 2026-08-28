#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
INSTALL_ROOT="${HOOKYBAR_INSTALL_ROOT:-$HOME/Applications}"
APP_NAME="Hooky bar"
APP_PATH="$INSTALL_ROOT/$APP_NAME.app"
STAGING_DIR="$(mktemp -d)"
STAGED_APP="$STAGING_DIR/$APP_NAME.app"
trap 'rm -rf "$STAGING_DIR"' EXIT

"$PROJECT_DIR/Packaging/build-app.sh" "$STAGED_APP"

mkdir -p "$INSTALL_ROOT"
BACKUP_PATH="$INSTALL_ROOT/$APP_NAME.previous.app"
stop_installed_app() {
    local installed_path="$1"
    local existing_pid
    existing_pid="$(pgrep -f "^${installed_path}/Contents/MacOS/" | head -1 || true)"
    if [[ -n "$existing_pid" ]]; then
        # Stop the media adapter before its parent so it cannot survive an
        # update as an orphaned helper process.
        pkill -P "$existing_pid" 2>/dev/null || true
        kill "$existing_pid"
        for _ in {1..20}; do
            kill -0 "$existing_pid" 2>/dev/null || break
            sleep 0.05
        done
    fi
}

stop_installed_app "$APP_PATH"

if [[ -e "$APP_PATH" ]]; then
    rm -rf "$BACKUP_PATH"
    mv "$APP_PATH" "$BACKUP_PATH"
fi
mv "$STAGED_APP" "$APP_PATH"
open "$APP_PATH"
/usr/bin/osascript - "$APP_PATH" <<'APPLESCRIPT'
on run argv
    set appPath to item 1 of argv
    tell application "System Events"
        if exists login item "Hooky bar" then delete login item "Hooky bar"
        make login item at end with properties {name:"Hooky bar", path:appPath, hidden:false}
    end tell
end run
APPLESCRIPT

# The backup is useful only while replacing the bundle. Keeping it after a
# successful launch would leave an obsolete bundle identifier on disk.
rm -rf "$BACKUP_PATH"

echo "$APP_PATH"
