#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"
swift build -c release --product HookyPanelPerformanceCheck
PRODUCTS_DIR="$(swift build -c release --show-bin-path)"
exec "$PRODUCTS_DIR/HookyPanelPerformanceCheck" "$@"
