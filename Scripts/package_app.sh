#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-debug}"
APP_DIR="$ROOT_DIR/.build/FinderSessionRestore.app"
EXECUTABLE="$ROOT_DIR/.build/$CONFIGURATION/FinderSessionRestore"

mkdir -p "$ROOT_DIR/.build/home" "$ROOT_DIR/.build/module-cache"
export HOME="$ROOT_DIR/.build/home"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"

swift build --disable-sandbox -c "$CONFIGURATION"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/FinderSessionRestore"
chmod +x "$APP_DIR/Contents/MacOS/FinderSessionRestore"

echo "$APP_DIR"
