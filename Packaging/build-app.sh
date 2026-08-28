#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
OUTPUT_APP="${1:?Передайте путь к выходному Hooky bar.app}"
if [[ "${OUTPUT_APP:t}" != "Hooky bar.app" ]]; then
    echo "Выходной путь должен заканчиваться точным именем 'Hooky bar.app'" >&2
    exit 64
fi
if [[ -e "$OUTPUT_APP" ]]; then
    echo "Отказываюсь перезаписывать существующий путь: $OUTPUT_APP" >&2
    exit 73
fi
STAGING_DIR="$(mktemp -d)"
STAGED_APP="$STAGING_DIR/Hooky bar.app"
trap 'rm -rf "$STAGING_DIR"' EXIT

cd "$PROJECT_DIR"
swift build -c release
PRODUCTS_DIR="$(swift build -c release --show-bin-path)"

mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$PROJECT_DIR/Packaging/Info.plist" "$STAGED_APP/Contents/Info.plist"
cp "$PROJECT_DIR/Packaging/HookyBar.icns" "$STAGED_APP/Contents/Resources/HookyBar.icns"
ditto "$PROJECT_DIR/Packaging/en.lproj" "$STAGED_APP/Contents/Resources/en.lproj"
ditto "$PROJECT_DIR/Packaging/ru.lproj" "$STAGED_APP/Contents/Resources/ru.lproj"
cp "$PRODUCTS_DIR/HookyBar" "$STAGED_APP/Contents/MacOS/HookyBar"
cp "$PRODUCTS_DIR/libMediaRemoteAdapter.dylib" "$STAGED_APP/Contents/MacOS/libMediaRemoteAdapter.dylib"
ditto "$PRODUCTS_DIR/MediaRemoteAdapter_MediaRemoteAdapter.bundle" \
      "$STAGED_APP/Contents/Resources/MediaRemoteAdapter_MediaRemoteAdapter.bundle"
ditto "$PRODUCTS_DIR/HookyBar_HookyBar.bundle" \
      "$STAGED_APP/Contents/Resources/HookyBar_HookyBar.bundle"

# Локальная ad-hoc подпись сохраняет стабильное designated requirement между
# сборками. Developer ID для open-source beta не требуется.
codesign --force --sign - "$STAGED_APP/Contents/MacOS/libMediaRemoteAdapter.dylib"
codesign --force --sign - \
    --requirements '=designated => identifier "com.yarxhe.HookyBar"' \
    "$STAGED_APP"

mkdir -p "${OUTPUT_APP:h}"
mv "$STAGED_APP" "$OUTPUT_APP"
echo "$OUTPUT_APP"
