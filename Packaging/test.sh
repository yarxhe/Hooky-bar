#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
TESTING_PLUGIN="/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
TESTING_FRAMEWORK="/Library/Developer/CommandLineTools/Library/Developer/Frameworks/Testing.framework"
TESTING_INTEROP="/Library/Developer/CommandLineTools/Library/Developer/usr/lib/lib_TestingInterop.dylib"

cd "$PROJECT_DIR"

# Полный Xcode сам подключает Swift Testing. Отдельные Command Line Tools 27
# содержат framework и macro plugin, но пока не добавляют их в rpath SwiftPM.
if [[ -f "$TESTING_PLUGIN" && -d "$TESTING_FRAMEWORK" && -f "$TESTING_INTEROP" ]]; then
    PRODUCTS_DIR="$(swift build --show-bin-path)"
    mkdir -p "$PRODUCTS_DIR/PackageFrameworks"
    ditto "$TESTING_FRAMEWORK" "$PRODUCTS_DIR/PackageFrameworks/Testing.framework"
    cp "$TESTING_INTEROP" "$PRODUCTS_DIR/lib_TestingInterop.dylib"
    swift test \
        -Xswiftc -load-plugin-library \
        -Xswiftc "$TESTING_PLUGIN"
else
    swift test
fi
