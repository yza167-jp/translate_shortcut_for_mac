#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
CONFIGURATION="${CONFIGURATION:-release}"
APP_PATH="$PROJECT_DIR/dist/Translate Shortcut.app"

swift build -c "$CONFIGURATION"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_DIR/TranslateShortcut" "$APP_PATH/Contents/MacOS/TranslateShortcut"
cp Resources/Info.plist "$APP_PATH/Contents/Info.plist"
swift scripts/generate-icon.swift "$PROJECT_DIR/.build/AppIcon.iconset"
iconutil -c icns "$PROJECT_DIR/.build/AppIcon.iconset" -o "$APP_PATH/Contents/Resources/AppIcon.icns"
codesign --force --sign "${CODE_SIGN_IDENTITY:--}" --identifier io.github.yza167-jp.translate-shortcut "$APP_PATH"
codesign --verify --strict "$APP_PATH"
printf '\nBuilt: %s\n' "$APP_PATH"
