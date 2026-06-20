#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/manual-tests"
mkdir -p "$BUILD_DIR"

swiftc \
  "$ROOT_DIR/Sources/TypingWithMyPetsCore/TypingEngine.swift" \
  "$ROOT_DIR/Tests/TypingWithMyPetsCoreSmoke/main.swift" \
  -o "$BUILD_DIR/TypingWithMyPetsCoreSmoke"

"$BUILD_DIR/TypingWithMyPetsCoreSmoke"
