#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/manual"
COMBINED_MAIN="$BUILD_DIR/main.swift"
BINARY="$BUILD_DIR/TypingWithMyPets"
APP_DIR="$BUILD_DIR/TypingWithMyPets.app"
MODULE_CACHE_DIR="$BUILD_DIR/module-cache"
SDK_PATH="$(xcrun --show-sdk-path --sdk macosx)"
TARGET_TRIPLE="${TWMP_SWIFT_TARGET:-$(uname -m)-apple-macosx13.0}"

mkdir -p "$BUILD_DIR" "$MODULE_CACHE_DIR"
grep -v '^import TypingWithMyPetsCore$' "$ROOT_DIR/Sources/TypingWithMyPets/main.swift" > "$COMBINED_MAIN"

frameworks=(-framework AppKit -framework EventKit)
if [ -d "$SDK_PATH/System/Library/Frameworks/FoundationModels.framework" ]; then
  frameworks+=(-framework FoundationModels)
fi

swiftc \
  -target "$TARGET_TRIPLE" \
  -module-cache-path "$MODULE_CACHE_DIR" \
  "$ROOT_DIR/Sources/TypingWithMyPetsCore/ConversationEngine.swift" \
  "$ROOT_DIR/Sources/TypingWithMyPetsCore/TypingEngine.swift" \
  "$COMBINED_MAIN" \
  "${frameworks[@]}" \
  -o "$BINARY"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$BINARY" "$APP_DIR/Contents/MacOS/TypingWithMyPets"
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>TypingWithMyPets</string>
  <key>CFBundleIdentifier</key>
  <string>local.typing-with-my-pets</string>
  <key>CFBundleName</key>
  <string>Typing With My Pets</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSSupportsAutomaticTermination</key>
  <false/>
  <key>NSSupportsSuddenTermination</key>
  <false/>
  <key>NSRemindersUsageDescription</key>
  <string>Typing With My Pets uses Reminders only when you explicitly ask the pet to create a reminder.</string>
</dict>
</plist>
PLIST

printf '%s\n' "$APP_DIR"
