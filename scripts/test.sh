#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/manual-tests"
MODULE_CACHE_DIR="$BUILD_DIR/module-cache"
TARGET_TRIPLE="${TWMP_SWIFT_TARGET:-$(uname -m)-apple-macosx13.0}"
mkdir -p "$BUILD_DIR" "$MODULE_CACHE_DIR"

swiftc \
  -target "$TARGET_TRIPLE" \
  -module-cache-path "$MODULE_CACHE_DIR" \
  "$ROOT_DIR/Sources/TypingWithMyPetsCore/ConversationEngine.swift" \
  "$ROOT_DIR/Sources/TypingWithMyPetsCore/TypingEngine.swift" \
  "$ROOT_DIR/Tests/TypingWithMyPetsCoreSmoke/main.swift" \
  -o "$BUILD_DIR/TypingWithMyPetsCoreSmoke"

"$BUILD_DIR/TypingWithMyPetsCoreSmoke"
