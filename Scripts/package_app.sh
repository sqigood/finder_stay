#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Debug}"
PROJECT_PATH="$ROOT_DIR/FinderSessionRestore.xcodeproj"
DERIVED_DATA_PATH="$ROOT_DIR/.xcode-derived-data"

case "$CONFIGURATION" in
    debug)
        CONFIGURATION="Debug"
        ;;
    release)
        CONFIGURATION="Release"
        ;;
esac

xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme FinderSessionRestore \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    build

APP_DIR="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/FinderSessionRestore.app"

echo "$APP_DIR"
